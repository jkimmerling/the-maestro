# QA Pre-Push Hook Validation Guide

## Overview

**MANDATORY**: All QA reviews must include execution of the pre-push hook (`.git/hooks/pre-push`) as a core validation step. Any failures must be documented as issues in the QA report.

## Why Pre-Push Hook Validation is Required

The pre-push hook enforces the same quality standards that prevent broken code from reaching the repository. QA teams must verify that:

1. **Code meets production standards** before approval
2. **All automated quality checks pass** consistently
3. **No regressions** are introduced in quality tooling
4. **Developers will not be blocked** when they attempt to push

## QA Validation Process

### 1. **MANDATORY: Execute Pre-Push Hook**

**Command to run:**
```bash
.git/hooks/pre-push
```

**Expected behavior:**
- Hook executes all 6 quality checks
- Either all checks pass OR hook fails with specific error messages
- Complete output must be captured for QA report

### 2. **Document Hook Results**

#### ✅ **If Hook Passes:**
```yaml
pre_push_validation:
  executed: true
  status: PASS
  hook_output: |
    🚀 Running Cleanops pre-push quality checks...
    ✅ Dependencies installed
    ✅ Compilation successful
    ✅ Code formatting is correct  
    ✅ All tests passed
    ✅ Credo analysis passed
    ✅ Dialyzer analysis passed
    ✅ 🎉 All quality checks passed! Push proceeding...
  issues_found: []
  resolution:
    status: resolved
```

#### ❌ **If Hook Fails:**
```yaml
pre_push_validation:
  executed: true
  status: FAIL
  hook_output: |
    # Paste complete hook failure output here
  issues_found:
    - id: "HOOK-001"
      category: "tests"  # or formatting|compilation|credo|dialyzer|dependencies
      finding: "Test suite failed: 2 tests failing in register_test.exs"
      severity: "critical"
      action_required: "Fix failing tests before story approval"
  resolution:
    status: pending
```

### 3. **Analyze Hook Output**

#### **Quality Check Categories:**

| Check | Category | What It Validates | QA Action If Failed |
|-------|----------|------------------|-------------------|
| **Dependencies** | `dependencies` | All deps installed correctly | Block until deps fixed |
| **Compilation** | `compilation` | Code compiles without warnings | Block until warnings resolved |
| **Formatting** | `formatting` | Code follows Elixir standards | Block until `mix format` run |
| **Tests** | `tests` | All tests pass | Block until test failures fixed |
| **Credo** | `credo` | Code quality standards | Block until critical issues fixed |
| **Dialyzer** | `dialyzer` | Type safety validation | Block until type errors resolved |

### 4. **Issue Severity Mapping**

| Hook Failure Type | QA Severity | QA Action |
|------------------|-------------|-----------|
| **Test failures** | `critical` | FAIL gate - Must fix before approval |
| **Compilation errors** | `critical` | FAIL gate - Must fix before approval |
| **Dialyzer errors** | `high` | CONCERNS gate - Should fix before approval |
| **Formatting issues** | `medium` | CONCERNS gate - Easy fix required |
| **Credo critical issues** | `high` | CONCERNS gate - Should fix before approval |
| **Dependency issues** | `critical` | FAIL gate - Must fix before approval |

### 5. **Gate Decision Matrix**

| Hook Status | Other Issues | Gate Decision |
|-------------|-------------|---------------|
| **PASS** | None | **PASS** |
| **PASS** | Minor issues only | **PASS** |  
| **PASS** | Major functional issues | **CONCERNS** |
| **FAIL** | Any check failed | **FAIL** or **CONCERNS** |

## QA Report Integration

### Required QA Report Sections

#### **1. Pre-Push Validation Section (MANDATORY)**
```yaml
pre_push_validation:
  executed: true           # MUST be true
  status: PASS|FAIL        # Based on hook execution
  hook_output: |           # Complete hook output
    [paste full output]
  issues_found: []         # List any hook failures as issues
  resolution:              # Current status
    status: resolved|pending|waived
```

#### **2. Quality Metrics Section**
```yaml
hook_metrics:
  compilation_time: "2.1s"
  test_execution_time: "0.3s"
  test_count: 23
  test_failures: 0
  credo_issues_total: 0
  credo_issues_critical: 0
  dialyzer_warnings: 0
  formatting_issues: 0
```

#### **3. Evidence Section**
```yaml
evidence:
  pre_push_executed: true        # MANDATORY field
  dialyzer_clean: true          # From hook results
  credo_issues: 0               # From hook results
  test_failures: 0              # From hook results
```

## Common Hook Failure Scenarios

### **Test Failures**
```bash
❌ Tests failed
⚠️  Fix failing tests before pushing
```
**QA Action:**
- Review test failures in detail
- Verify tests are correctly written
- Block story until tests pass
- Add issue: `HOOK-001: Test suite failed`

### **Credo Issues**
```bash
❌ Credo found critical issues
⚠️  Fix code quality issues before pushing
```
**QA Action:**
- Review credo output for details
- Assess if issues are critical
- May allow design suggestions (D-level)
- Add issue: `HOOK-002: Code quality violations found`

### **Dialyzer Warnings**
```bash
❌ Dialyzer found type errors
⚠️  Fix type errors before pushing
```
**QA Action:**
- Review type errors carefully
- Verify @spec annotations are correct
- Ensure typespecs match implementation
- Add issue: `HOOK-003: Type safety violations`

### **Formatting Issues**
```bash
❌ Code formatting issues found
⚠️  Run 'mix format' to fix formatting
```
**QA Action:**
- Easy fix - should be resolved immediately
- Block until formatting corrected
- Add issue: `HOOK-004: Code formatting violations`

## QA Workflow Integration

### **Standard QA Process:**
1. **Receive story** for QA review
2. **Set up environment** (git checkout feature branch)
3. **🔧 EXECUTE PRE-PUSH HOOK** (`.git/hooks/pre-push`)
4. **Document results** in QA report
5. **Continue with functional testing**
6. **Make gate decision** (considering hook results)
7. **Create QA report** with hook validation section

### **If Hook Fails:**
1. **Document failure** in QA report immediately
2. **Create issues** for each failure category
3. **Set gate to FAIL or CONCERNS**
4. **Return to developer** with specific fix requirements
5. **Re-run hook** after fixes are implemented
6. **Update QA report** with resolution status

## Troubleshooting

### **Hook Not Found**
```bash
# Verify hook exists and is executable
ls -la .git/hooks/pre-push
# Should show: -rwxr-xr-x (executable)
```

### **Permission Issues**
```bash
# Make hook executable
chmod +x .git/hooks/pre-push
```

### **Environment Issues**
```bash
# Verify you're in project root
ls mix.exs
# Should exist

# Verify Elixir environment
elixir --version
mix --version
```

### **Hook Hangs or Timeout**
```bash
# Run with timeout
timeout 600 .git/hooks/pre-push
# 10-minute timeout for hook execution - realistic time for complex validation
```

## Quality Assurance Standards

### **QA Must Verify:**
- ✅ Pre-push hook executed successfully
- ✅ All hook output captured and documented
- ✅ Any failures properly categorized and reported
- ✅ Resolution status tracked through completion
- ✅ Hook metrics included in quality assessment

### **QA Cannot Approve Stories That:**
- ❌ Have not had pre-push hook executed
- ❌ Have critical hook failures unresolved
- ❌ Show test failures in hook execution
- ❌ Have compilation errors or warnings
- ❌ Have unresolved type safety issues

## Best Practices

### **For QA Teams:**
1. **Run hook early** in QA process to catch issues fast
2. **Capture complete output** - don't truncate failure messages
3. **Categorize issues correctly** - use severity guidelines
4. **Provide actionable feedback** - include specific fix guidance
5. **Re-verify after fixes** - always re-run hook to confirm resolution

### **For QA Reports:**
1. **Always include** pre-push validation section
2. **Use consistent formatting** for hook output
3. **Link hook issues** to specific files and line numbers when possible  
4. **Track resolution status** through completion
5. **Include performance metrics** from hook execution

## Integration with Existing QA Process

This pre-push hook validation **enhances** the existing QA process by:

- **Adding automated verification** of code quality standards
- **Providing consistent quality metrics** across all stories
- **Catching issues early** before manual QA time investment
- **Ensuring production readiness** of all approved stories
- **Creating objective quality evidence** for QA reports

The pre-push hook validation is **mandatory** and **complementary** to existing manual QA processes - it does not replace functional testing, design validation, or acceptance criteria verification.