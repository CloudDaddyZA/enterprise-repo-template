# ADR-001: Use Architecture Decision Records

## Status

Accepted

## Date

2024-01-01

## Context

We need a lightweight way to document important architectural decisions so that:
- New team members understand why decisions were made
- We avoid revisiting the same discussions repeatedly
- We have a record of trade-offs considered

## Decision

We will use Architecture Decision Records (ADRs) as described by Michael Nygard. Each ADR will:
- Be stored in `docs/adr/` as a Markdown file
- Follow the naming convention `NNN-short-title.md`
- Use the template in `docs/adr/template.md`
- Be reviewed via pull request

## Consequences

### Positive

- Clear documentation of architectural decisions
- Easy onboarding for new team members
- Prevents repeated discussions about past decisions
- Lightweight process (just a Markdown file)

### Negative

- Requires discipline to create ADRs for significant decisions
- May become stale if not maintained

### Neutral

- ADRs are immutable once accepted; new decisions supersede old ones

## References

- [Documenting Architecture Decisions - Michael Nygard](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions)
