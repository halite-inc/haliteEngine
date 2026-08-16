import Foundation
import SwiftUI
import Combine
import AppKit

// MARK: - App Release Info Model

public struct AppReleaseInfo: Identifiable, Codable, Equatable {
    public var id: String { tagName }
    public let tagName: String
    public let version: String
    public let title: String
    public let changelog: String
    public let publishedAt: Date?
    public let downloadURL: URL?
    public let htmlURL: URL?
    public let isPrerelease: Bool

    public init(
        tagName: String,
        version: String,
        title: String,
        changelog: String,
        publishedAt: Date? = nil,
        downloadURL: URL? = nil,
        htmlURL: URL? = nil,
        isPrerelease: Bool = false
    ) {
        self.tagName = tagName
        self.version = version
        self.title = title
        self.changelog = changelog
        self.publishedAt = publishedAt
        self.downloadURL = downloadURL
        self.htmlURL = htmlURL
        self.isPrerelease = isPrerelease
    }
}

// MARK: - Update Check State

public enum UpdateCheckState: Equatable {
    case idle
    case checking
    case upToDate(currentVersion: String)
    case updateAvailable(AppReleaseInfo)
    case downloading(progress: Double)
    case readyToInstall(fileURL: URL, release: AppReleaseInfo)
    case installing
    case error(String)

    public var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }

    public var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }

    public var isInstalling: Bool {
        if case .installing = self { return true }
        return false
    }
}

// MARK: - Update Manager Singleton

@MainActor
public final class UpdateManager: ObservableObject {
    public static let shared = UpdateManager()

    @Published public var state: UpdateCheckState = .idle
    @Published public var lastCheckedDate: Date? = nil
    @Published public var autoCheckEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoCheckEnabled, forKey: "autoCheckForUpdates")
        }
    }

    public let repoOwner = "halite-inc"
    public let repoName = "haliteEngine"

    public var currentVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return version
    }

    public var currentBuild: String {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return build
    }

    private var downloadTask: URLSessionDownloadTask?
    private var downloadObservation: NSKeyValueObservation?

    private init() {
        self.autoCheckEnabled = UserDefaults.standard.object(forKey: "autoCheckForUpdates") as? Bool ?? true
        if let lastTimestamp = UserDefaults.standard.object(forKey: "lastUpdateCheckDate") as? Date {
            self.lastCheckedDate = lastTimestamp
        }

        if autoCheckEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                Task {
                    await self.checkForUpdates(silent: true)
                }
            }
        }
    }

    // MARK: - Check For Updates

    public func checkForUpdates(silent: Bool = false) async {
        if !silent {
            self.state = .checking
        }

        let apiURLString = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
        guard let url = URL(string: apiURLString) else {
            if !silent { self.state = .error("Invalid update API endpoint.") }
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Halite-Updater/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                if !silent { self.state = .error("Could not reach update server.") }
                return
            }

            if httpResponse.statusCode == 404 {
                // No releases published yet on GitHub repo
                self.lastCheckedDate = Date()
                UserDefaults.standard.set(self.lastCheckedDate, forKey: "lastUpdateCheckDate")
                self.state = .upToDate(currentVersion: currentVersion)
                return
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                if !silent { self.state = .error("GitHub API returned HTTP status \(httpResponse.statusCode).") }
                return
            }

            let release = try parseGitHubRelease(data: data)
            self.lastCheckedDate = Date()
            UserDefaults.standard.set(self.lastCheckedDate, forKey: "lastUpdateCheckDate")

            // Compare versions
            let isNewer = isVersion(release.version, newerThan: currentVersion)
            if isNewer {
                self.state = .updateAvailable(release)
            } else {
                self.state = .upToDate(currentVersion: currentVersion)
            }
        } catch {
            if !silent {
                self.state = .error("Update check failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Download & Install

    public func downloadUpdate(release: AppReleaseInfo) {
        guard let downloadURL = release.downloadURL ?? release.htmlURL else {
            self.state = .error("No valid download link found for this release.")
            return
        }

        // If direct binary asset is not a direct zip/dmg, open browser
        let isDirectAsset = downloadURL.absoluteString.hasSuffix(".dmg") || downloadURL.absoluteString.hasSuffix(".zip")
        if !isDirectAsset {
            NSWorkspace.shared.open(downloadURL)
            return
        }

        self.state = .downloading(progress: 0.0)

        let session = URLSession(configuration: .default)
        let task = session.downloadTask(with: downloadURL) { [weak self] tempLocalURL, response, error in
            Task { @MainActor in
                if let error {
                    self?.state = .error("Download failed: \(error.localizedDescription)")
                    return
                }

                guard let tempLocalURL else {
                    self?.state = .error("Downloaded file not found.")
                    return
                }

                do {
                    let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                    let ext = downloadURL.pathExtension.isEmpty ? "dmg" : downloadURL.pathExtension
                    let filename = "Halite-\(release.version).\(ext)"
                    let destinationURL = downloadsDir.appendingPathComponent(filename)
                    try? FileManager.default.removeItem(at: destinationURL)
                    try FileManager.default.copyItem(at: tempLocalURL, to: destinationURL)

                    self?.state = .readyToInstall(fileURL: destinationURL, release: release)
                } catch {
                    self?.state = .error("Could not save download: \(error.localizedDescription)")
                }
            }
        }

        self.downloadObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor in
                self?.state = .downloading(progress: progress.fractionCompleted)
            }
        }

        self.downloadTask = task
        task.resume()
    }

    public func installUpdate(fileURL: URL) {
        self.state = .installing

        let currentAppBundleURL = Bundle.main.bundleURL
        let currentAppPath = currentAppBundleURL.path
        let pid = ProcessInfo.processInfo.processIdentifier

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent("HaliteUpdateStaging_\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

                let ext = fileURL.pathExtension.lowercased()
                var extractedAppPath: String? = nil

                if ext == "zip" {
                    // Extract zip headlessly using ditto
                    let unzipProcess = Process()
                    unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                    unzipProcess.arguments = ["-xk", fileURL.path, stagingDir.path]
                    try unzipProcess.run()
                    unzipProcess.waitUntilExit()

                    if unzipProcess.terminationStatus == 0 {
                        let contents = try FileManager.default.contentsOfDirectory(at: stagingDir, includingPropertiesForKeys: nil)
                        if let appURL = contents.first(where: { $0.pathExtension == "app" }) {
                            extractedAppPath = appURL.path
                        }
                    }
                } else if ext == "dmg" {
                    // Mount DMG headlessly
                    let mountPoint = stagingDir.appendingPathComponent("mount")
                    try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

                    let attachProcess = Process()
                    attachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                    attachProcess.arguments = ["attach", fileURL.path, "-mountpoint", mountPoint.path, "-nobrowse", "-quiet", "-noautoopen"]
                    try attachProcess.run()
                    attachProcess.waitUntilExit()

                    if attachProcess.terminationStatus == 0 {
                        let contents = try? FileManager.default.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)
                        if let appURL = contents?.first(where: { $0.pathExtension == "app" }) {
                            let localAppCopy = stagingDir.appendingPathComponent(appURL.lastPathComponent)
                            let copyProcess = Process()
                            copyProcess.executableURL = URL(fileURLWithPath: "/bin/cp")
                            copyProcess.arguments = ["-R", appURL.path, localAppCopy.path]
                            try copyProcess.run()
                            copyProcess.waitUntilExit()
                            if copyProcess.terminationStatus == 0 {
                                extractedAppPath = localAppCopy.path
                            }
                        }

                        // Unmount
                        let detachProcess = Process()
                        detachProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                        detachProcess.arguments = ["detach", mountPoint.path, "-quiet", "-force"]
                        try? detachProcess.run()
                        detachProcess.waitUntilExit()
                    }
                }

                guard let newAppPath = extractedAppPath else {
                    Task { @MainActor in
                        // Fallback: reveal in Finder if automated extraction was not possible
                        self?.state = .readyToInstall(fileURL: fileURL, release: AppReleaseInfo(tagName: "", version: "", title: "", changelog: ""))
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                        NSWorkspace.shared.open(fileURL)
                    }
                    return
                }

                // Create helper updater script
                let scriptId = UUID().uuidString
                let updaterScriptPath = "/tmp/halite_updater_\(scriptId).sh"
                let scriptContent = """
                #!/bin/bash
                
                # Wait up to 3 seconds for app PID \(pid) to exit cleanly
                for i in {1..15}; do
                    if ! kill -0 \(pid) 2>/dev/null; then
                        break
                    fi
                    sleep 0.2
                done
                
                # Force kill PID if still alive
                kill -9 \(pid) 2>/dev/null || true
                sleep 0.3
                
                # Replace the target application bundle
                if [ -d "\(currentAppPath)" ]; then
                    rm -rf "\(currentAppPath)"
                fi
                
                /usr/bin/ditto "\(newAppPath)" "\(currentAppPath)"
                
                # Remove quarantine attribute
                /usr/bin/xattr -dr com.apple.quarantine "\(currentAppPath)" 2>/dev/null || true
                
                # Relaunch the new application
                /usr/bin/open "\(currentAppPath)"
                
                # Cleanup staging
                rm -rf "\(stagingDir.path)"
                rm -f "\(updaterScriptPath)"
                exit 0
                """

                try scriptContent.write(toFile: updaterScriptPath, atomically: true, encoding: .utf8)
                
                // Make script executable
                let chmodProcess = Process()
                chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
                chmodProcess.arguments = ["+x", updaterScriptPath]
                try chmodProcess.run()
                chmodProcess.waitUntilExit()

                // Launch updater script in background detached
                let launcherProcess = Process()
                launcherProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
                launcherProcess.arguments = ["-c", "nohup /bin/bash \"\(updaterScriptPath)\" >/tmp/halite_updater.log 2>&1 &"]
                try launcherProcess.run()

                // Immediately terminate the running app
                DispatchQueue.main.async {
                    NSApp.windows.forEach { $0.close() }
                    NSApp.terminate(nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        exit(0)
                    }
                }
            } catch {
                Task { @MainActor in
                    self?.state = .error("Failed to install update: \(error.localizedDescription)")
                }
            }
        }
    }

    public func openReleaseWebPage(release: AppReleaseInfo) {
        if let url = release.htmlURL {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - SemVer & Parsing Utilities

    public func isVersion(_ v1: String, newerThan v2: String) -> Bool {
        let clean1 = v1.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).trimmingCharacters(in: .whitespacesAndNewlines)
        let clean2 = v2.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).trimmingCharacters(in: .whitespacesAndNewlines)

        // Split off pre-release suffix (e.g. "1.0.1-beta.2" -> "1.0.1", "beta.2")
        let components1 = clean1.split(separator: "-", maxSplits: 1)
        let components2 = clean2.split(separator: "-", maxSplits: 1)
        let numeric1 = String(components1.first ?? "")
        let numeric2 = String(components2.first ?? "")
        let isPrerelease1 = components1.count > 1
        let isPrerelease2 = components2.count > 1

        let parts1 = numeric1.split(separator: ".").compactMap { Int($0) }
        let parts2 = numeric2.split(separator: ".").compactMap { Int($0) }

        let count = max(parts1.count, parts2.count)
        for i in 0..<count {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 > p2 { return true }
            if p1 < p2 { return false }
        }
        // Numeric parts are equal; a release (no suffix) is newer than a pre-release
        if !isPrerelease1 && isPrerelease2 { return true }
        return false
    }

    private func parseGitHubRelease(data: Data) throws -> AppReleaseInfo {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "UpdateManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response from GitHub."])
        }

        let tagName = (json["tag_name"] as? String) ?? "v1.0.0"
        let rawVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let name = (json["name"] as? String) ?? "Release \(tagName)"
        let body = (json["body"] as? String) ?? "No release notes provided."
        let htmlUrlStr = json["html_url"] as? String
        let isPrerelease = (json["prerelease"] as? Bool) ?? false

        var pubDate: Date? = nil
        if let pubDateStr = json["published_at"] as? String {
            let formatter = ISO8601DateFormatter()
            pubDate = formatter.date(from: pubDateStr)
        }

        // Find downloadable asset (.zip preferred for fast in-place update, fallback to .dmg)
        var downloadURL: URL? = nil
        if let assets = json["assets"] as? [[String: Any]] {
            // First priority: ZIP (Halite-macos.zip / appleint-macos.zip)
            for asset in assets {
                if let assetName = asset["name"] as? String,
                   assetName.hasSuffix(".zip"),
                   let downloadStr = asset["browser_download_url"] as? String,
                   let assetURL = URL(string: downloadStr) {
                    downloadURL = assetURL
                    break
                }
            }
            // Second priority: DMG
            if downloadURL == nil {
                for asset in assets {
                    if let assetName = asset["name"] as? String,
                       assetName.hasSuffix(".dmg"),
                       let downloadStr = asset["browser_download_url"] as? String,
                       let assetURL = URL(string: downloadStr) {
                        downloadURL = assetURL
                        break
                    }
                }
            }
        }

        return AppReleaseInfo(
            tagName: tagName,
            version: rawVersion,
            title: name,
            changelog: body,
            publishedAt: pubDate,
            downloadURL: downloadURL,
            htmlURL: htmlUrlStr.flatMap { URL(string: $0) },
            isPrerelease: isPrerelease
        )
    }
}
