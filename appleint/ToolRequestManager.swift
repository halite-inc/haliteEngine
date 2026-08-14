import Foundation
import Observation
import SwiftUI

@Observable
public final class ToolRequestManager {
    // Current active tool request
    public var activeRequest: ToolRequest?
    /// The conversation that opened the request. Tool completion must never
    /// depend on whichever chat happens to be selected later.
    public var activeRequestThreadId: UUID?
    
    // True between user submitting form and AI first token arriving
    public private(set) var processingThreadIds: Set<UUID> = []
    public var isProcessing: Bool { !processingThreadIds.isEmpty }

    public func isProcessing(threadId: UUID) -> Bool {
        processingThreadIds.contains(threadId)
    }

    public func beginProcessing(threadId: UUID?) {
        guard let threadId else { return }
        processingThreadIds.insert(threadId)
    }

    public func finishProcessing(threadId: UUID) {
        processingThreadIds.remove(threadId)
    }
    
    // Collected values dictionary: field ID -> string representation
    public var collectedValues: [String: String] = [:]
    
    // Navigation for sequential flow
    public var currentFieldIndex: Int = 0
    public var showGeneratedBlocks: Bool = false
    
    // Callbacks
    public var onSubmitResponse: ((String, String) -> Void)?
    public var onCancel: (() -> Void)?
    public var onGenerateBlocks: (() -> Void)?
    
    // Dynamic binding helper for SwiftUI fields
    public func binding(for fieldId: String) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.collectedValues[fieldId] ?? ""
            },
            set: { [weak self] newValue in
                self?.collectedValues[fieldId] = newValue
            }
        )
    }
    
    // Initialize or load a new request
    public func loadRequest(_ request: ToolRequest, threadId: UUID) {
        self.activeRequest = request
        self.activeRequestThreadId = threadId
        self.collectedValues = [:]
        self.currentFieldIndex = 0
        self.processingThreadIds.remove(threadId)
        
        // Initialize fields from request defaults only. Durable user context is
        // handled exclusively by Advanced Memory.
        for field in request.fields {
            switch field.type {
                case .slider, .stepper:
                    let defaultVal = field.min ?? 0.0
                    self.collectedValues[field.id] = String(defaultVal)
                case .boolean:
                    self.collectedValues[field.id] = "false"
                case .date:
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    self.collectedValues[field.id] = formatter.string(from: Date())
                case .time:
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm"
                    self.collectedValues[field.id] = formatter.string(from: Date())
                default:
                    self.collectedValues[field.id] = ""
            }
        }
        
        if request.fields.isEmpty {
            submitResponse()
        }
    }
    
    // Proceed to next field in sequential flow
    public func nextField() {
        guard let request = activeRequest else { return }
        
        let nextIndex = currentFieldIndex + 1
        if nextIndex < request.fields.count {
            currentFieldIndex = nextIndex
        } else {
            submitResponse()
        }
    }
    
    // Go back to previous field in sequential flow
    public func previousField() {
        if currentFieldIndex > 0 {
            currentFieldIndex -= 1
        }
    }
    
    // Directly set field value and auto-advance
    public func selectValue(_ value: String, forField fieldId: String) {
        guard let request = activeRequest else { return }
        
        collectedValues[fieldId] = value
        
        if request.mode == .sequential {
            let nextIndex = currentFieldIndex + 1
            if nextIndex < request.fields.count {
                currentFieldIndex = nextIndex
            } else {
                submitResponse()
            }
        }
    }
    
    // Submit the collected response back
    public func submitResponse() {
        guard let request = activeRequest else { return }
        
        var responseDict: [String: Any] = [:]
        var textSummaryItems: [String] = []
        
        for field in request.fields {
            let valString = collectedValues[field.id] ?? ""
            
            // Format output type based on field definition
            switch field.type {
            case .number, .slider, .stepper:
                if let valDouble = Double(valString) {
                    if valDouble == Double(Int(valDouble)) {
                        responseDict[field.id] = Int(valDouble)
                    } else {
                        responseDict[field.id] = valDouble
                    }
                } else {
                    responseDict[field.id] = valString
                }
            case .boolean:
                responseDict[field.id] = (valString.lowercased() == "true")
            case .multipleChoice:
                let array = valString.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                responseDict[field.id] = array
            default:
                responseDict[field.id] = valString
            }
            
            // Reconstruct text version for smaller on-device models
            let displayVal = valString
            let unitStr = field.unit.map { " \($0)" } ?? ""
            textSummaryItems.append("- \(field.label): \(displayVal)\(unitStr)")
        }
        
        let payload: [String: Any] = ["tool_response": responseDict]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            clearActiveRequest()
            return
        }
        
        let summaryText = textSummaryItems.joined(separator: "\n")
        let naturalLanguagePrompt = """
        [System: User has submitted the requested information for "\(request.title)"]:
        \(summaryText)
        
        Please process this data and continue the conversation.
        """
        
        beginProcessing(threadId: activeRequestThreadId)
        onSubmitResponse?(jsonString, naturalLanguagePrompt)
        clearActiveRequest()
    }
    
    public func cancel() {
        onCancel?()
        clearActiveRequest()
    }
    
    public func clearActiveRequest() {
        activeRequest = nil
        activeRequestThreadId = nil
        collectedValues = [:]
        currentFieldIndex = 0
        showGeneratedBlocks = false
        // isProcessing stays true until AI starts responding — cleared by ChatManager
    }
    
    public func generateBlocks() {
        showGeneratedBlocks = true
    }
    
    public func generateHTML(for request: ToolRequest, values: [String: String]) -> String {
        let themeBg = "transparent"
        let themeText = "#ffffff"
        let cardBg = "rgba(255, 255, 255, 0.04)"
        let cardBorder = "rgba(255, 255, 255, 0.08)"
        
        var inputsHTML = ""
        var jsCalculations = ""
        var outputsHTML = ""
        
        let titleLower = request.title.lowercased()
        if titleLower.contains("weight") || titleLower.contains("timeline") || titleLower.contains("surplus") {
            let initialSurplus = values["surplus"] ?? "600"
            let initialKg: String = {
                if let target = Double(values["target_weight"] ?? ""),
                   let current = Double(values["weight"] ?? ""),
                   target > current {
                    return String(format: "%.1f", target - current)
                }
                return values["kg_to_gain"] ?? "6"
            }()
            
            inputsHTML = """
            <div class="inputs-grid">
                <div class="input-box">
                    <label for="kg_to_gain">Kg to gain</label>
                    <input type="range" id="kg_to_gain" min="1" max="25" step="0.5" value="\(initialKg)" oninput="calculate()">
                    <div class="value-display">Target: <span id="kg_to_gain-val">\(initialKg)</span> kg</div>
                </div>
                <div class="input-box">
                    <label for="surplus">Daily surplus (kcal)</label>
                    <input type="range" id="surplus" min="200" max="1000" step="50" value="\(initialSurplus)" oninput="calculate()">
                    <div class="value-display"><span id="surplus-val">\(initialSurplus)</span> kcal/day</div>
                </div>
            </div>
            """
            
            outputsHTML = """
            <div class="outputs-grid">
                <div class="output-card">
                    <div class="title">Time to reach goal</div>
                    <div class="value" id="weeks-needed">11 weeks</div>
                </div>
                <div class="output-card">
                    <div class="title">Estimated date</div>
                    <div class="value" id="estimated-date">26 Sept 2026</div>
                </div>
            </div>
            <div class="chart-container">
                <canvas id="chartCanvas"></canvas>
            </div>
            """
            
            jsCalculations = """
            function calculate() {
                var kgToGain = parseFloat(document.getElementById('kg_to_gain').value);
                var surplus = parseFloat(document.getElementById('surplus').value);
                
                document.getElementById('kg_to_gain-val').innerText = kgToGain;
                document.getElementById('surplus-val').innerText = surplus;
                
                var weeklyGain = (surplus * 7) / 7700;
                var weeks = kgToGain / weeklyGain;
                
                document.getElementById('weeks-needed').innerText = Math.round(weeks) + " weeks";
                document.getElementById('estimated-date').innerText = getEstimatedDate(weeks);
                
                drawChart(kgToGain, surplus, weeks);
            }
            
            function getEstimatedDate(weeks) {
                var now = new Date();
                var days = Math.round(weeks * 7);
                now.setDate(now.getDate() + days);
                
                var day = now.getDate();
                var months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                var month = months[now.getMonth()];
                var year = now.getFullYear();
                return day + " " + month + " " + year;
            }
            
            function drawChart(kgToGain, surplusVal, weeksVal) {
                var canvas = document.getElementById('chartCanvas');
                var ctx = canvas.getContext('2d');
                
                var dpr = window.devicePixelRatio || 1;
                var rect = canvas.getBoundingClientRect();
                canvas.width = rect.width * dpr;
                canvas.height = rect.height * dpr;
                ctx.scale(dpr, dpr);
                
                var w = rect.width;
                var h = rect.height;
                
                ctx.clearRect(0, 0, w, h);
                
                var minSurplus = 200;
                var maxSurplus = 1000;
                var minWeeks = 5;
                var maxWeeks = 35;
                
                var paddingLeft = 35;
                var paddingRight = 15;
                var paddingTop = 15;
                var paddingBottom = 25;
                
                var graphWidth = w - paddingLeft - paddingRight;
                var graphHeight = h - paddingTop - paddingBottom;
                
                function getX(surplus) {
                    return paddingLeft + ((surplus - minSurplus) / (maxSurplus - minSurplus)) * graphWidth;
                }
                
                function getY(weeks) {
                    var ratio = (weeks - minWeeks) / (maxWeeks - minWeeks);
                    if (ratio < 0) ratio = 0;
                    if (ratio > 1) ratio = 1;
                    return paddingTop + graphHeight - ratio * graphHeight;
                }
                
                // Grid lines and Y axis labels
                ctx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
                ctx.lineWidth = 1;
                ctx.fillStyle = '#8e8e93';
                ctx.font = '9px -apple-system';
                ctx.textAlign = 'right';
                ctx.textBaseline = 'middle';
                
                var yMarkings = [5, 10, 15, 20, 25, 30, 35];
                yMarkings.forEach(function(val) {
                    var py = getY(val);
                    ctx.beginPath();
                    ctx.moveTo(paddingLeft, py);
                    ctx.lineTo(w - paddingRight, py);
                    ctx.stroke();
                    
                    ctx.fillText(val, paddingLeft - 6, py);
                });
                
                // X axis labels
                ctx.textAlign = 'center';
                ctx.textBaseline = 'top';
                var xMarkings = [200, 320, 440, 560, 680, 800, 920];
                xMarkings.forEach(function(val) {
                    var px = getX(val);
                    ctx.fillText(val, px, paddingTop + graphHeight + 6);
                });
                
                // Y-Axis title
                ctx.save();
                ctx.translate(10, paddingTop + graphHeight / 2);
                ctx.rotate(-Math.PI / 2);
                ctx.textAlign = 'center';
                ctx.fillText('Weeks needed', 0, 0);
                ctx.restore();
                
                // X-Axis title
                ctx.fillText('Daily surplus (kcal)', paddingLeft + graphWidth / 2, h - 10);
                
                // Draw curve path
                ctx.beginPath();
                for (var s = minSurplus; s <= maxSurplus; s += 5) {
                    var weeklyGain = (s * 7) / 7700;
                    var weeks = kgToGain / weeklyGain;
                    var px = getX(s);
                    var py = getY(weeks);
                    if (s === minSurplus) {
                        ctx.moveTo(px, py);
                    } else {
                        ctx.lineTo(px, py);
                    }
                }
                
                ctx.strokeStyle = '#007aff';
                ctx.lineWidth = 2;
                ctx.stroke();
                
                // Fill area under curve
                ctx.lineTo(getX(maxSurplus), paddingTop + graphHeight);
                ctx.lineTo(getX(minSurplus), paddingTop + graphHeight);
                ctx.closePath();
                ctx.fillStyle = 'rgba(0, 122, 255, 0.08)';
                ctx.fill();
                
                // Draw red dot for selected values
                var cx = getX(surplusVal);
                var cy = getY(weeksVal);
                
                ctx.beginPath();
                ctx.arc(cx, cy, 6, 0, 2 * Math.PI);
                ctx.fillStyle = '#ff3b30'; // Red dot
                ctx.fill();
                
                ctx.beginPath();
                ctx.arc(cx, cy, 6, 0, 2 * Math.PI);
                ctx.strokeStyle = '#ffffff'; // White border
                ctx.lineWidth = 1.5;
                ctx.stroke();
            }
            """
        } else if titleLower.contains("bmr") || titleLower.contains("calorie") {
            let initialAge = values["age"] ?? "25"
            let initialWeight = values["weight"] ?? "70"
            
            inputsHTML = """
            <div class="inputs-grid">
                <div class="input-box">
                    <label for="age">Age</label>
                    <input type="range" id="age" min="1" max="100" value="\(initialAge)" oninput="calculate()">
                    <div class="value-display"><span id="age-val">\(initialAge)</span> years</div>
                </div>
                <div class="input-box">
                    <label for="weight">Weight</label>
                    <input type="range" id="weight" min="30" max="150" value="\(initialWeight)" oninput="calculate()">
                    <div class="value-display"><span id="weight-val">\(initialWeight)</span> kg</div>
                </div>
            </div>
            """
            
            outputsHTML = """
            <div class="outputs-grid" style="grid-template-columns: repeat(3, 1fr);">
                <div class="output-card">
                    <div class="title">BMR</div>
                    <div class="value" id="bmr-val">1650 kcal</div>
                </div>
                <div class="output-card">
                    <div class="title">Sedentary</div>
                    <div class="value" id="sedentary-val">1980 kcal</div>
                </div>
                <div class="output-card">
                    <div class="title">Active</div>
                    <div class="value" id="active-val">2550 kcal</div>
                </div>
            </div>
            """
            
            jsCalculations = """
            function calculate() {
                var age = parseFloat(document.getElementById('age').value);
                var weight = parseFloat(document.getElementById('weight').value);
                document.getElementById('age-val').innerText = age;
                document.getElementById('weight-val').innerText = weight;
                
                var bmr = 10 * weight + 6.25 * 175 - 5 * age + 5;
                document.getElementById('bmr-val').innerText = Math.round(bmr) + " kcal";
                document.getElementById('sedentary-val').innerText = Math.round(bmr * 1.2) + " kcal";
                document.getElementById('active-val').innerText = Math.round(bmr * 1.55) + " kcal";
            }
            """
        } else {
            // Generic dynamic block list
            var fieldsInputs = ""
            var fieldIds: [String] = []
            
            for field in request.fields {
                let initialVal = values[field.id] ?? String(field.min ?? 0.0)
                if field.type == .slider || field.type == .number {
                    fieldIds.append(field.id)
                    let minVal = field.min ?? 0.0
                    let maxVal = field.max ?? 100.0
                    let stepVal = field.step ?? 1.0
                    fieldsInputs += """
                    <div class="input-box">
                        <label for="\(field.id)">\(field.label)</label>
                        <input type="range" id="\(field.id)" min="\(minVal)" max="\(maxVal)" step="\(stepVal)" value="\(initialVal)" oninput="calculate()">
                        <div class="value-display"><span id="\(field.id)-val">\(initialVal)</span></div>
                    </div>
                    """
                }
            }
            
            inputsHTML = """
            <div class="inputs-grid">
                \(fieldsInputs)
            </div>
            """
            
            outputsHTML = """
            <div class="outputs-grid">
                <div class="output-card">
                    <div class="title">Sum</div>
                    <div class="value" id="calc-sum">0</div>
                </div>
                <div class="output-card">
                    <div class="title">Scaled (x1.5)</div>
                    <div class="value" id="calc-scaled">0</div>
                </div>
            </div>
            """
            
            let jsSumArray = "[" + fieldIds.map { "parseFloat(document.getElementById('" + $0 + "').value)" }.joined(separator: ", ") + "]"
            let jsSetValues = fieldIds.map { "document.getElementById('" + $0 + "-val').innerText = document.getElementById('" + $0 + "').value;" }.joined(separator: "\n")
            
            jsCalculations = """
            function calculate() {
                \(jsSetValues)
                var vals = \(jsSumArray);
                var sum = vals.reduce((a, b) => a + b, 0);
                document.getElementById('calc-sum').innerText = sum.toFixed(1);
                document.getElementById('calc-scaled').innerText = (sum * 1.5).toFixed(1);
            }
            """
        }
        
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    background-color: \(themeBg);
                    color: \(themeText);
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    margin: 0;
                    padding: 4px;
                    font-size: 13px;
                }
                .container {
                    max-width: 100%;
                }
                .inputs-grid {
                    display: grid;
                    grid-template-columns: 1fr 1fr;
                    gap: 12px;
                    margin-bottom: 12px;
                }
                .input-box {
                    background: \(cardBg);
                    border: 1px solid \(cardBorder);
                    border-radius: 8px;
                    padding: 8px 10px;
                }
                .input-box label {
                    display: block;
                    font-size: 11px;
                    font-weight: 500;
                    color: #8e8e93;
                    text-transform: uppercase;
                    letter-spacing: 0.5px;
                    margin-bottom: 4px;
                }
                input[type="range"] {
                    width: 100%;
                    margin: 8px 0;
                    accent-color: #007aff;
                    background: rgba(255, 255, 255, 0.1);
                    height: 4px;
                    border-radius: 2px;
                    appearance: none;
                }
                .value-display {
                    font-size: 13px;
                    font-weight: 600;
                    color: #ffffff;
                    margin-top: 4px;
                }
                .outputs-grid {
                    display: grid;
                    grid-template-columns: 1fr 1fr;
                    gap: 12px;
                    margin-bottom: 12px;
                }
                .output-card {
                    background: \(cardBg);
                    border: 1px solid \(cardBorder);
                    border-radius: 10px;
                    padding: 12px;
                }
                .output-card .title {
                    font-size: 10px;
                    color: #8e8e93;
                    text-transform: uppercase;
                    letter-spacing: 0.5px;
                    margin-bottom: 4px;
                }
                .output-card .value {
                    font-size: 20px;
                    font-weight: 700;
                    color: #ffffff;
                }
                .chart-container {
                    width: 100%;
                    height: 140px;
                    background: rgba(0, 0, 0, 0.2);
                    border-radius: 10px;
                    border: 1px solid \(cardBorder);
                    padding: 8px;
                    box-sizing: border-box;
                }
                canvas {
                    width: 100%;
                    height: 100%;
                    display: block;
                }
            </style>
        </head>
        <body onload="calculate()">
            <div class="container">
                \(inputsHTML)
                \(outputsHTML)
            </div>
            <script>
                \(jsCalculations)
            </script>
        </body>
        </html>
        """
        
        return html
    }
}
