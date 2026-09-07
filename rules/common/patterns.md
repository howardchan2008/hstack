# Common Patterns

## Skeleton projects
Search for battle-tested skeletons (`gh search repos`, `gh search code`, package registries), read the top two or three yourself (a README and a dependency file answer most of it), clone the best match, iterate inside the proven structure.

## Repository pattern
Standard operations behind an interface (findAll, findById, create, update, delete). Concrete implementations hold storage details; business logic depends on the interface.

## API response envelope
Consistent shape: status indicator, nullable data payload, nullable error message, pagination metadata where relevant.
