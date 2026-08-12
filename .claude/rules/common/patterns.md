# Common Patterns

## Skeleton Projects

When implementing new functionality:

1. Search for battle-tested skeleton projects
2. Use parallel agents to evaluate options:
   - Security assessment
   - Extensibility analysis
   - Relevance scoring
   - Implementation planning
3. Clone best match as foundation
4. Iterate within proven structure

## Design Patterns

> Repository Pattern is not applicable — this repo owns no data store. All data arrives through
> BE LMS via the Orval-generated client, consumed only through service hooks in
> `src/hooks/api/`. See SSOT.md §1.2 and §5.
