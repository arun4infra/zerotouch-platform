# Platform APIs Reorganization

## Summary

Reorganized the 04-apis directory to group all EventDrivenService-related files together, making it easier to maintain and add new service types in the future.

## Changes Made

### Before (Flat Structure)
```
04-apis/
├── compositions/
│   └── event-driven-service-composition.yaml
├── definitions/
│   └── xeventdrivenservices.yaml
├── schemas/
│   └── eventdrivenservice.schema.json
├── examples/
│   ├── agent-executor-claim.yaml
│   ├── full-claim.yaml
│   └── minimal-claim.yaml
├── tests/
│   ├── test-autoscaling.sh
│   ├── test-full-deployment.sh
│   ├── test-minimal-deployment.sh
│   ├── verify-composition.sh
│   ├── verify-keda-config.sh
│   ├── schema-validation.test.sh
│   └── fixtures/
└── docs/
    └── RCA-AUTOSCALING-FIX.md
```

### After (Organized by Service)
```
04-apis/
├── event-driven-service/
│   ├── compositions/
│   │   └── event-driven-service-composition.yaml
│   ├── definitions/
│   │   └── xeventdrivenservices.yaml
│   ├── schemas/
│   │   └── eventdrivenservice.schema.json
│   ├── examples/
│   │   ├── agent-executor-claim.yaml
│   │   ├── full-claim.yaml
│   │   └── minimal-claim.yaml
│   ├── tests/
│   │   ├── test-autoscaling.sh
│   │   ├── test-full-deployment.sh
│   │   ├── test-minimal-deployment.sh
│   │   ├── verify-composition.sh
│   │   ├── verify-keda-config.sh
│   │   ├── schema-validation.test.sh
│   │   └── fixtures/
│   ├── docs/
│   │   └── RCA-AUTOSCALING-FIX.md
│   └── README.md
└── README.md
```

## Benefits

1. **Better Organization** - All EventDrivenService files are in one place
2. **Easier Maintenance** - Clear separation of concerns
3. **Scalable Structure** - Easy to add new service types (e.g., `webservice/`, `cronjob/`)
4. **Self-Documenting** - Each service has its own README
5. **Isolated Testing** - Tests are specific to each service

## Path Updates

Updated the following in test scripts:
- `PROJECT_ROOT` calculation: `../../../..` (4 levels up from `event-driven-service/tests/`)
- `CLAIM_FILE` path: `${PROJECT_ROOT}/platform/04-apis/event-driven-service/examples/minimal-claim.yaml`

## Testing

All tests verified to work with new structure:
```bash
./platform/04-apis/event-driven-service/tests/test-autoscaling.sh
./platform/04-apis/event-driven-service/tests/test-full-deployment.sh
./platform/04-apis/event-driven-service/tests/test-minimal-deployment.sh
```

## Future Service Types

When adding new services, follow this pattern:
```
04-apis/
├── <service-name>/
│   ├── compositions/
│   ├── definitions/
│   ├── schemas/
│   ├── examples/
│   ├── tests/
│   ├── docs/
│   └── README.md
```

Examples:
- `webservice/` - HTTP-based web services
- `cronjob/` - Scheduled batch jobs
- `stateful-service/` - Services with persistent storage
