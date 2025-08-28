# Project Quality Standards

## Pre-Push Hook Enforcement (MANDATORY)
All code changes must pass the pre-push hook (`.git/hooks/pre-push`):
1. **Compilation**: Zero warnings or errors
2. **Code Formatting**: All code properly formatted via `mix format`
3. **Test Suite**: 100% test pass rate (minimum 80% coverage)
4. **Code Quality**: Critical Credo violations resolved
5. **Type Safety**: Zero Dialyzer warnings
6. **Dependencies**: All dependencies correctly installed

## Additional Quality Requirements
All code changes must also meet:
1. Integration test coverage: minimum 70%
2. Security scan: zero critical vulnerabilities  
3. Code complexity: maximum cyclomatic complexity of 10
4. Performance: response time < 200ms for API calls

## QA Validation Requirements
Required validations before story approval:
- **Pre-Push Hook**: PASS (all 6 quality checks must pass)
- **Code Review**: PASS (no critical issues found)
- **Test Coverage**: PASS (comprehensive coverage validated)
- **Functional Testing**: PASS (acceptance criteria verified)
- **Dialyzer Validation**: PASS (zero type warnings)

## Sub-agent Validation
Required approvals before merge:
- code-reviewer: PASS (no critical issues)
- test-automator: PASS (comprehensive coverage)
- qa-expert: PASS (strategy validated + pre-push hook executed)

## Exemption Process
Exemptions require:
- Technical justification in decisions.md
- Alternative mitigation strategies
- Time-bound remediation plan