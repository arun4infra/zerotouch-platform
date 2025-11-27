---
schema_version: "1.0"
category: adr
number: XXX                          # Auto-incremented by agent (3 digits)
status: proposed                     # proposed | accepted | deprecated | superseded
created_at: YYYY-MM-DDTHH:MM:SSZ
last_updated: YYYY-MM-DDTHH:MM:SSZ
supersedes: []                       # Optional: List of ADR numbers this replaces
superseded_by: null                  # Optional: ADR number that replaces this
tags:
  - architecture
  - decision
---

# ADR {number}: {Decision Title}

## Status
**{Status}** - {Date}

{If superseded, add: Superseded by [ADR XXX](./XXX-title.md)}

## Context

Describe the problem or situation requiring a decision. Use tables or bullet points:

| Factor | Current State | Problem |
|:-------|:--------------|:--------|
| ... | ... | ... |

## Decision

{State the decision in one clear sentence.}

## Rationale

Explain why this decision was made. Use comparison tables:

| Factor | Option A | Option B | Option C | Winner |
|:-------|:---------|:---------|:---------|:-------|
| ... | ... | ... | ... | **X** |

OR use weighted scoring:

| Criterion | Weight | Option A Score | Option B Score |
|:----------|:-------|:---------------|:---------------|
| ... | ... | ... | ... |

## Implementation

Provide concrete implementation details:

### Configuration Changes
```yaml
# Example YAML or code
```

### Steps
| Step | Action | Owner |
|:-----|:-------|:------|
| 1. | First step | Team/Person |

## Consequences

### Positive
- ✅ Benefit 1
- ✅ Benefit 2

### Negative
- ⚠️ Drawback 1 (with mitigation plan if applicable)
- ⚠️ Drawback 2

## Related Decisions

- ADR XXX: Related decision title
- [Spec: Related resource](../specs/xxx.md)

## References

- [External documentation](https://example.com)
- [Best practices guide](https://example.com)
