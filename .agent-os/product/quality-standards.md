# Project Quality Standards

## Automated Enforcement
All code changes must pass:
1. Unit test coverage: minimum 80%
2. Integration test coverage: minimum 70%
3. Security scan: zero critical vulnerabilities
4. Code complexity: maximum cyclomatic complexity of 10
5. Performance: response time < 200ms for API calls

## Sub-agent Validation
Required approvals before merge:
- code-reviewer: PASS (no critical issues)
- test-automator: PASS (comprehensive coverage)
- qa-expert: PASS (strategy validated)

## Exemption Process
Exemptions require:
- Technical justification in decisions.md
- Alternative mitigation strategies
- Time-bound remediation plan