defmodule TheMaestro.TUI.SecurityConfirmation do
  @moduledoc """
  Terminal user interface for MCP security confirmation dialogs.
  
  Provides a command-line interface for users to review and confirm
  MCP tool execution requests, including risk assessment information
  and trust management options.
  """

  alias TheMaestro.TUI.MenuHelpers
  alias TheMaestro.MCP.Security.ConfirmationEngine.{ConfirmationRequest, ConfirmationResult}

  @doc """
  Presents a security confirmation dialog in the terminal.

  ## Parameters
  - `tool_name`: Name of the MCP tool being executed
  - `parameters`: Tool parameters (sanitized)
  - `confirmation_request`: ConfirmationRequest struct with risk assessment
  - `context`: Execution context with server and user information
  - `sanitization_warnings`: List of parameter sanitization warnings

  ## Returns
  - `{:ok, ConfirmationResult.t()}`: User confirmed execution
  - `{:error, :cancelled}`: User cancelled execution
  """
  @spec prompt_confirmation(String.t(), map(), ConfirmationRequest.t(), map(), [String.t()]) ::
    {:ok, ConfirmationResult.t()} | {:error, :cancelled}
  def prompt_confirmation(tool_name, parameters, confirmation_request, context, sanitization_warnings \\ []) do
    MenuHelpers.clear_screen()
    display_confirmation_header()
    display_tool_info(tool_name, context.server_id)
    display_risk_assessment(confirmation_request.risk_assessment)
    display_parameters(parameters)
    
    if length(sanitization_warnings) > 0 do
      display_sanitization_warnings(sanitization_warnings)
    end

    display_confirmation_options(confirmation_request.risk_assessment.risk_level)
    choice = get_user_choice(confirmation_request.risk_assessment.risk_level)
    
    case choice do
      :cancelled -> {:error, :cancelled}
      _ -> {:ok, create_confirmation_result(choice)}
    end
  end

  # Private Functions

  defp display_confirmation_header do
    MenuHelpers.display_title("🔒 MCP SECURITY CONFIRMATION", 80)
  end

  defp display_tool_info(tool_name, server_id) do
    IO.puts([IO.ANSI.bright(), "Tool Information:"])
    IO.puts("  Tool: #{IO.ANSI.cyan()}#{tool_name}#{IO.ANSI.reset()}")
    IO.puts("  Server: #{IO.ANSI.cyan()}#{server_id}#{IO.ANSI.reset()}")
    IO.puts("")
  end

  defp display_risk_assessment(risk_assessment) do
    {color, symbol} = case risk_assessment.risk_level do
      :low -> {IO.ANSI.green(), "✓"}
      :medium -> {IO.ANSI.yellow(), "⚠"}
      :high -> {IO.ANSI.red(), "⚠"}
      :critical -> {IO.ANSI.red(), "🚨"}
      _ -> {IO.ANSI.white(), "?"}
    end

    risk_text = risk_assessment.risk_level |> to_string() |> String.upcase()
    
    IO.puts([IO.ANSI.bright(), "Risk Assessment:"])
    IO.puts("  #{color}#{symbol} #{risk_text} RISK#{IO.ANSI.reset()}")
    
    if length(risk_assessment.reasons) > 0 do
      IO.puts("\n  Risk Factors:")
      Enum.each(risk_assessment.reasons, fn reason ->
        IO.puts("    • #{reason}")
      end)
    end
    
    IO.puts("")
  end

  defp display_parameters(parameters) when map_size(parameters) > 0 do
    IO.puts([IO.ANSI.bright(), "Parameters:"])
    
    formatted = case Jason.encode(parameters, pretty: true) do
      {:ok, json} -> json
      {:error, _} -> inspect(parameters, pretty: true)
    end
    
    # Split lines and indent each one
    formatted
    |> String.split("\n")
    |> Enum.each(fn line ->
      IO.puts("  #{IO.ANSI.cyan()}#{line}#{IO.ANSI.reset()}")
    end)
    
    IO.puts("")
  end
  defp display_parameters(_), do: :ok

  defp display_sanitization_warnings(warnings) do
    IO.puts([IO.ANSI.yellow(), IO.ANSI.bright(), "⚠ Sanitization Warnings:"])
    
    Enum.each(warnings, fn warning ->
      IO.puts([IO.ANSI.yellow(), "    • #{warning}#{IO.ANSI.reset()}"])
    end)
    
    IO.puts("")
  end

  defp display_confirmation_options(risk_level) do
    IO.puts([IO.ANSI.bright(), "Options:"])
    IO.puts("  #{IO.ANSI.green()}1#{IO.ANSI.reset()} Execute once")
    
    if risk_level in [:low, :medium] do
      IO.puts("  #{IO.ANSI.green()}2#{IO.ANSI.reset()} Always allow this tool")
      IO.puts("  #{IO.ANSI.green()}3#{IO.ANSI.reset()} Always trust this server")
    end
    
    if risk_level in [:high, :critical] do
      IO.puts("  #{IO.ANSI.red()}4#{IO.ANSI.reset()} Block this tool")
    end
    
    IO.puts("  #{IO.ANSI.red()}5#{IO.ANSI.reset()} Cancel")
    IO.puts("")
  end

  defp get_user_choice(risk_level) do
    max_option = case risk_level do
      level when level in [:low, :medium] -> 5
      level when level in [:high, :critical] -> 5
      _ -> 5
    end

    prompt = "Choose an option (1-#{max_option}): "
    input = IO.gets(prompt) |> String.trim()

    case {input, risk_level} do
      {"1", _} -> :execute_once
      {"2", level} when level in [:low, :medium] -> :always_allow_tool
      {"3", level} when level in [:low, :medium] -> :always_trust_server
      {"4", level} when level in [:high, :critical] -> :block_tool
      {"5", _} -> :cancelled
      {_, _} ->
        IO.puts([IO.ANSI.red(), "Invalid choice. Please try again.", IO.ANSI.reset()])
        IO.puts("")
        get_user_choice(risk_level)
    end
  end

  defp create_confirmation_result(choice) do
    {decision, message, trust_updated} = case choice do
      :execute_once ->
        {:allow, "User chose to execute once via TUI", false}
        
      :always_allow_tool ->
        {:allow, "User chose to always allow this tool via TUI", true}
        
      :always_trust_server ->
        {:allow, "User chose to always trust this server via TUI", true}
        
      :block_tool ->
        {:deny, "User chose to block this tool via TUI", true}
        
      :cancelled ->
        {:deny, "User cancelled via TUI", false}
    end

    %ConfirmationResult{
      decision: decision,
      choice: choice,
      message: message,
      trust_updated: trust_updated,
      audit_logged: true
    }
  end

  @doc """
  Displays a simple security status message for non-interactive scenarios.
  
  Used when confirmation is not required but user should be informed
  of security decisions.
  """
  @spec display_security_status(String.t(), String.t(), atom()) :: :ok
  def display_security_status(tool_name, server_id, decision) do
    {color, symbol, message} = case decision do
      :allowed -> {IO.ANSI.green(), "✓", "ALLOWED"}
      :denied -> {IO.ANSI.red(), "✗", "DENIED"}
      :trusted -> {IO.ANSI.blue(), "🔒", "TRUSTED"}
      _ -> {IO.ANSI.white(), "?", "UNKNOWN"}
    end

    IO.puts([
      color, symbol, " MCP Security: ",
      message, " - ",
      tool_name, " (", server_id, ")",
      IO.ANSI.reset()
    ])
  end

  @doc """
  Displays security policy violation message.
  """
  @spec display_security_violation(String.t(), String.t(), String.t()) :: :ok
  def display_security_violation(tool_name, server_id, reason) do
    IO.puts([
      IO.ANSI.red(), IO.ANSI.bright(),
      "🚨 SECURITY VIOLATION BLOCKED",
      IO.ANSI.reset()
    ])
    IO.puts("Tool: #{tool_name}")
    IO.puts("Server: #{server_id}")
    IO.puts("Reason: #{reason}")
    IO.puts("")
  end
end