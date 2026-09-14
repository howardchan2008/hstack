# Coding Style

- **Immutability (critical).** Return new objects; never mutate.
- **Small files.** 200-400 lines typical; 800 max. High cohesion, low coupling. By feature, not type.
- **Errors handled explicitly at every level.** User-friendly UI messages, detailed logs. Never silent.
- **Validate at system boundaries.** Schema-based where available. Fail fast. Never trust external data.
- Complete: above + functions <50 lines, nesting <4, no hardcoded values.