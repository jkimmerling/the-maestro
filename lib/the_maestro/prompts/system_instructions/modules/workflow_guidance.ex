defmodule TheMaestro.Prompts.SystemInstructions.Modules.WorkflowGuidance do
  @moduledoc """
  Task-specific workflow guidance module for system instructions.
  """

  @doc """
  Generates workflow-specific instructions based on the task context.
  """
  def generate(task_context) do
    primary_task_type = Map.get(task_context, :primary_task_type, :generic)

    case primary_task_type do
      :software_engineering ->
        generate_software_engineering_workflow(task_context)

      :new_application ->
        generate_new_application_workflow(task_context)

      :debugging ->
        generate_debugging_workflow(task_context)

      :documentation ->
        generate_documentation_workflow(task_context)

      _ ->
        generate_generic_workflow(task_context)
    end
  end

  defp generate_software_engineering_workflow(task_context) do
    complexity_level = Map.get(task_context, :complexity_level, :moderate)
    
    base_workflow = """
    ## Software Engineering Tasks
    When requested to perform tasks like fixing bugs, adding features, refactoring, or explaining code, follow this sequence:
    1. **Understand:** Use search tools extensively to understand file structures, existing code patterns, and conventions
    2. **Plan:** Build a coherent plan based on understanding. Share concise plan with user if helpful
    3. **Implement:** Use available tools, strictly adhering to project conventions
    4. **Verify (Tests):** Verify changes using project's testing procedures
    5. **Verify (Standards):** Execute project-specific build, linting and type-checking commands
    """

    complexity_additions = case complexity_level do
      :high ->
        """
        
        ### High Complexity Task Guidelines
        - Break down complex changes into smaller, manageable steps
        - Consider architectural implications of changes
        - Document rationale for significant design decisions
        - Plan rollback strategy for major changes
        """

      :moderate ->
        """
        
        ### Moderate Complexity Task Guidelines
        - Ensure changes are well-tested and documented
        - Consider impact on related components
        - Follow established patterns and conventions
        """

      :low ->
        """
        
        ### Simple Task Guidelines
        - Make minimal, focused changes
        - Verify changes don't introduce unintended side effects
        """
    end

    base_workflow <> complexity_additions
  end

  defp generate_new_application_workflow(_task_context) do
    """
    ## New Application Development
    **Goal:** Autonomously implement and deliver a visually appealing, substantially complete, and functional prototype.
    1. **Understand Requirements:** Analyze user request for core features, UX, visual aesthetic, platform
    2. **Propose Plan:** Present clear, concise, high-level summary to user
    3. **User Approval:** Obtain user approval for the proposed plan
    4. **Implementation:** Autonomously implement each feature per approved plan
    5. **Verify:** Review work against original request and approved plan
    6. **Solicit Feedback:** Provide instructions on how to start the application

    ### New Application Guidelines
    - Focus on core functionality first, then enhance
    - Use established frameworks and best practices
    - Implement proper error handling and validation
    - Create clear documentation for setup and usage
    """
  end

  defp generate_debugging_workflow(_task_context) do
    """
    ## Debugging Tasks
    When investigating issues, errors, or unexpected behavior, follow this systematic approach:
    1. **Reproduce:** Confirm the issue can be reproduced consistently
    2. **Investigate:** Examine logs, error messages, and relevant code sections
    3. **Root Cause:** Identify the underlying cause of the issue
    4. **Fix:** Implement the minimal fix that addresses the root cause
    5. **Test:** Verify the fix resolves the issue without introducing new problems
    6. **Document:** Document the issue, cause, and solution for future reference

    ### Debugging Guidelines
    - Start with the simplest possible explanations
    - Use logging and debugging tools to gather evidence
    - Test fixes in isolation before deploying
    - Consider both immediate and long-term implications of fixes
    """
  end

  defp generate_documentation_workflow(_task_context) do
    """
    ## Documentation Tasks
    When creating or updating documentation, follow these guidelines:
    1. **Audience Analysis:** Understand who will use this documentation
    2. **Content Planning:** Structure information logically and comprehensively
    3. **Clear Writing:** Use clear, concise language appropriate for the audience
    4. **Examples:** Include practical examples and code snippets where relevant
    5. **Review:** Check for accuracy, completeness, and clarity
    6. **Maintenance:** Ensure documentation stays current with code changes

    ### Documentation Guidelines
    - Focus on the "why" as much as the "what" and "how"
    - Use consistent formatting and structure
    - Include troubleshooting and common issues
    - Provide both overview and detailed reference information
    """
  end

  defp generate_generic_workflow(_task_context) do
    """
    ## General Task Workflow
    For tasks that don't fit specific categories, follow this general approach:
    1. **Analyze:** Understand the requirements and constraints
    2. **Plan:** Develop a clear approach to accomplish the task
    3. **Execute:** Implement the solution using available tools and knowledge
    4. **Validate:** Verify that the task has been completed successfully
    5. **Communicate:** Provide clear feedback on what was accomplished

    ### General Guidelines
    - Ask for clarification when requirements are ambiguous
    - Break complex tasks into manageable steps
    - Document important decisions and assumptions
    - Be transparent about limitations and constraints
    """
  end
end