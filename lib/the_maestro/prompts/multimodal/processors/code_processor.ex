defmodule TheMaestro.Prompts.MultiModal.Processors.CodeProcessor do
  @moduledoc """
  Specialized processor for code content.
  """

  @spec process(map(), map()) :: map()
  def process(%{type: :code, content: content, metadata: metadata} = _item, _context) do
    language = Map.get(metadata, :language, :unknown)

    %{
      syntax_analysis: %{
        is_valid: validate_syntax(content, language),
        language_detected: language
      },
      complexity_analysis: %{
        cyclomatic_complexity: calculate_complexity(content),
        nesting_depth: calculate_nesting_depth(content)
      },
      security_analysis: %{
        vulnerabilities: detect_vulnerabilities(content),
        has_issues: has_security_issues?(content)
      },
      style_analysis: %{style_issues: []},
      documentation_extraction: %{comments: []},
      code_enhancement: %{suggestions: []},
      pattern_detection: %{
        patterns_found: detect_patterns(content),
        antipatterns: detect_antipatterns(content)
      }
    }
  end

  defp validate_syntax(_content, :elixir), do: true
  defp validate_syntax(_content, _language), do: true

  defp calculate_complexity(content) do
    # Simple complexity based on conditional statements
    conditions = Regex.scan(~r/(if|case|cond|when)/, content)
    max(length(conditions), 1)
  end

  defp calculate_nesting_depth(content) do
    # Simple nesting calculation
    if String.contains?(content, "if") do
      # Count nested structures
      nested_count =
        content
        |> String.split("\n")
        |> Enum.map(&(String.length(&1) - String.length(String.trim_leading(&1))))
        |> Enum.max(fn -> 0 end)

      # Approximate nesting depth
      div(nested_count, 2) + 1
    else
      1
    end
  end

  defp detect_vulnerabilities(content) do
    vulnerabilities = []

    # Check for hardcoded credentials
    vulnerabilities = if Regex.match?(~r/password.*=.*["'][^"']+["']/, content) do
      [:hardcoded_credentials | vulnerabilities]
    else
      vulnerabilities
    end

    # Check for weak authentication
    vulnerabilities = if String.contains?(content, ~s(== "admin")) do
      [:weak_authentication | vulnerabilities]
    else
      vulnerabilities
    end

    vulnerabilities
  end

  defp has_security_issues?(content) do
    length(detect_vulnerabilities(content)) > 0
  end

  defp detect_patterns(content) do
    patterns = []

    patterns = if Regex.match?(~r/def \w+.*do.*end/s, content) do
      [:function_definition | patterns]
    else
      patterns
    end

    patterns
  end

  defp detect_antipatterns(content) do
    antipatterns = []

    # Deep nesting antipattern
    antipatterns = if calculate_nesting_depth(content) > 3 do
      [:deep_nesting | antipatterns]
    else
      antipatterns
    end

    # Long function antipattern
    line_count = String.split(content, "\n") |> length()

    antipatterns = if line_count > 20 do
      [:long_function | antipatterns]
    else
      antipatterns
    end

    antipatterns
  end
end
