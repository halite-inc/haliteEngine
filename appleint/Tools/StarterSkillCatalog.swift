import Foundation

/// Editable starter skills installed once into Space → Skills.
enum StarterSkillCatalog {
    static let installationKey = "AppleIntStarterSkillsV1Installed"
    static let exposedInstallationKey = "AppleIntExposedSkillsV1Installed"

    static let dynamicInputID = UUID(uuidString: "A2000001-0000-4000-8000-000000000001")!
    static let dynamicInsightsID = UUID(uuidString: "A2000002-0000-4000-8000-000000000002")!
    static let tesaractID = UUID(uuidString: "A2000003-0000-4000-8000-000000000003")!
    static let internetSearchID = UUID(uuidString: "A2000004-0000-4000-8000-000000000004")!
    static let advancedMemoryID = UUID(uuidString: "A2000005-0000-4000-8000-000000000005")!
    static let filesystemID = UUID(uuidString: "A2000006-0000-4000-8000-000000000006")!
    static let tasksID = UUID(uuidString: "A2000007-0000-4000-8000-000000000007")!
    private static let retiredCapabilityID = UUID(uuidString: "A2000008-0000-4000-8000-000000000008")!
    static let toolRouterID = UUID(uuidString: "A3000001-0000-4000-8000-000000000001")!
    static let personaID = UUID(uuidString: "A3000002-0000-4000-8000-000000000002")!
    static let learningID = UUID(uuidString: "A3000003-0000-4000-8000-000000000003")!
    static let reasoningID = UUID(uuidString: "A3000004-0000-4000-8000-000000000004")!
    static let directResponseID = UUID(uuidString: "A3000005-0000-4000-8000-000000000005")!
    static let crossCheckID = UUID(uuidString: "A3000006-0000-4000-8000-000000000006")!
    static let mandatorySearchID = UUID(uuidString: "A3000007-0000-4000-8000-000000000007")!
    static let performanceID = UUID(uuidString: "A3000008-0000-4000-8000-000000000008")!
    static let balancedID = UUID(uuidString: "A3000009-0000-4000-8000-000000000009")!

    static let evidenceFirstSearchRule = " EVIDENCE-FIRST PRIORITY: SOURCE-FIRST WEB DEFAULT. For every substantive knowledge request, retrieve current web evidence before answering. Formulate laser-focused keyword search targets; never use the user's whole sentence or conversational request as a query (e.g., search 'cashews walnuts raisins almonds nutrition facts per 100g USDA' rather than 'im gonna have 30g cashews... give me macros'). Decompose multi-entity requests when separate evidence is required, choose suited source types, and run independent focused queries. Perform all arithmetic, unit conversions, and macro/data calculations internally before responding. Deliver a direct, clean, authoritative final synthesis with a clear table or breakdown. NEVER expose internal scratchpad calculations, rough draft monologues, backtracking, or conflicting self-corrections ('Let's recalculate...', 'Wait...', 'Hypothesis:'). Ensure total sums match the itemized breakdown exactly."
    static let legacyLearningInstructions = "[LEARNING]\nAfter a confirmed error and verified fix, save one concise reusable prevention rule with advanced_memory; never save guesses or transient failures."
    static let previousLearningInstructions = "learning(action,learningId,content); actions: list,append,update,delete,clear. Use append only after an error and its fix are both confirmed by tool results or explicit user confirmation. Store one concise reusable prevention rule, never guesses, transient output, personal facts, or credentials. Use update/delete with the stable learningId returned by list. Personal facts and entity relationships belong in advanced_memory, not here.\n\n[LEARNED RULES]"
    static let previousTopiclessLearningInstructions = "learning(action,learningId,learningKind,content); actions: list,append,update,delete,clear; learningKind: rule or how-to. WHEN TO SAVE: use rule after a confirmed error and verified correction; use how-to when a task required multiple failed approaches or a long tool chain before a final method was verified. A hard-won How-to is mandatory after 2 or more failed tool attempts followed by success, or after 6 or more tool steps taking at least 60 seconds. Do not save ordinary first-try work, guesses, raw logs, transient errors, personal facts, or credentials. HOW TO SAVE OR UPDATE: call list first. If a learning already covers the same task, call update with its stable learningId; otherwise call append. A how-to must be self-contained and concise: state when it applies, required preconditions, the successful ordered steps, how to verify success, and the failed approach or pitfall to avoid. Record only the final proven method, without chain-of-thought. Never claim it was saved until the learning tool reports success. Personal facts and entity relationships belong in advanced_memory, not here.\n\n[LEARNED RULES]"
    static let previousDomainlessLearningInstructions = "learning(action,learningId,learningKind,learningTopic,content); actions: list,append,update,delete,clear; learningKind: rule or how-to; learningTopic: a specific 2–6 word subject heading such as Provider Recovery or Xcode Build Recovery. WHEN TO SAVE: use rule after a confirmed error and verified correction; use how-to when a task required multiple failed approaches or a long tool chain before a final method was verified. A hard-won How-to is mandatory after 2 or more failed tool attempts followed by success, or after 6 or more tool steps taking at least 60 seconds. Do not save ordinary first-try work, guesses, raw logs, transient errors, personal facts, or credentials. HOW TO SAVE OR UPDATE: call list first and use learningTopic to find the relevant subheading. If a learning already covers the same task, call update with its stable learningId and preserve or improve its topic; otherwise call append. Use one stable, descriptive topic across related learnings so they remain easy to retrieve. A how-to must be self-contained and concise: state when it applies, required preconditions, the successful ordered steps, how to verify success, and the failed approach or pitfall to avoid. Record only the final proven method, without chain-of-thought. Every successful append or update is written directly into this Learning skill under its visible topic subheading. Never claim it was saved until the learning tool reports success. Personal facts belong in advanced_memory.\n\n[LEARNED RULES]"
    static let legacyAdvancedMemoryInstructions = "advanced_memory(action,nodes,edges)"

    static let learningRulesMarker = "[LEARNED RULES]"

    /// Built-in capabilities and directives shown in Space → Skills. Their
    /// instruction text is the same text compiled into the model prompt, so an
    /// edit here changes what the assistant is taught on its next turn.
    static let exposedSkills: [CustomSkill] = [
        CustomSkill(id: dynamicInsightsID, name: "Dynamic Insights", summary: "Toolbox capability for displaying calculated insights and alerts.", instructions: "dynamic_insights(title,description,fields:[{id,label,type:\"insight\",placeholder}]); use only to present useful calculated results or alerts as a native insight block"),
        CustomSkill(id: internetSearchID, name: "Internet Search", summary: "Source-first web retrieval for substantive answers, with current multi-source evidence and citations. Edit this to customize how the AI uses search.", instructions: "internet_use(query) or internet_use(queries: [\"query 1\", \"query 2\"]); before calling it, interpret the user's request and formulate laser-focused, concise search queries containing exact keywords, entities, or product names (e.g. 'cashews walnuts nutrition facts per 100g USDA' rather than conversational sentences like 'im gonna have 30g cashews... give me macros'). For multi-entity or comparative questions, supply multiple queries in `queries` or emit sequential internet_use calls. After retrieval, perform all unit conversions and calculations internally. Emit a clean, definitive, verified answer without exposing private reasoning, scratchpad notes, rough drafts, or self-correction monologues. Ensure summary totals match itemized values with exact arithmetic."),
        CustomSkill(id: advancedMemoryID, name: "Advanced Memory", summary: "Capability for updating the persistent user/entity knowledge graph.", instructions: "advanced_memory(action,nodes,edges); actions: upsert,delete,clear. Store only user facts, preferences, projects, people, interests, goals, and explicit entity relationships. Never store operational lessons or error-prevention rules here; use learning instead. Every edge must reference supplied or existing node IDs"),
        CustomSkill(id: filesystemID, name: "Terminal & Filesystem", summary: "Toolbox capability for validated terminal commands and local file operations.", instructions: "file_system(action,path,content,command,files); exact actions: execute_command (runs zsh terminal commands directly on macOS), list, read_file, create_file, create_files, create_folder; use create_files for up to 12 related project files; Home: {{HOME}}; Downloads: {{HOME}}/Downloads; Documents: {{HOME}}/Documents; Desktop: {{HOME}}/Desktop. You have authorized terminal access to execute shell commands when requested. When installing software or tools on macOS, always use Homebrew (e.g. `brew install <package>` or `brew install --cask <app>`). When starting development servers (e.g. `npm run dev`, `vite`, `nuxt`, `next dev`), check the tool output for the localhost URL (e.g. `http://localhost:3000`), report the localhost link to the user, and mark your job complete immediately. Always emit tool JSON objects directly without stopping at descriptive markdown code blocks."),
        CustomSkill(id: toolRouterID, name: "Tool Execution Contract", summary: "Core rules governing how the AI emits, chains, and completes tool calls.", instructions: "Before executing any tool, write a brief, polite 1-sentence intro acknowledging what you will do (e.g. 'I will install Vue CLI for you now using Homebrew.'). Then emit exactly one valid JSON object with a `type` matching a listed tool and only its needed fields. Tool calls are intermediate: inspect the structured result and either emit the single next action explicitly required by the user or a concise final answer. When running dev servers or background processes, report the running localhost URL and finish immediately; do not wait for the server to exit. Stop immediately once the requested result is confirmed; never add unrequested actions or narrate private reasoning. Request input when needed and wait. Never invent tool names, field types, or action names."),
        CustomSkill(id: personaID, name: "Persona & User Style", summary: "Controls adoption of user-requested roles, names, tone, and response style.", instructions: "[PERSONA]\nNaturally adopt user-requested roles, names, and response styles while remaining helpful."),
        CustomSkill(id: learningID, name: "Learning", summary: "Writable reusable prevention rules and topic-organized How-tos learned from difficult completed work.", instructions: "learning(action,learningId,learningKind,learningTopic,content); actions: list,append,update,delete,clear; learningKind: rule or how-to; learningTopic: a specific 2–6 word subject heading such as Xcode Build Recovery. WHEN TO SAVE: use rule after a confirmed error and verified correction; use how-to when a task required multiple failed approaches or a long tool chain before a final method was verified. A hard-won How-to is mandatory after 2 or more failed tool attempts followed by success, or after 6 or more tool steps taking at least 60 seconds. Do not save ordinary first-try work, guesses, raw logs, transient errors, personal facts, or credentials. HOW TO SAVE OR UPDATE: call list first and use learningTopic to find the relevant subheading. If a learning already covers the same task, update it by stable learningId; otherwise append. Use one stable topic across related learnings. A how-to must state when it applies, preconditions, ordered proven steps, verification, and the failed pitfall. Record only the final proven method, without chain-of-thought. Successful writes appear immediately under the topic subheading in Skills → Learning. Never claim it was saved until the tool reports success. Personal facts belong in advanced_memory.\n\n[LEARNED RULES]"),
        CustomSkill(id: reasoningID, name: "Deep Reasoning Behavior", summary: "Instructions used while Deep Reasoning mode is enabled.", instructions: "[DEEP REASONING MODE ACTIVE]\nReason carefully internally. Never expose chain-of-thought, planning traces, scratchpad calculations, rough draft recalculations, or <think> tags; return only concise user-facing progress, tool calls, and the polished final answer with verified consistent arithmetic."),
        CustomSkill(id: directResponseID, name: "Direct Response Behavior", summary: "Instructions used while Deep Reasoning mode is disabled.", instructions: "[REASONING MODE DISABLED]\nDo not generate, expose, or stream chain-of-thought, scratchpads, analysis, rough draft recalculations, or <think> blocks. Perform all calculations and unit conversions internally, and respond directly with only the clean, final, verified answer."),
        CustomSkill(id: crossCheckID, name: "Fact Cross-Check", summary: "Instructions used when fact cross-check mode is enabled.", instructions: "[MANDATORY FACT CROSS-CHECK VERIFICATION ACTIVE]\nCross-check factual claims that need current verification with internet_use before the final answer. Prefer primary sources and never claim a source was checked when it was not."),
        CustomSkill(id: mandatorySearchID, name: "Mandatory Internet Search", summary: "Instructions used when mandatory search mode is enabled.", instructions: "[MANDATORY INTERNET SEARCH ACTIVE]\nExecute an internet_use query for every user prompt before answering."),
        CustomSkill(id: performanceID, name: "Performance Mode", summary: "Instructions used when AI Performance mode is selected.", instructions: "[SYSTEM OPTIMIZATION: PERFORMANCE MODE ACTIVE]\nMaximize execution speed and minimize token usage. Provide direct, precise answers without filler while fully completing the request."),
        CustomSkill(id: balancedID, name: "Balanced Mode", summary: "Instructions used when Balanced performance mode is selected.", instructions: "[SYSTEM OPTIMIZATION: BALANCED MODE ACTIVE]\nMaintain accuracy and useful depth while keeping responses direct and token-efficient. Avoid repetitive padding.")
    ]

    // These generic starter workflows duplicated the assistant's normal
    // behavior and unnecessarily inflated both the Skills UI and model prompt.
    // Keep their stable IDs only so existing persisted copies are removed.
    static let retiredStarterSkillIDs: Set<UUID> = Set((1...8).compactMap { index in
        UUID(uuidString: String(format: "A100%04d-0000-4000-8000-%012d", index, index))
    })
    static let retiredSkillIDs: Set<UUID> = Set([dynamicInputID, tesaractID, tasksID, retiredCapabilityID])
        .union(retiredStarterSkillIDs)
    static let toolSkillIDs: Set<UUID> = [dynamicInsightsID, internetSearchID, advancedMemoryID, filesystemID, learningID]
    static let infrastructureIDs: Set<UUID> = Set(exposedSkills.map(\.id))
    // These are internal app directives/settings, not user-facing skills.
    static let skillsSpaceHiddenIDs: Set<UUID> = [
        toolRouterID, personaID, reasoningID, directResponseID,
        crossCheckID, mandatorySearchID, performanceID, balancedID
    ]

    static let skills: [CustomSkill] = [
        CustomSkill(
            id: UUID(uuidString: "A1000001-0000-4000-8000-000000000001")!,
            name: "Deep Research",
            summary: "Use for research questions that need current sources, comparison, and a clear evidence-based conclusion.",
            instructions: """
            1. Restate the research question and identify the claims that require evidence.
            2. Search broadly, then prefer primary and recent sources.
            3. Cross-check important claims across independent sources.
            4. Separate verified facts, reasonable inferences, and uncertainty.
            5. Deliver a concise synthesis with links beside the claims they support.
            Never invent citations or imply a source was checked when it was not.
            """
        ),
        CustomSkill(
            id: UUID(uuidString: "A1000002-0000-4000-8000-000000000002")!,
            name: "Code Review",
            summary: "Use when reviewing code, pull-request changes, architecture, performance, reliability, or maintainability.",
            instructions: """
            Review behavior before style. Inspect surrounding code and call sites when available.
            Prioritize findings by severity: correctness, security, data loss, concurrency, performance, then maintainability.
            For every finding, explain the concrete failure mode and point to the relevant code. Suggest the smallest safe fix.
            Do not report speculative issues as facts. Mention missing tests for risky paths and end with a short overall assessment.
            """
        ),
        CustomSkill(
            id: UUID(uuidString: "A1000003-0000-4000-8000-000000000003")!,
            name: "Debugging Partner",
            summary: "Use when diagnosing crashes, incorrect behavior, failed builds, logs, or hard-to-reproduce software bugs.",
            instructions: """
            1. Capture the expected behavior, actual behavior, and reliable reproduction steps.
            2. Inspect errors, logs, recent changes, and the narrowest relevant code path.
            3. Form a small number of testable hypotheses and check the highest-signal one first.
            4. Identify the root cause before proposing a fix.
            5. After fixing, run the closest relevant verification and check for regressions.
            Clearly distinguish diagnosis, implemented change, and remaining uncertainty.
            """
        ),
        CustomSkill(
            id: UUID(uuidString: "A1000004-0000-4000-8000-000000000004")!,
            name: "Writing Editor",
            summary: "Use to rewrite, polish, shorten, or improve emails, documents, posts, and other prose while preserving intent.",
            instructions: """
            Preserve the author's meaning, facts, and natural voice. Improve clarity, structure, rhythm, and concision.
            Match the requested audience and tone; if none is given, use warm professional language.
            Remove repetition, filler, and vague phrasing without making the writing sound generic.
            Return the revised text first. Add brief editorial notes only when a meaningful choice or ambiguity needs attention.
            """
        ),
        CustomSkill(
            id: UUID(uuidString: "A1000005-0000-4000-8000-000000000005")!,
            name: "Meeting Notes to Actions",
            summary: "Use to turn meeting transcripts, rough notes, or discussions into decisions, owners, and next steps.",
            instructions: """
            Extract: summary, decisions, action items, open questions, and risks.
            Write every action item as a concrete verb-led task. Include owner and due date only when stated; otherwise mark them Unassigned or Not set.
            Do not convert suggestions into decisions or invent commitments.
            Keep background discussion brief and make unresolved disagreements visible.
            """
        ),
        CustomSkill(
            id: UUID(uuidString: "A1000006-0000-4000-8000-000000000006")!,
            name: "Project Planner",
            summary: "Use to turn a goal or feature idea into a practical execution plan with milestones, dependencies, and risks.",
            instructions: """
            Define the outcome and success criteria first. State important assumptions.
            Break work into ordered milestones with concrete deliverables, dependencies, and verification steps.
            Surface the critical path, likely risks, and decisions that block progress.
            Keep the plan proportional to the project; avoid ceremonial tasks that do not reduce risk or produce an outcome.
            End with the next three actions that can begin immediately.
            """
        ),
        CustomSkill(
            id: UUID(uuidString: "A1000007-0000-4000-8000-000000000007")!,
            name: "Data Analyst",
            summary: "Use for datasets, metrics, tables, CSV files, trends, comparisons, and evidence-based business analysis.",
            instructions: """
            Confirm what each field and metric represents before calculating. Check missing values, duplicates, units, date ranges, and suspicious outliers.
            Use the simplest analysis that answers the question. Show important assumptions and enough calculation detail to reproduce the result.
            Distinguish correlation from causation. Lead with the decision-relevant insight, then supporting numbers, limitations, and recommended next checks.
            """
        ),
        CustomSkill(
            id: UUID(uuidString: "A1000008-0000-4000-8000-000000000008")!,
            name: "Decision Brief",
            summary: "Use when comparing options, products, approaches, or tradeoffs and recommending a defensible choice.",
            instructions: """
            Identify the decision, constraints, and evaluation criteria. Ask one focused question only if a missing constraint could reverse the recommendation.
            Compare viable options consistently across the same criteria. Include cost, risk, reversibility, and opportunity cost when relevant.
            Recommend one option, explain why it wins for this situation, and name the condition that would change the recommendation.
            """
        )
    ]

    static func isStarter(_ id: UUID) -> Bool {
        skills.contains { $0.id == id }
    }

    static func isInfrastructure(_ id: UUID) -> Bool {
        infrastructureIDs.contains(id) || id.uuidString.hasPrefix("A400")
    }
    static func isCatalogSkill(_ id: UUID) -> Bool { isStarter(id) || isInfrastructure(id) }
    static func isVisibleInSkillsSpace(_ id: UUID) -> Bool {
        !skillsSpaceHiddenIDs.contains(id) && !retiredSkillIDs.contains(id)
    }
    static func defaultInstructions(for id: UUID) -> String? {
        guard let instructions = (exposedSkills + skills).first(where: { $0.id == id })?.instructions else {
            return nil
        }
        if id == internetSearchID, !instructions.contains("EVIDENCE-FIRST PRIORITY:") {
            return instructions.replacingOccurrences(
                of: "internet_use(query);",
                with: "internet_use(query);\(evidenceFirstSearchRule)"
            )
        }
        return instructions
    }

    static func librarySkillID(for apiID: String) -> UUID? {
        let ids: [String: String] = [
            "weather_api": "A4000001-0000-4000-8000-000000000001",
            "wiki_api": "A4000002-0000-4000-8000-000000000002",
            "github_api": "A4000003-0000-4000-8000-000000000003",
            "coingecko_api": "A4000004-0000-4000-8000-000000000004",
            "hackernews_api": "A4000005-0000-4000-8000-000000000005",
            "nasa_api": "A4000006-0000-4000-8000-000000000006",
            "openlibrary_api": "A4000007-0000-4000-8000-000000000007",
            "geoip_api": "A4000008-0000-4000-8000-000000000008",
            "forex_api": "A4000009-0000-4000-8000-000000000009",
            "arxiv_api": "A4000010-0000-4000-8000-000000000010",
            "restcountries_api": "A4000011-0000-4000-8000-000000000011",
            "spotify_api": "A4000012-0000-4000-8000-000000000012",
            "jsonplaceholder_api": "A4000013-0000-4000-8000-000000000013",
            "pubmed_api": "A4000014-0000-4000-8000-000000000014",
            "market_api": "A4000015-0000-4000-8000-000000000015",
            "apple_notes_api": "A4000016-0000-4000-8000-000000000016"
        ]
        return ids[apiID].flatMap(UUID.init(uuidString:))
    }

    /// Curated intent routing keeps full starter instructions out of unrelated
    /// prompts while avoiding fuzzy keyword matches such as treating any
    /// coding request as a code-review request.
    static func matches(_ skill: CustomSkill, request: String) -> Bool {
        let query = request.lowercased()
        let phrases: [String]
        switch skill.name {
        case "Deep Research":
            phrases = ["deep research", "research this", "investigate", "find sources", "cite sources", "latest information", "verify these claims"]
        case "Code Review":
            phrases = ["code review", "review this code", "review my code", "audit this code", "pull request", "review this pr"]
        case "Debugging Partner":
            phrases = ["debug", "bug", "crash", "build failed", "failing test", "doesn't work", "not working", "error message"]
        case "Writing Editor":
            phrases = ["rewrite", "proofread", "polish this", "edit this", "improve this writing", "shorten this", "draft an email"]
        case "Meeting Notes to Actions":
            phrases = ["meeting notes", "meeting transcript", "meeting minutes", "action items", "turn these notes"]
        case "Project Planner":
            phrases = ["project plan", "implementation plan", "create a roadmap", "make a roadmap", "plan this project", "milestones and dependencies"]
        case "Data Analyst":
            phrases = ["analyze this data", "analyse this data", "dataset", "csv", "spreadsheet", "analyze metrics", "analyse metrics", "find trends"]
        case "Decision Brief":
            phrases = ["decision brief", "decide between", "compare options", "pros and cons", "which should i choose", "tradeoffs", "recommend an option"]
        default:
            return true
        }
        return phrases.contains { query.contains($0) }
    }
}
