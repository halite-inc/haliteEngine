import SwiftUI

struct ToolFieldView: View {
    let field: ToolField
    @Bindable var manager: ToolRequestManager
    
    // Manage custom input visibility locally for modular form support
    @State private var showCustomInput: Bool = false
    
    // Bindings computed from the manager's dictionary
    private var textBinding: Binding<String> {
        manager.binding(for: field.id)
    }
    
    private var dateBinding: Binding<Date> {
        Binding(
            get: {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                let text = manager.collectedValues[field.id] ?? ""
                return formatter.date(from: text) ?? Date()
            },
            set: { newDate in
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                manager.collectedValues[field.id] = formatter.string(from: newDate)
            }
        )
    }
    
    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                let text = manager.collectedValues[field.id] ?? ""
                return formatter.date(from: text) ?? Date()
            },
            set: { newTime in
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                manager.collectedValues[field.id] = formatter.string(from: newTime)
            }
        )
    }
    
    private var multipleChoiceBinding: Binding<Set<String>> {
        Binding(
            get: {
                let text = manager.collectedValues[field.id] ?? ""
                if text.isEmpty { return [] }
                return Set(text.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
            },
            set: { newSet in
                manager.collectedValues[field.id] = Array(newSet).joined(separator: ",")
            }
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Label & Required Indicator
            HStack(spacing: 4) {
                Text(field.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                
                if field.isRequired {
                    Text("*")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.red)
                }
            }
            
            // Check if field has suggestions and custom input is NOT yet activated
            if let suggestions = field.suggestions, !suggestions.isEmpty, !showCustomInput {
                suggestionsView(suggestions)
            } else {
                customInputView
            }
        }
        .onAppear {
            // If the field does not have suggestions, or custom is the only option, force custom mode
            if field.suggestions == nil || field.suggestions?.isEmpty == true {
                showCustomInput = true
            }
        }
    }
    
    // MARK: - Suggestions Layout
    @ViewBuilder
    private func suggestionsView(_ suggestions: [SuggestionItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Render suggestions
                    ForEach(suggestions) { item in
                        let isCurrent = (manager.collectedValues[field.id] == item.value)
                        
                        Button {
                            withAnimation(.spring(duration: 0.3)) {
                                manager.selectValue(item.value, forField: field.id)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if isCurrent {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                
                                Text(item.displayLabel)
                                    .fontWeight(isCurrent ? .bold : .medium)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(isCurrent ? Color.blue : Color.primary.opacity(0.06))
                            )
                            .foregroundStyle(isCurrent ? .white : .primary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .hoverEffect()
                    }
                    
                    // Custom Button
                    if field.isCustomAllowed {
                        Button {
                            withAnimation(.spring(duration: 0.3)) {
                                showCustomInput = true
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 10))
                                Text("Custom...")
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.primary.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
                        .hoverEffect()
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
    
    // MARK: - Custom Controls
    @ViewBuilder
    private var customInputView: some View {
        switch field.type {
        case .number, .text:
            HStack(spacing: 0) {
                TextField(field.placeholder ?? (field.type == .number ? "Enter number" : "Enter text"), text: textBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                
                if let unit = field.unit, !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(unit)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(5)
                        .padding(.trailing, 5)
                }
                
                if field.suggestions != nil {
                    backToSuggestionsButton
                        .padding(.trailing, 6)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
                
        case .singleChoice:
            VStack(alignment: .leading, spacing: 6) {
                let items = field.suggestions ?? []
                ForEach(items) { item in
                    let isSelected = (textBinding.wrappedValue == item.value)
                    Button {
                        textBinding.wrappedValue = item.value
                    } label: {
                        HStack {
                            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(isSelected ? Color.blue : Color.secondary)
                            Text(item.displayLabel)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            
        case .multipleChoice:
            VStack(alignment: .leading, spacing: 6) {
                let items = field.suggestions ?? []
                ForEach(items) { item in
                    let isChecked = multipleChoiceBinding.wrappedValue.contains(item.value)
                    Button {
                        if isChecked {
                            multipleChoiceBinding.wrappedValue.remove(item.value)
                        } else {
                            multipleChoiceBinding.wrappedValue.insert(item.value)
                        }
                    } label: {
                        HStack {
                            Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                                .foregroundStyle(isChecked ? Color.blue : Color.secondary)
                            Text(item.displayLabel)
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            
        case .boolean:
            Toggle(isOn: Binding(
                get: { textBinding.wrappedValue.lowercased() == "true" },
                set: { textBinding.wrappedValue = $0 ? "true" : "false" }
            )) {
                Text(field.placeholder ?? "Enable option")
            }
            .toggleStyle(.switch)
            
        case .date:
            DatePicker("", selection: dateBinding, displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                
        case .time:
            DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute)
                .datePickerStyle(.compact)
                .labelsHidden()
                
        case .slider:
            let minVal = field.min ?? 0.0
            let maxVal = field.max ?? 100.0
            let stepVal = field.step ?? 1.0
            let currentVal = Double(textBinding.wrappedValue) ?? minVal
            
            HStack(spacing: 8) {
                Slider(
                    value: Binding(
                        get: { currentVal },
                        set: { textBinding.wrappedValue = String(format: "%.1f", $0) }
                    ),
                    in: minVal...maxVal,
                    step: stepVal
                )
                
                Text(String(format: "%.1f", currentVal))
                    .font(.body.monospacedDigit())
                    .frame(width: 50, alignment: .trailing)
                
                if let unit = field.unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
        case .stepper:
            let minVal = field.min ?? 0.0
            let maxVal = field.max ?? 100.0
            let stepVal = field.step ?? 1.0
            let currentVal = Double(textBinding.wrappedValue) ?? minVal
            
            HStack(spacing: 12) {
                Stepper(value: Binding(
                    get: { currentVal },
                    set: { textBinding.wrappedValue = String(format: "%.1f", $0) }
                ), in: minVal...maxVal, step: stepVal) {
                    Text(String(format: "%.1f", currentVal))
                        .font(.body.monospacedDigit())
                }
                
                if let unit = field.unit {
                    Text(unit)
                        .foregroundStyle(.secondary)
                }
            }
            
        case .dropdown:
            Picker("", selection: textBinding) {
                Text("Select an option...").tag("")
                let items = field.suggestions ?? []
                ForEach(items) { item in
                    Text(item.displayLabel).tag(item.value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            
        case .insight:
            EmptyView()
        }
    }
    
    private var backToSuggestionsButton: some View {
        Button {
            withAnimation(.spring(duration: 0.3)) {
                showCustomInput = false
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 10))
                Text("Suggestions")
                    .font(.caption)
            }
            .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
    }
}
