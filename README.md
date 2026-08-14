<div align="center">

<img src="halite.png" alt="Halite Logo" width="96" height="96" />

# Halite

### **The Native macOS AI Engine & Autonomous Agent Workspace**
*Supercharged with Model Context Protocol (MCP), Persistent Memory Graph, Local & Cloud LLMs, and Grounded Web Intelligence.*

[![Platform](https://img.shields.io/badge/Platform-macOS%2014.0%2B-blue?style=for-the-badge&logo=apple)](https://github.com/halite-inc/haliteEngine)
[![Language](https://img.shields.io/badge/Swift-5.10%20%7C%20SwiftUI-orange?style=for-the-badge&logo=swift)](https://swift.org)
[![MCP Ready](https://img.shields.io/badge/Protocol-Model%20Context%20Protocol%20(MCP)-purple?style=for-the-badge)](https://modelcontextprotocol.io)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)
[![GitHub release](https://img.shields.io/github/v/release/halite-inc/haliteEngine?style=for-the-badge&color=cyan)](https://github.com/halite-inc/haliteEngine/releases)

---

[**Download Ready-to-Use DMG**](https://github.com/halite-inc/haliteEngine/releases/latest) • [**Key Features**](#-key-features) • [**MCP Guide**](#-model-context-protocol-mcp) • [**Building from Source**](#-build-from-source) • [**Documentation**](https://github.com/halite-inc/haliteEngine)

---

</div>

<br/>

## 🌟 Overview

**Halite** is an ultra-fast, native macOS artificial intelligence workstation and autonomous agent engine. Built completely with **Swift** and **SwiftUI** for maximum performance and zero Electron bloat, Halite bridges local inference (Apple Silicon GPUs via LM Studio) with frontier cloud intelligence (OpenRouter, Groq, OpenAI), extensible tools via **Model Context Protocol (MCP)**, persistent graph memory, and live grounded internet synthesis.

<br/>

```
                     ┌────────────────────────────────────────┐
                     │          Halite Native Engine          │
                     └───────────────────┬────────────────────┘
                                         │
     ┌───────────────────┬───────────────┴───────────────┬───────────────────┐
     ▼                   ▼                               ▼                   ▼
┌──────────────┐  ┌──────────────┐               ┌──────────────┐     ┌──────────────┐
│  Local GPUs  │  │ Cloud LLMs   │               │ MCP Servers  │     │  Memory &    │
│  (LM Studio) │  │ (OpenRouter, │               │ (Filesystem, │     │  Knowledge   │
│  Offline     │  │  Groq, OAI)  │               │  Fetch, DBs) │     │  Graph Engine│
└──────────────┘  └──────────────┘               └──────────────┘     └──────────────┘
```

<br/>

## 🚀 Key Features

### 🔌 1. Model Context Protocol (MCP) Superpowers
- **Native JSON-RPC 2.0 Stdio & SSE Transport**: Connect any MCP server (Filesystem, Fetch, SQLite, Postgres, Memory Graph, Puppeteer, GitHub, etc.) with zero setup friction.
- **In-App `mcp.json` Editor**: Full-featured code editor inside **Space → MCP** with live syntax validation, auto-formatting, and pre-packaged server templates.
- **Dynamic Tool Dispatch**: LLMs automatically discover tools provided by all connected MCP servers and execute them deterministically with real-time transcript streaming.

### ⚡ 2. Pure Native Apple Silicon Performance
- **Swift & SwiftUI**: 60fps glassmorphism interface, instant cold starts, and minimal battery footprint.
- **Universal Multi-Provider Architecture**: Effortlessly switch between local offline models (Gemma, Llama 3, Mistral, Qwen via LM Studio) and cloud speed (Groq LPU, OpenRouter, GPT-4o, Claude 3.5).

### 🧠 3. Persistent Knowledge Graph Memory & Self-Learning
- **Autonomous Entity-Relationship Memory**: Automatically extracts personal context, preferences, and entity connections across conversations into a durable Knowledge Graph.
- **Verified Self-Learning Loop**: Discovers operational fixes, behavioral rules, and reusable workflows without leaking raw chat transcripts.

### 🌐 4. Deep Multi-Link Grounded Web Search
- **Guaranteed Verification**: Automatically fetches and verifies minimum 3 domain-diverse primary sources per research request.
- **Interactive Sources Panel**: Shift-click or tap the sources badge to open the dedicated research panel with summary previews and direct URL navigation.

### 🛠️ 5. Terminal & File System Execution
- **Autonomous File Management**: Create, inspect, edit, and organize files and directories in your workspace.
- **Safe Shell Execution**: Runs verified command lines with deterministic status monitoring and activity tracking.

### 🔄 6. 1-Click In-App Updates & Automated CI/CD
- **Built-in Update Engine**: Check for updates directly inside the Settings modal with instant release notes, improvements, and bug fixes.
- **Automated GitHub Pipeline**: 1-command deployment (`./scripts/release.sh 1.0.1 "..."`) builds and distributes updates to all running apps worldwide.

<br/>

---

## 📦 Installation

### Option 1: Direct Download (DMG)
1. Download the latest **[`Halite.dmg`](https://github.com/halite-inc/haliteEngine/releases/latest)** from the Releases page.
2. Open the disk image and drag **Halite** to your `Applications` folder.
3. Launch **Halite** and start exploring!

### Option 2: Build from Source
Ensure you have **Xcode 15+** installed on macOS Sonoma or newer:

```bash
# Clone the repository
git clone https://github.com/halite-inc/haliteEngine.git
cd haliteEngine

# Build the Release application bundle
xcodebuild -project appleint.xcodeproj -scheme appleint -configuration Release build

# Or generate a fresh installer DMG
mkdir -p build/dmg_staging
cp -R build/DerivedData/Build/Products/Release/appleint.app build/dmg_staging/Halite.app
ln -s /Applications build/dmg_staging/Applications
hdiutil create -volname "Halite" -srcfolder build/dmg_staging -ov -format UDZO Halite.dmg
```

<br/>

---

## 🛠️ Model Context Protocol (`mcp.json`)

Halite follows the industry-standard MCP configuration format (compatible with LM Studio and Claude Desktop). Configure your servers directly in **Space → MCP** or edit `~/Library/Application Support/appleint/mcp.json`:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/Users/yourname/Desktop"]
    },
    "fetch": {
      "command": "uvx",
      "args": ["mcp-server-fetch"]
    },
    "sqlite": {
      "command": "uvx",
      "args": ["mcp-server-sqlite", "--db-path", "/Users/yourname/database.db"]
    },
    "custom-remote": {
      "url": "https://mcp-server.example.com/sse"
    }
  }
}
```

<br/>

---

## 🚀 Publishing Updates (For Developers)

Halite includes an automated deployment pipeline. To release an update with new features and fixes to all users:

```bash
./scripts/release.sh 1.0.1 "### Improvements & Fixes
- Added Model Context Protocol (MCP) server support
- Added in-app Check for Updates button in Settings
- Web search now guarantees minimum 3 verified links
- Performance optimizations for Apple Silicon M-series"
```

This single command stages changes, tags the release, pushes to GitHub, triggers the automated GitHub Actions compiler, and distributes the update package.

<br/>

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Cmd + K` | Clear Chat / New Thread |
| `Cmd + ,` / `Cmd + S` | Open Settings & Updates Modal |
| `Cmd + I` | Toggle Right Activity & Sources Sidebar |
| `Shift + Click Sources` | Open Web Search Deep Inspection Panel |
| `Cmd + Enter` | Send Message with Tool Routing |

<br/>

---

## 🤝 Contributing

Contributions, feature suggestions, and bug reports are warmly welcome!

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

<br/>

---

## 📄 License

Halite is distributed under the **MIT License**. See [`LICENSE`](LICENSE) for more information.

<div align="center">
  <sub>Crafted with ❤️ for macOS by the Halite Team. If you love Halite, give it a ⭐️ on GitHub!</sub>
</div>
