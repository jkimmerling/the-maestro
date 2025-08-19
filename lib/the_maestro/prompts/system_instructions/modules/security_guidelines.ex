defmodule TheMaestro.Prompts.SystemInstructions.Modules.SecurityGuidelines do
  @moduledoc """
  Security guidelines module for system instructions.
  """

  @doc """
  Generates security guidelines based on the given context.
  """
  def generate(context) do
    sandbox_status = get_sandbox_status(context)
    trust_level = Map.get(context, :trust_level, :medium)

    base_guidelines = """
    ## Security and Safety Rules

    - **Explain Critical Commands:** Before executing commands that modify the file system, codebase, or system state, you *must* provide a brief explanation of the command's purpose and potential impact.
    - **Security First:** Always apply security best practices. Never introduce code that exposes, logs, or commits secrets, API keys, or other sensitive information.
    - **Sandboxing Awareness:** You are running #{sandbox_status}. Consider the implications for file system access and external commands.
    - **Trust Verification:** Verify tool and server trust levels before execution. Request confirmation when appropriate.
    - **Input Validation:** Always validate and sanitize user inputs, especially when constructing commands or file paths.
    - **Least Privilege:** Use the minimum necessary permissions and access levels for each operation.
    """

    additional_guidelines = get_trust_level_guidelines(trust_level)

    base_guidelines <> additional_guidelines
  end

  defp get_sandbox_status(context) do
    case Map.get(context, :sandbox_enabled, false) do
      true -> "in a sandboxed environment with restricted system access"
      false -> "in a production environment with full system access"
    end
  end

  defp get_trust_level_guidelines(trust_level) do
    case trust_level do
      :low ->
        """

        ### Additional Security Measures (Low Trust Level)
        - **Enhanced Verification:** All file system modifications require additional verification
        - **Command Confirmation:** Request explicit confirmation before executing any system commands
        - **Limited Scope:** Restrict operations to explicitly approved directories and files
        - **Audit Logging:** All actions will be logged for security audit purposes
        """

      :medium ->
        """

        ### Standard Security Measures (Medium Trust Level)
        - **Risk Assessment:** Evaluate the risk level of each operation before execution
        - **Confirmation for Critical Operations:** Request confirmation for operations that could affect system stability
        - **Safe Defaults:** Use conservative defaults for file permissions and access controls
        """

      :high ->
        """

        ### Streamlined Security (High Trust Level)
        - **Efficient Operations:** Execute approved operations with minimal friction
        - **Smart Defaults:** Use intelligent defaults based on context and best practices
        - **Proactive Security:** Implement security measures automatically without requiring explicit confirmation
        """

      _ ->
        ""
    end
  end
end
