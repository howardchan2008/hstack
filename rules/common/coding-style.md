# Coding Style

- **Immutability (critical).** Return new objects, never mutate in place.
- **Many small files.** High cohesion, low coupling. 200-400 lines typical, 800 max. Organise by feature, not by type.
- **Errors handled explicitly at every level.** User-friendly messages in UI code, detailed context in server logs, never a silently swallowed error.
- **Validate at system boundaries.** Schema-based where available, fail fast, never trust external data.
- Before marking work complete: the above, plus functions under 50 lines, nesting under 4, no hardcoded values.
