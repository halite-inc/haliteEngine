# AppleInt Architecture

AppleInt is a local-first SwiftUI agent application. Its architecture favors explicit ownership, thread-scoped agent runs, replaceable infrastructure, and durable user data without coupling views to transport or storage details.

## System shape

```text
SwiftUI views
    │ user intents / observed state
    ▼
ChatManager (application facade, @MainActor)
    ├── AgentController per thread (run state machine and limits)
    ├── ToolRegistry → validated tool executors
    ├── model transports → Gemini / OpenRouter / OpenAI / LM Studio
    └── injected capabilities
          ├── ThreadPersisting
          ├── AttachmentStoring
          ├── URLSession
          ├── DiagnosticsStore
          ├── AgentLearningStore
          ├── ModelDiscoveryService
          └── ProviderHealthService
```

`AppBootstrapper` is the only production composition root. It runs migrations before stateful features are created, prepares application storage, creates long-lived services once, and injects them into `ChatManager` through `AppDependencies`.

## Dependency rule

Dependencies point inward:

| Layer | Owns | May depend on |
|---|---|---|
| Presentation | SwiftUI rendering and user interaction | Application facade and domain values |
| Application | Use-case orchestration, thread lifecycle, cancellation | Domain contracts and injected capabilities |
| Domain | Agent state, tool calls, limits, messages | Foundation value types only |
| Infrastructure | HTTP, files, and preferences | Domain contracts; never SwiftUI views |

Views must not create repositories, sessions, or provider clients. Infrastructure must not mutate view state. `ChatManager` is main-actor isolated and is the serialization boundary for observable application state. Actors own independently concurrent caches, diagnostics, learning history, and provider health checks.

## Runtime invariants

- Each conversation has its own generation task, generation identity, search history, and `AgentController`.
- A stale stream cannot clean up or overwrite a newer generation for the same thread.
- Tool calls are normalized and validated through `ToolRegistry` before execution.
- Runs have explicit step, duplicate-call, continuation, and consecutive-failure limits.
- Streaming preferences are snapshotted at the run boundary so a request cannot change semantics midway through generation.
- Thread writes are serialized, debounced, atomic, and synchronously flushed when the scene leaves the active state.
- Attachments live outside conversation JSON and use owner-only directories/files.
- Operational diagnostics are bounded and never record prompts, credentials, tool payloads, or file contents.

## Storage ownership

`AppPaths` defines the single Application Support root and all durable child locations. Production uses `~/Library/Application Support/AppleIntChat`; tests and previews can inject a temporary root.

| Data | Storage | Owner |
|---|---|---|
| Threads | `threads.json` | `ThreadPersisting` |
| Image attachments | `attachments/` | `AttachmentStoring` |
| Knowledge graph | `global_memory_graph.json` | Memory application service |
| Credentials | owner-readable `credentials.json` | `CredentialStore` |
| Terminal audit | `terminal-audit.jsonl` | Terminal application service |
| Lightweight settings | `UserDefaults` | Injected preferences capability |

Large values do not belong in `UserDefaults`. Credentials must never enter prompts, diagnostics, or ordinary conversation persistence.

## Evolution path

The application facade remains intentionally compatible with the current UI while modularization continues. New work should follow these seams:

1. Put each provider behind `ModelProvider`; keep wire DTOs private to its adapter.
2. Move task, memory, search, terminal, and generation orchestration into focused application services.
3. Split feature views by screen after their state is owned by the corresponding service or feature model.
4. Add contract tests against `ThreadPersisting`, `AttachmentStoring`, and provider adapters using temporary paths and injected URL sessions.

Avoid adding new provider switches, direct `URLSession.shared` calls, or storage paths to `ChatManager` or a SwiftUI view. Extend the relevant protocol and register its production implementation in `AppDependencies.live()`.

## Architectural definition of done

A feature is complete when its dependencies are injected, cancellation is defined, failures are surfaced as typed errors, durable writes are atomic, sensitive data is excluded from logs, and its core behavior can run with test doubles without launching SwiftUI or making a real network request.
