# Open Questions and Proposed Defaults

Where the architecture specifications are silent, ambiguous, or allow multiple interpretations, questions and safe defaults are recorded here. Approved architecture documents are never directly edited.

---

## OQ-001: Structure and Error Representation in `EditOutcome`

- **Context**: Spec §9.3 defines the signature `Future<EditOutcome> apply(EditTransaction transaction, {required int expectedRevision});` without defining the inner structure of `EditOutcome`.
- **Question**: Should `EditOutcome` be an exception-throwing contract or a functional result object?
- **Decision / Proposed Default**: Implemented as a sealed class hierarchy (`EditSuccess` and `EditFailure`).
  - `EditSuccess` provides `document` and the incremented `revision`.
  - `EditFailure` wraps `ShadowError` with code (`EDIT_REVISION_MISMATCH`, `EDIT_INVALID_OPERATION`), category (`edit`), `retryable` flag, and diagnostic `details`.
  - Also exposes convenience getters (`isSuccess`, `isFailure`, `document`, `revision`, `error`) for ergonomic calling from UI or agent tools without requiring unhandled exception crashes.

---

## OQ-002: Revision Counter Behavior Across Undo and Redo

- **Context**: Spec §0 defines Revision as "عدّاد أحادي التزايد يزداد مع كل EditTransaction مُثبَّتة" (a monotonic increasing counter). In Spec §14.1, frame cache keys depend on `revision` or `graph_hash`.
- **Question**: When an undo or redo occurs, should `revision` increment (monotonically) or decrement / step backward to the previous revision number?
- **Decision / Proposed Default**: Increment `revision` monotonically on every state transition (`apply`, `undo`, `redo`).
  - If `revision` were decremented on undo, a subsequent edit would re-issue a previously seen revision number, creating cache collisions in scrub frame caches and breaking optimistic concurrency locks (`expectedRevision`).
  - Monotonic increments guarantee that every distinct document state has a globally unique, strictly ascending revision identifier.

---

## OQ-003: Scope of Transitions in Phase 1

- **Context**: The Phase 1 brief notes: "transitions only on the boundary of two adjacent clips (if you implement transitions now; otherwise list as deferred)."
- **Question**: How much transition functionality belongs in Phase 1 (`editing_core`) versus Phase 3 (`RenderGraph` derivation)?
- **Decision / Proposed Default**: 
  - Included `Transition` in the track model with strict invariant validation: `transition.at_ticks` must exactly equal the cut boundary (`fromClip.timelineEndTicks == toClip.timelineStartTicks`), both clips must exist on the track, and `duration_ticks <= min(fromClip.durationTicks, toClip.durationTicks) ~/ 2`.
  - Specific transition editing commands (e.g. `AddTransitionCommand`) and transition rendering compilation are deferred to Phase 3.

---

## OQ-004: Asset Kind Matching on Track Kinds

- **Context**: Spec §domain/invariants.py and Phase 1 state "asset kind matches track kind".
- **Question**: What exact combinations of `AssetKind` and `TrackKind` are permitted?
- **Decision / Proposed Default**:
  - `TrackKind.video`: accepts `AssetKind.video` and `AssetKind.image` (and synthetic clips without assets like solid color or adjustment).
  - `TrackKind.audio`: strictly requires `AssetKind.audio`.
  - `TrackKind.overlay`: accepts `AssetKind.image` and `AssetKind.video`.
  - Any mismatch (e.g. audio asset on video track or video asset on audio track) is rejected with `EDIT_INVALID_OPERATION`.

---

## OQ-005: Deferred Methods on `EditingService` in Phase 1

- **Context**: Spec §9.3 includes `openProject`, `save`, and `resolveGraph` on `EditingService`. Phase 1 instructions state: "Leave openProject/save/resolveGraph for later phases but keep the interface compatible."
- **Question**: How should `EditingService` handle calls to these methods during Phase 1?
- **Decision / Proposed Default**: These methods are declared on the interface matching Spec §9.3 signatures. In `DefaultEditingService`, they throw `UnimplementedError` citing the phase where they will be implemented (Phase 2 for `openProject` and `save` via `local_storage`, Phase 3 for `resolveGraph` via RenderGraph resolver).
