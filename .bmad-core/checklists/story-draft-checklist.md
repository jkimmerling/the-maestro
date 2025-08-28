<!-- Powered by BMAD™ Core -->

# Story Draft Checklist

The Scrum Master should use this checklist to validate that each story contains sufficient context for a developer agent to implement it successfully, while assuming the dev agent has reasonable capabilities to figure things out.

[[LLM: INITIALIZATION INSTRUCTIONS - STORY DRAFT VALIDATION

Before proceeding with this checklist, ensure you have access to:

1. The story document being validated (usually in docs/stories/ or provided directly)
2. The parent epic context
3. Any referenced architecture or design documents
4. Previous related stories if this builds on prior work

IMPORTANT: This checklist validates individual stories BEFORE implementation begins.

VALIDATION PRINCIPLES:

1. Clarity - A developer should understand WHAT to build
2. Context - WHY this is being built and how it fits
3. Guidance - Key technical decisions and patterns to follow
4. Testability - How to verify the implementation works
5. Self-Contained - Most info needed is in the story itself

REMEMBER: We assume competent developer agents who can:

- Research documentation and codebases
- Make reasonable technical decisions
- Follow established patterns
- Ask for clarification when truly stuck

We're checking for SUFFICIENT guidance, not exhaustive detail.]]

## 1. GOAL & CONTEXT CLARITY

[[LLM: Without clear goals, developers build the wrong thing. Verify:

1. The story states WHAT functionality to implement
2. The business value or user benefit is clear
3. How this fits into the larger epic/product is explained
4. Dependencies are explicit ("requires Story X to be complete")
5. Success looks like something specific, not vague]]

- [ ] Story goal/purpose is clearly stated
- [ ] Relationship to epic goals is evident
- [ ] How the story fits into overall system flow is explained
- [ ] Dependencies on previous stories are identified (if applicable)
- [ ] Business context and value are clear

## 2. UI DESIGN REQUIREMENTS (MANDATORY FIRST STEP FOR UI STORIES)

[[LLM: 🚨 CRITICAL WORKFLOW REQUIREMENT 🚨

FOR ANY UI-RELATED STORY, THIS MUST BE VALIDATED FIRST, BEFORE ANY IMPLEMENTATION GUIDANCE:

The current workflow problem: Agents start coding without understanding design system requirements → must re-implement to meet professional standards.

REQUIRED WORKFLOW: Agent must understand ALL design system requirements BEFORE writing any code.

1. Check if this story involves ANY UI/frontend work
2. If UI work: REFERENCE the design system documentation and standards
3. ALL design system guidelines MUST be prominently featured at the TOP of the drafted story
4. Story MUST include a "🎨 DESIGN SYSTEM - UNDERSTAND FIRST BEFORE CODING" section as the FIRST technical section
5. Story MUST explicitly instruct: "MANDATORY: Review and understand ALL design system standards before writing any code"
6. Story MUST follow the UI Story Template at `docs/architecture/ui-story-template.md`
7. Mark as CRITICAL FAILURE if design system standards are not referenced
8. Mark as CRITICAL FAILURE if design section is not positioned as the FIRST implementation step]]

- [ ] **🚨 DESIGN-FIRST WORKFLOW**: If this is a UI story, it starts with "🎨 DESIGN SYSTEM - UNDERSTAND FIRST BEFORE CODING" as the first technical section
- [ ] **🚨 DESIGN SYSTEM VALIDATION**: ALL design system guidelines from project documentation are prominently included
- [ ] **🚨 PRE-CODING MANDATE**: Story explicitly states "MANDATORY: Review and understand ALL design system standards before writing any code"
- [ ] **UI TEMPLATE COMPLIANCE**: UI stories follow the template at `docs/architecture/ui-story-template.md` 
- [ ] **COMPLETE DESIGN SPECIFICATIONS**: Includes color palette, typography, spacing, component specifications from design system
- [ ] **RESPONSIVE DESIGN COVERAGE**: Design system responsive breakpoints and standards are included
- [ ] **PROFESSIONAL QUALITY REQUIREMENT**: Story explicitly requires professional-grade design system compliance
- [ ] **VISUAL TESTING MANDATE**: Story specifically requires Playwright visual regression tests to validate design consistency

## 3. TECHNICAL IMPLEMENTATION GUIDANCE

[[LLM: After design system requirements are established (for UI stories), developers need technical context to start coding. Check:

1. Key files/components to create or modify are mentioned
2. Technology choices are specified where non-obvious
3. Integration points with existing code are identified
4. Data models or API contracts are defined or referenced
5. Non-standard patterns or exceptions are called out

Note: We don't need every file listed - just the important ones.]]

- [ ] Key files to create/modify are identified (not necessarily exhaustive)
- [ ] Technologies specifically needed for this story are mentioned
- [ ] Critical APIs or interfaces are sufficiently described
- [ ] Necessary data models or structures are referenced
- [ ] Required environment variables are listed (if applicable)
- [ ] Any exceptions to standard coding patterns are noted

## 4. REFERENCE EFFECTIVENESS

[[LLM: References should help, not create a treasure hunt. Ensure:

1. References point to specific sections, not whole documents
2. The relevance of each reference is explained
3. Critical information is summarized in the story
4. References are accessible (not broken links)
5. Previous story context is summarized if needed]]

- [ ] References to external documents point to specific relevant sections
- [ ] Critical information from previous stories is summarized (not just referenced)
- [ ] Context is provided for why references are relevant
- [ ] References use consistent format (e.g., `docs/filename.md#section`)

## 5. SELF-CONTAINMENT ASSESSMENT

[[LLM: Stories should be mostly self-contained to avoid context switching. Verify:

1. Core requirements are in the story, not just in references
2. Domain terms are explained or obvious from context
3. Assumptions are stated explicitly
4. Edge cases are mentioned (even if deferred)
5. The story could be understood without reading 10 other documents]]

- [ ] Core information needed is included (not overly reliant on external docs)
- [ ] Implicit assumptions are made explicit
- [ ] Domain-specific terms or concepts are explained
- [ ] Edge cases or error scenarios are addressed

## 6. TYPE SPECIFICATIONS & DIALYZER VALIDATION (ELIXIR PROJECTS)

[[LLM: For Elixir projects, type safety is critical for maintainability and correctness. Check:

1. Story specifies that @spec annotations are required for all public functions
2. Story specifies that @type definitions are needed for custom data structures  
3. Story requires comprehensive typespecs for LiveView callbacks (mount, handle_event, handle_info)
4. Story mandates QA must run Dialyzer validation during review process
5. Story specifies typespecs must follow Elixir conventions and project patterns
6. Story requires documentation of complex type relationships]]

- [ ] **@spec REQUIREMENTS**: Story explicitly requires @spec annotations for all public functions
- [ ] **@type DEFINITIONS**: Story specifies @type definitions needed for custom data structures and complex parameters
- [ ] **LIVEVIEW TYPESPECS**: For LiveView stories, comprehensive typespecs required for mount/3, handle_event/3, handle_info/2, etc.
- [ ] **DIALYZER VALIDATION**: Story explicitly states QA must run `mix dialyzer` and resolve all warnings before approval
- [ ] **PRE-PUSH HOOK VALIDATION**: Story explicitly requires QA to execute `.git/hooks/pre-push` as part of validation process
- [ ] **TYPE COMPLEXITY GUIDANCE**: For complex types (union types, nested structs), story provides guidance on typespec patterns
- [ ] **PROJECT TYPESPEC STANDARDS**: Story references project-specific typespec conventions and patterns to follow

## 7. TESTING GUIDANCE

[[LLM: Testing ensures the implementation actually works. Check:

1. Test approach is specified (unit, integration, e2e)
2. Key test scenarios are listed
3. Success criteria are measurable
4. Special test considerations are noted
5. Acceptance criteria in the story are testable]]

- [ ] Required testing approach is outlined
- [ ] Key test scenarios are identified
- [ ] Success criteria are defined
- [ ] Special testing considerations are noted (if applicable)

## VALIDATION RESULT

[[LLM: FINAL STORY VALIDATION REPORT

Generate a concise validation report:

1. Quick Summary
   - Story readiness: READY / NEEDS REVISION / BLOCKED
   - Clarity score (1-10)
   - Major gaps identified

2. Fill in the validation table with:
   - PASS: Requirements clearly met
   - PARTIAL: Some gaps but workable
   - FAIL: Critical information missing

3. Specific Issues (if any)
   - List concrete problems to fix
   - Suggest specific improvements
   - Identify any blocking dependencies

4. Developer Perspective
   - Could YOU implement this story as written?
   - What questions would you have?
   - What might cause delays or rework?

Be pragmatic - perfect documentation doesn't exist, but it must be enough to provide the extreme context a dev agent needs to get the work down and not create a mess.]]

| Category                                                    | Status | Issues |
| ----------------------------------------------------------- | ------ | ------ |
| 1. Goal & Context Clarity                                   | _TBD_  |        |
| 2. UI Design Requirements (Mandatory First Step for UI) | _TBD_  |        |
| 3. Technical Implementation Guidance                        | _TBD_  |        |
| 4. Reference Effectiveness                                  | _TBD_  |        |
| 5. Self-Containment Assessment                              | _TBD_  |        |
| 6. Type Specifications & Dialyzer Validation (Elixir)      | _TBD_  |        |
| 7. Testing Guidance                                         | _TBD_  |        |

**Final Assessment:**

- READY: The story provides sufficient context for implementation
- NEEDS REVISION: The story requires updates (see issues)
- BLOCKED: External information required (specify what information)
