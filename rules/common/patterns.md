# Common Patterns

## Skeleton Projects

When implementing new functionality:
1. Search for battle-tested skeletons (`gh search repos`, `gh search code`, the package
   registries). Full research ladder: `development-workflow.md` step 0.
2. Read the top two or three yourself. Four agents scoring one repo on four axes was the
   old text here, and it spends half the daily agent budget re-deriving what a README and
   a dependency file answer directly.
3. Clone the best match as the foundation.
4. Iterate within the proven structure.

## Design Patterns

### Repository Pattern

Encapsulate data access behind a consistent interface:
- Define standard operations: findAll, findById, create, update, delete
- Concrete implementations handle storage details (database, API, file, etc.)
- Business logic depends on the abstract interface, not the storage mechanism
- Enables easy swapping of data sources and simplifies testing with mocks

### API Response Format

Use a consistent envelope for all API responses:
- Include a success/status indicator
- Include the data payload (nullable on error)
- Include an error message field (nullable on success)
- Include metadata for paginated responses (total, page, limit)
