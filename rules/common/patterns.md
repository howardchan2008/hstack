# Common Patterns

## Skeleton projects
Search battle-tested skeletons (`gh search repos`, `gh search code`, package registries). Read top 2-3. Clone best, iterate in proven structure.

## Repository pattern
Interface: findAll, findById, create, update, delete. Implementations hold storage. Business logic depends on interface.

## API response envelope
- Status indicator
- Data payload (nullable)
- Error message (nullable)
- Pagination metadata where relevant