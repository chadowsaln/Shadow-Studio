# Body-Side Architecture Boundaries Rule

1. **Role Scope**:
   - The body side of Shadow Studio owns: Timeline, Media Management, Import/Export, Preview, Project Persistence, Native Media Engine Worker, UI-to-Agent binding, and UI/Media tests.
   - The AI agent side owns: `agent_runtime`, `provider_gateway`, `tool_system`, `permissions`.
   - Never modify or couple directly with the AI agent side internals; expose clean Dart interfaces (e.g. `EditingService`, `EditorController`, `EditOutcome`).

2. **Transaction Integrity**:
   - Every mutation is an atomic `EditTransaction` with strict `expectedRevision` verification.
   - All time values are integer microseconds (`1 tick = 1/1,000,000 s`). Never use `double` for time.
   - Edits are non-destructive; original media files are never altered.
