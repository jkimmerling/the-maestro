# CleanOps Elixir Project Rules & Standards

**Critical Project Guidelines for Developers and QA Engineers**

This document consolidates all project-specific rules, quality standards, and development practices that must be followed in the CleanOps Elixir project.

---

## 🚨 ZERO TOLERANCE POLICIES

### Git Hook Bypassing - IMMEDIATE PROJECT REMOVAL

**ABSOLUTELY FORBIDDEN - NO EXCEPTIONS - IMMEDIATE CONSEQUENCES:**

Any use of the following commands results in **IMMEDIATE PROJECT REMOVAL**:

```bash
# ❌ FORBIDDEN - IMMEDIATE PROJECT REMOVAL
git commit --no-verify
git commit -n
git push --no-verify  
git push --force
git push --force-with-lease
git push -f

# ❌ ALSO FORBIDDEN - Hook manipulation
git config core.hooksPath /dev/null
chmod -x .git/hooks/*
rm .git/hooks/*
```

**CONSEQUENCES - NO WARNINGS:**
- **First and only response**: Immediate project removal
- **Zero tolerance**: No exceptions, no warnings, no second chances
- **Treated as sabotage** of code quality and team standards

**IF HOOKS FAIL - FIX THE ISSUES, NEVER BYPASS:**
```bash
# ✅ CORRECT APPROACH - ALWAYS
# 1. READ hook failure message carefully
# 2. FIX the identified issues (format, test, lint, security)
# 3. Run checks locally: mix format, mix test, mix credo
# 4. Commit and push normally - let hooks run
git commit -m "Your message"
git push
```

**Professional developers solve problems. They never bypass protections.**

---

## 🎯 TOP REQUIREMENT: UI Design Excellence

### Mandatory Visual Quality Standards

**Professional UI standards are REQUIRED for all UI work - no exceptions**

#### Development Quality Gate
- [ ] All interactive states implemented and validated
- [ ] Responsive behavior follows modern web standards
- [ ] Typography, colors, spacing follow design system
- [ ] Accessibility standards met (WCAG 2.1 AA minimum)
- [ ] Design consistency report generated and approved

#### QA Quality Gate  
- [ ] UI Quality Checklist 100% complete
- [ ] browsermcp visual regression tests all pass
- [ ] Cross-browser consistency verified
- [ ] All responsive breakpoints tested and approved
- [ ] Performance and accessibility requirements met

#### Quality Standards

**Exact Match Required For:**
- Colors (consistent with design system)
- Typography (font-family, font-size, font-weight, line-height)
- Spacing (margins, padding, gaps following system)
- Borders (width, color, radius)
- Shadows and effects
- Component dimensions and positioning
- Hover/focus/active states
- Animation timing and easing

**Acceptance Criteria Template:**
```
✅ UI QUALITY VERIFICATION CHECKLIST (Required for story completion):
□ Design system compliance verified
□ Typography follows established patterns
□ Colors follow design system guidelines
□ Spacing follows design system rules
□ Responsive behavior meets modern standards
□ Interactive states properly implemented
□ Cross-browser visual consistency confirmed
□ browsermcp visual regression tests pass
□ No visual regressions introduced
□ Accessibility requirements met
```

#### Immediate Rejection Criteria
**Stories will be AUTOMATICALLY REJECTED if:**

- Design system compliance is not followed
- Typography doesn't follow established patterns
- Colors deviate from design system
- Spacing is inconsistent with system
- Interactive states are missing or incorrect
- Responsive behavior doesn't meet modern standards
- Cross-browser inconsistencies exist
- Accessibility standards not met
- browsermcp visual tests fail

---

## 📚 MANDATORY: Archon Documentation Integration

### Research and Documentation Reference (REQUIRED)

**CRITICAL: Use Archon MCP server for documentation research and knowledge retrieval - THIS IS MANDATORY.**

#### Available Archon Tools for Research

```bash
# Research best practices and patterns
archon:perform_rag_query(
  query="[technology/pattern] best practices",
  match_count=3-5
)

# Find implementation examples
archon:search_code_examples(
  query="[feature] implementation examples",
  match_count=2-3
)
```

#### MANDATORY Research Requirements

**BEFORE any implementation, you MUST:**
- Research established patterns using Archon RAG queries
- Find security best practices for your specific technologies
- Discover testing strategies and examples
- Reference architectural guidelines and conventions

**Failure to use Archon for research is a quality gate violation.**

---

## 🧪 Elixir Testing Standards & Anti-Theater Measures

### Project-Specific Testing Requirements

**See [Testing Strategies](../standards/testing-strategies.md) for universal testing principles and TDD best practices.**

#### Elixir-Specific Anti-Theater Measures

**✅ PASS Criteria for Elixir Tests:**
- Tests use proper ExUnit patterns with `describe` blocks
- LiveView tests verify actual user interactions, not just component rendering
- Phoenix Context tests verify complete business workflows
- GenServer tests verify behavior, not internal state
- Database tests use real database connections (no mocking Repo)

**❌ FAIL Criteria (Elixir Test Theater):**
- Tests mock Ecto.Repo operations instead of using database
- Tests verify internal GenServer state instead of public API
- LiveView tests only check template rendering without interactions
- Tests use Process.sleep instead of proper OTP synchronization

#### Elixir-Specific Business Value Testing

**HIGH VALUE Tests for CleanOps:**
```elixir
# ✅ Complete Phoenix Context workflow
test "customer creation workflow with job assignment" do
  customer_params = valid_customer_attributes()
  
  {:ok, customer} = Customers.create_customer(customer_params)
  {:ok, job} = Jobs.create_job(customer, valid_job_attributes())
  
  assert customer.status == :active
  assert job.customer_id == customer.id
  assert Jobs.list_jobs_for_customer(customer) |> length() == 1
end

# ✅ LiveView integration testing
test "job creation form validates and creates job", %{conn: conn} do
  customer = customer_fixture()
  
  {:ok, lv, _html} = live(conn, ~p"/jobs/new?customer_id=#{customer.id}")
  
  lv
  |> form("#job-form", job: @valid_attrs)
  |> render_submit()
  
  assert_redirected(lv, ~p"/jobs")
  assert Jobs.list_jobs() |> length() == 1
end

# ✅ Phoenix Context with side effects
test "invoice generation triggers email notification" do
  customer = customer_fixture()
  job = job_fixture(%{customer: customer})
  
  {:ok, invoice} = Invoices.generate_invoice(job)
  
  assert invoice.status == :pending
  assert_email_sent(to: customer.email, subject: ~r/Invoice/)
end
```

#### Elixir-Specific Error Handling
```elixir
describe "Ecto changeset validation" do
  test "rejects customer with invalid email format" do
    invalid_attrs = %{email: "not-an-email", name: "Valid Name"}
    
    {:error, changeset} = Customers.create_customer(invalid_attrs)
    
    assert "has invalid format" in errors_on(changeset).email
  end
  
  test "handles database constraint violations" do
    customer = customer_fixture()
    duplicate_attrs = %{email: customer.email, name: "Different Name"}
    
    {:error, changeset} = Customers.create_customer(duplicate_attrs)
    
    assert "has already been taken" in errors_on(changeset).email
  end
end
```

#### Phoenix LiveView Testing Patterns
```elixir
# ✅ Test user interactions, not just rendering
test "job form shows validation errors on invalid input", %{conn: conn} do
  {:ok, lv, _html} = live(conn, ~p"/jobs/new")
  
  # Submit form with invalid data
  lv
  |> form("#job-form", job: %{title: "", description: ""})
  |> render_submit()
  
  # Verify error messages appear
  assert has_element?(lv, "#job-form [phx-feedback-for='job[title]']")
  assert render(lv) =~ "can't be blank"
end

# ✅ Test real-time updates
test "job status updates are pushed to all connected users", %{conn: conn} do
  job = job_fixture()
  
  {:ok, lv1, _} = live(conn, ~p"/jobs/#{job.id}")
  {:ok, lv2, _} = live(conn, ~p"/jobs/#{job.id}")
  
  # Update job status from one connection
  Jobs.update_job(job, %{status: :completed})
  
  # Verify both connections receive the update
  assert render(lv1) =~ "Completed"
  assert render(lv2) =~ "Completed"
end
```

#### Elixir Anti-Patterns to Avoid

**❌ DON'T: Mock Ecto Operations**
```elixir
# BAD - Mocking database operations
test "creates user successfully" do
  expect(MockRepo, :insert, fn _ -> {:ok, %User{}} end)
  
  result = Users.create_user(%{email: "test@example.com"})
  assert {:ok, %User{}} = result
end

# GOOD - Use real database with proper cleanup
test "creates user successfully" do
  user_attrs = %{email: "test@example.com", name: "Test User"}
  
  {:ok, user} = Users.create_user(user_attrs)
  
  assert user.email == "test@example.com"
  assert Users.get_user!(user.id) == user
end
```

**❌ DON'T: Test GenServer Internal State**
```elixir
# BAD - Testing internal GenServer state
test "stores correct state in GenServer" do
  {:ok, pid} = JobProcessor.start_link([])
  :sys.get_state(pid)  # Don't access internal state
end

# GOOD - Test GenServer public API
test "job processor handles job completion" do
  {:ok, pid} = JobProcessor.start_link([])
  job = job_fixture()
  
  :ok = JobProcessor.process_job(pid, job)
  
  updated_job = Jobs.get_job!(job.id)
  assert updated_job.status == :processing
end
```

**❌ DON'T: Use Process.sleep for Timing**
```elixir
# BAD - Using sleep for async operations
test "background job completes" do
  BackgroundWorker.perform_async(:send_email)
  Process.sleep(1000)  # Brittle timing
  assert email_sent?()
end

# GOOD - Use proper OTP synchronization
test "background job completes" do
  task = Task.async(fn -> BackgroundWorker.perform(:send_email) end)
  
  assert :ok = Task.await(task, 5000)
  assert email_sent?()
end
```

---

## 📋 Team Responsibilities & Quality Gates

### For Product Owners & Scrum Masters
- **Every UI story MUST use complete design quality validation requirements**
- **All acceptance criteria MUST include Archon research requirements**
- **Stories cannot be marked "Done" without:**
  - Design system compliance validation
  - Archon research completion verification
  - Anti-theater test criteria met
- **Stories MUST be rejected if quality standards are not met**

### For Developers  
- **MUST follow design system standards for UI verification**
- **MUST achieve professional-grade design consistency**
- **MUST use Archon MCP proactively throughout development**
- **MUST implement ALL interactive states following design system**
- **MUST validate across all responsive breakpoints**
- **MUST write business-value focused tests (not test theater)**
- **MUST follow proper git workflow (never bypass hooks)**

### For QA Engineers
- **MUST complete comprehensive UI quality validation for every UI story**
- **MUST use browsermcp for visual regression testing**
- **MUST validate Archon research was conducted and applied**
- **MUST test all responsive breakpoints across browsers**
- **MUST reject stories that don't meet business value testing criteria**
- **MUST validate anti-theater measures in test suites**
- **Stories MUST be rejected if design system compliance is not met**

### Code Review Requirements

**ALL code reviews must confirm:**
- Archon research was conducted and applied
- Implementation follows documented best practices
- Security and performance considerations were addressed per Archon guidance
- Design system compliance is achieved (for UI work)
- Tests provide real business value (not theater)
- No git hook bypassing evidence

---

## 🎯 Success Metrics & Enforcement

### Key Performance Indicators
- **Design Quality Score**: Must maintain professional standards across all UI components
- **First-Pass QA Success**: Target 100% of stories pass initial QA review
- **Archon Integration**: 100% of stories include documented Archon research
- **Test Quality**: Zero test theater - all tests must verify business behavior
- **Hook Compliance**: Zero bypass attempts tolerated

### Tracking and Reporting
- Weekly design quality score reports
- Monthly process compliance audits
- Quarterly tooling effectiveness reviews
- Real-time git hook compliance monitoring
- Test quality metrics and theater detection

### Detection and Monitoring

#### Automated Detection
- Git logs automatically scanned for bypass flags
- Repository webhooks detect forced pushes
- CI/CD systems log all override attempts
- Test suites analyzed for theater patterns
- Design quality automatically measured

#### Team Accountability
- All team members must report policy violations
- Code reviews check for compliance evidence
- Regular training reinforces policy importance
- Anonymous reporting system available

---

## 🔄 Workflow Integration

### Story Creation Process
1. Use complete UI story template with design system references
2. Include comprehensive Archon research requirements
3. Define all validation requirements and acceptance criteria
4. Set clear business value testing requirements

### Development Process
1. **Research Phase**: Query Archon for relevant patterns and best practices
2. **Design Phase**: Follow design system standards and guidelines
3. **Implementation Phase**: Code with continuous design quality and Archon validation
4. **Testing Phase**: Write business-value focused tests using Archon patterns
5. **Quality Phase**: Achieve design system compliance and generate quality reports

### QA Process  
1. Complete comprehensive UI quality validation checklist
2. Verify Archon research integration and best practice application
3. Execute visual testing across all browsers and devices
4. Validate business value in test suite (reject test theater)
5. Provide final approval or rejection with detailed feedback

### Release Process
1. Verify all quality gates passed
2. Confirm stakeholder approvals obtained
3. Validate zero hook bypass attempts
4. Deploy with confidence in design quality and code quality
5. Monitor for any regressions or compliance issues

---

## 🚀 Summary

**This project demands excellence in every aspect:**

### Non-Negotiable Requirements
1. **Professional design system compliance** for all UI work
2. **Proactive Archon documentation usage** for all development
3. **Business-value focused testing** (zero tolerance for test theater)
4. **Zero git hook bypassing** (immediate project removal)
5. **Complete quality gate compliance** before any story completion

### Professional Standards
- **Research first, code second** using Archon MCP
- **Professional-grade implementation** following design standards
- **Meaningful tests** that verify real business behavior
- **Quality gates** that cannot be compromised
- **Team accountability** at every level

**Remember: Our users and clients deserve a product that works flawlessly, looks exactly as designed, and maintains the highest quality standards. Excellence in these areas is what sets professional teams apart.**

---

**🚨 This document overrides any conflicting requirements. These standards are mandatory for all team members.**