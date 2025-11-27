---
schema_version: "1.0"
category: runbook
resource: COMPONENT_NAME              # e.g., postgres, cilium, argocd (kebab-case)
issue_type: operational               # operational | performance | security
severity: high                        # critical | high | medium | low
created_at: YYYY-MM-DDTHH:MM:SSZ
last_updated: YYYY-MM-DDTHH:MM:SSZ
related_compositions:                 # Optional: Links to platform resources
  - platform/path/to/composition.yaml
tags:
  - tag1
  - tag2
---

# {Resource Name}: {Issue Title}

## Symptoms

| Indicator | Threshold | Detection Method |
|:----------|:----------|:-----------------|
| Metric/Alert name | Value that triggers issue | Prometheus alert name or monitoring tool |
| Example: Disk usage | >90% | `PostgresDiskUsage` alert |

## Diagnosis

| Step | Command | Expected Output |
|:-----|:--------|:----------------|
| 1. Check resource | `kubectl get/describe command` | What to look for |
| 2. Verify status | `kubectl exec command` | Expected vs. actual state |

## Solution

### Automated Fix (Kagent-Executable)

| Action | YAML Change | ArgoCD Sync |
|:-------|:-----------|:------------|
| What to change | Specific field and value update in which file | Auto or Manual |

### Manual Steps (If Automation Fails)

| Step | Command | Risk Level |
|:-----|:--------|:-----------|
| 1. Action description | `kubectl command` | High/Medium/Low (with reason) |

## Prevention

| Preventive Measure | Implementation | Owner |
|:-------------------|:---------------|:------|
| How to prevent recurrence | Code/config change needed | Team responsible |

## Related Incidents

| Date | PR | Outcome |
|:-----|:---|:--------|
| YYYY-MM-DD | #123 | Brief description of resolution |

## References

- [External documentation links]
- [Related ADRs or specs]
