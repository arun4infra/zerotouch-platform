# Script Writing Patterns

## Core Architecture Patterns

### 1. Subdirectory Organization Pattern

**Pattern:**
```bash
helpers/
├── script-name/           # One subdirectory per main script
│   ├── validator.sh       # Single-purpose helpers
│   ├── processor.sh
│   └── recorder.sh
```

**Why:** Prevents helper namespace collisions, enables clear ownership, simplifies maintenance when multiple scripts share similar helper names.

### 2. Orchestrator Simplification Pattern

**Pattern:**
```bash
main() {
    # Step 1: Validate inputs
    if ! validate_request; then exit 1; fi
    
    # Step 2: Execute core logic  
    if ! process_request; then exit 1; fi
    
    # Step 3: Record results
    if ! record_results; then exit 1; fi
}
```

**Why:** Main scripts become readable workflows, business logic stays in testable helpers, debugging focuses on specific steps, changes isolated to individual helpers.

### 3. Helper Module Sourcing Pattern

**Pattern:**
```bash
# Source helpers from organized subdirectories
source "${SCRIPT_DIR}/helpers/script-name/validator.sh"
source "${SCRIPT_DIR}/helpers/script-name/processor.sh"
source "${SCRIPT_DIR}/helpers/script-name/recorder.sh"
```

**Why:** Explicit dependencies, clear helper ownership, prevents accidental cross-script helper usage, enables independent helper testing.

### 4. Helper Communication Pattern

**Pattern:**
```bash
# Helpers export results for other helpers/main script
export OPERATION_STATUS="SUCCESS"
export OPERATION_RESULT_ID="abc123"
export OPERATION_METADATA_FILE="/path/to/metadata.json"
```

**Why:** Enables helper composition, provides audit trails, allows conditional logic based on previous helper results, supports debugging with intermediate state.

### 5. Multi-Tool Fallback Pattern

**Pattern:**
```bash
# Try preferred tool, fallback to alternatives
if command -v preferred_tool &> /dev/null; then
    preferred_tool_operation
elif command -v fallback_tool &> /dev/null; then
    fallback_tool_operation
else
    manual_operation
fi
```

**Why:** Handles different environment capabilities, ensures scripts work across systems, provides graceful degradation, reduces external dependencies.

### 6. Separate Testing Helpers Pattern

**Pattern:**
```bash
helpers/
├── script-name/
│   ├── core-logic.sh      # Business logic helpers
│   └── testing/           # Testing-specific helpers
│       ├── mock-setup.sh
│       └── test-runner.sh
```

**Why:** Separates production logic from test infrastructure, enables isolated testing of individual helpers, prevents test code from affecting production, supports different testing strategies.

## Implementation Rules

### Helper Script Requirements
- **Single Responsibility:** One helper = one focused task
- **Self-Contained:** Include validation, error handling, logging
- **Standard Interface:** Consistent parameter patterns across all helpers
- **Result Export:** Set environment variables for downstream consumption
- **Exit Codes:** 0=success, 1=failure, 2=config error

### Main Script Requirements  
- **Pure Orchestration:** No business logic, only helper coordination
- **Linear Flow:** Clear step-by-step progression
- **Error Propagation:** Fail fast on any helper failure
- **Logging Integration:** Use platform logging with step tracking
- **Size Limit:** Keep under 200 lines for maintainability

### Directory Structure Requirements
- `helpers/{script-name}/` for each main script's helpers
- `helpers/{script-name}/testing/` for test-specific utilities
- Shared utilities in `lib/` directory
- No helpers in root `helpers/` directory

These patterns ensure scripts are maintainable, testable, and follow consistent architecture across the platform.