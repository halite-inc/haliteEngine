import SwiftUI

struct ToolCardView: View {
    @Bindable var manager: ToolRequestManager
    
    var body: some View {
        if let request = manager.activeRequest {
            VStack(alignment: .leading, spacing: 0) {
                // Modern Apple-Native Header Bar
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: request.type == "file_system" ? "folder.fill" : (request.type == "advanced_memory" ? "brain.head.profile" : "slider.horizontal.3"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(request.type == "advanced_memory" ? Color.secondary : Color.blue)
                        .frame(width: 28, height: 28)
                        .background(request.type == "advanced_memory" ? Color.secondary.opacity(0.12) : Color.blue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.displayTitle.isEmpty ? "Input Required" : request.displayTitle)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(request.type == "advanced_memory" ? .secondary : .primary)
                        
                        if request.type != "advanced_memory" && !request.description.isEmpty {
                            Text(request.description)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer(minLength: 8)
                    
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            manager.cancel()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)
                
                Divider()
                    .opacity(0.12)
                
                // Form vs Sequential Content
                if request.mode == .form {
                    formContent(request: request)
                } else {
                    sequentialContent(request: request)
                }
            }
            .frame(maxWidth: 380)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 14, x: 0, y: 6)
        }
    }
    
    @ViewBuilder
    private func formContent(request: ToolRequest) -> some View {
        let nonSliderFields = request.fields.filter { $0.type != .slider }
        
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(nonSliderFields) { field in
                    ToolFieldView(field: field, manager: manager)
                }
            }
            .padding(14)
            
            Divider()
                .opacity(0.12)
            
            // Form Footer Action Bar
            HStack {
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        manager.submitResponse()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text("Continue")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 13))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color.blue)
                            .shadow(color: Color.blue.opacity(0.3), radius: 5, x: 0, y: 2)
                    )
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.02))
        }
    }
    
    @ViewBuilder
    private func sequentialContent(request: ToolRequest) -> some View {
        let nonSliderFields = request.fields.filter { $0.type != .slider }
        let index = manager.currentFieldIndex
        if index < nonSliderFields.count {
            let field = nonSliderFields[index]
            
            VStack(alignment: .leading, spacing: 0) {
                // Main field content
                VStack(alignment: .leading, spacing: 8) {
                    ToolFieldView(field: field, manager: manager)
                }
                .padding(14)
                
                Divider()
                    .opacity(0.12)
                
                // Sequential Progress and Navigation Footer
                HStack(alignment: .center) {
                    // Progress text & indicator
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Step \(index + 1) of \(nonSliderFields.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        
                        // Mini progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.secondary.opacity(0.15))
                                    .frame(height: 3)
                                
                                Capsule()
                                    .fill(Color.blue)
                                    .frame(width: geo.size.width * CGFloat(index + 1) / CGFloat(nonSliderFields.count), height: 3)
                            }
                        }
                        .frame(width: 70, height: 3)
                    }
                    
                    Spacer()
                    
                    // Back / Next / Done Buttons
                    HStack(spacing: 8) {
                        if index > 0 {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    manager.previousField()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text("Back")
                                }
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.primary.opacity(0.06))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // Next/Submit button
                        let isLast = (index == nonSliderFields.count - 1)
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                manager.nextField()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(isLast ? "Submit" : "Next")
                                    .font(.system(size: 13, weight: .semibold))
                                if !isLast {
                                    Image(systemName: "chevron.right")
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(isLast ? Color.blue : Color.primary.opacity(0.1))
                            .foregroundStyle(isLast ? .white : .primary)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.02))
            }
        }
    }
}
