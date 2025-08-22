defmodule TheMaestro.Prompts.EngineeringTools.TestingFrameworkTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.EngineeringTools.TestingFramework

  alias TheMaestro.Prompts.EngineeringTools.TestingFramework.{
    PromptTestSuite,
    TestCase,
    TestExecutionResults,
    TestSuiteReport,
    ValidationCriteria
  }

  describe "create_prompt_test_suite/2" do
    test "creates comprehensive test suite for a prompt" do
      prompt = "You are a {{role}} assistant. Help the user with {{task}}."

      test_configuration = %{
        test_types: [:functional, :performance, :quality, :regression],
        providers: [:openai, :anthropic, :google],
        edge_cases: true,
        cross_provider: true,
        performance_benchmarks: %{
          max_response_time: 5000,
          min_quality_score: 0.8,
          max_token_usage: 1000
        }
      }

      test_suite = TestingFramework.create_prompt_test_suite(prompt, test_configuration)

      assert %PromptTestSuite{} = test_suite
      assert test_suite.prompt_under_test == prompt
      assert is_list(test_suite.test_cases)
      assert length(test_suite.test_cases) > 0
      assert Map.has_key?(test_suite.validation_criteria, :functional)
      assert Map.has_key?(test_suite.validation_criteria, :performance)
      assert Map.has_key?(test_suite.validation_criteria, :quality)
      assert is_list(test_suite.regression_tests)
      assert is_list(test_suite.cross_provider_tests)
      assert is_list(test_suite.edge_case_tests)
      assert is_list(test_suite.user_acceptance_tests)
    end

    test "generates test cases based on prompt parameters" do
      prompt = """
      You are a {{role | enum: [teacher, mentor, expert]}} helping with {{subject | required}}.
      Difficulty level: {{difficulty | enum: [beginner, intermediate, advanced] | default: beginner}}
      Provide a {{format | enum: [brief, detailed, comprehensive]}} explanation.
      """

      test_configuration = %{
        test_types: [:functional, :edge_cases],
        parameter_testing: true,
        edge_cases: true
      }

      test_suite = TestingFramework.create_prompt_test_suite(prompt, test_configuration)

      # Should generate test cases for all parameter combinations
      parameter_test_cases =
        Enum.filter(test_suite.test_cases, fn tc ->
          tc.category == :parameter_variation
        end)

      assert length(parameter_test_cases) > 0

      # Should test different role values
      role_tests =
        Enum.filter(parameter_test_cases, fn tc ->
          Map.has_key?(tc.parameters, "role")
        end)

      # teacher, mentor, expert
      assert length(role_tests) >= 3
    end

    test "establishes performance benchmarks" do
      prompt = "Analyze the provided code and suggest improvements."

      test_configuration = %{
        test_types: [:performance],
        performance_benchmarks: %{
          max_response_time: 3000,
          min_quality_score: 0.85,
          max_token_usage: 800,
          min_accuracy: 0.9
        }
      }

      test_suite = TestingFramework.create_prompt_test_suite(prompt, test_configuration)

      benchmarks = test_suite.performance_benchmarks

      assert benchmarks.max_response_time == 3000
      assert benchmarks.min_quality_score == 0.85
      assert benchmarks.max_token_usage == 800
      assert benchmarks.min_accuracy == 0.9
    end

    test "creates regression test set from historical data" do
      prompt = "Summarize the following text: {{text | required}}"

      test_configuration = %{
        test_types: [:regression],
        historical_data: [
          %{input: %{"text" => "Sample text 1"}, expected_quality: 0.9},
          %{input: %{"text" => "Sample text 2"}, expected_quality: 0.85}
        ]
      }

      test_suite = TestingFramework.create_prompt_test_suite(prompt, test_configuration)

      regression_tests = test_suite.regression_tests

      assert length(regression_tests) == 2

      assert Enum.all?(regression_tests, fn test ->
               Map.has_key?(test, :input) && Map.has_key?(test, :expected_quality)
             end)
    end
  end

  describe "execute_prompt_test_suite/2" do
    setup do
      prompt = "You are a helpful assistant. Answer: {{question | required}}"

      test_configuration = %{
        test_types: [:functional, :performance],
        providers: [:test_provider],
        performance_benchmarks: %{
          max_response_time: 1000,
          min_quality_score: 0.7
        }
      }

      test_suite = TestingFramework.create_prompt_test_suite(prompt, test_configuration)
      {:ok, test_suite: test_suite}
    end

    test "executes all test types in suite", %{test_suite: test_suite} do
      execution_options = %{
        providers: [:test_provider],
        timeout: 5000,
        parallel: false
      }

      report = TestingFramework.execute_prompt_test_suite(test_suite, execution_options)

      assert %TestSuiteReport{} = report
      assert Map.has_key?(report.detailed_results, :functional_tests)
      assert Map.has_key?(report.detailed_results, :performance_tests)
      assert Map.has_key?(report.detailed_results, :quality_tests)
      assert Map.has_key?(report.detailed_results, :regression_tests)
      assert Map.has_key?(report.detailed_results, :cross_provider_tests)
      assert Map.has_key?(report.detailed_results, :user_acceptance_tests)
    end

    test "measures functional test results", %{test_suite: test_suite} do
      execution_options = %{providers: [:test_provider]}

      report = TestingFramework.execute_prompt_test_suite(test_suite, execution_options)

      functional_results = report.detailed_results.functional_tests

      assert Map.has_key?(functional_results, :success_rate)
      assert Map.has_key?(functional_results, :failed_tests)
      assert Map.has_key?(functional_results, :execution_time)
      assert is_number(functional_results.success_rate)
      assert functional_results.success_rate >= 0 && functional_results.success_rate <= 1
    end

    test "measures performance against benchmarks", %{test_suite: test_suite} do
      execution_options = %{providers: [:test_provider]}

      report = TestingFramework.execute_prompt_test_suite(test_suite, execution_options)

      performance_results = report.detailed_results.performance_tests

      assert Map.has_key?(performance_results, :average_response_time)
      assert Map.has_key?(performance_results, :benchmark_compliance)
      assert Map.has_key?(performance_results, :performance_violations)

      benchmark_compliance = performance_results.benchmark_compliance
      assert Map.has_key?(benchmark_compliance, :response_time_ok)
      assert Map.has_key?(benchmark_compliance, :token_usage_ok)
    end

    test "generates execution summary", %{test_suite: test_suite} do
      execution_options = %{providers: [:test_provider]}

      report = TestingFramework.execute_prompt_test_suite(test_suite, execution_options)

      summary = report.execution_summary

      assert Map.has_key?(summary, :total_tests)
      assert Map.has_key?(summary, :passed_tests)
      assert Map.has_key?(summary, :failed_tests)
      assert Map.has_key?(summary, :execution_time)
      assert Map.has_key?(summary, :overall_success_rate)

      assert summary.total_tests == summary.passed_tests + summary.failed_tests
      assert is_number(summary.overall_success_rate)
    end

    test "provides improvement recommendations", %{test_suite: test_suite} do
      execution_options = %{providers: [:test_provider]}

      report = TestingFramework.execute_prompt_test_suite(test_suite, execution_options)

      recommendations = report.recommendations

      assert is_list(recommendations)

      assert Enum.all?(recommendations, fn rec ->
               Map.has_key?(rec, :type) && Map.has_key?(rec, :description) &&
                 Map.has_key?(rec, :priority)
             end)
    end

    test "performs regression analysis", %{test_suite: test_suite} do
      execution_options = %{providers: [:test_provider], compare_to_baseline: true}

      report = TestingFramework.execute_prompt_test_suite(test_suite, execution_options)

      regression_analysis = report.regression_analysis

      assert Map.has_key?(regression_analysis, :performance_changes)
      assert Map.has_key?(regression_analysis, :quality_changes)
      assert Map.has_key?(regression_analysis, :regression_detected)
      assert is_boolean(regression_analysis.regression_detected)
    end
  end

  describe "automated test case generation" do
    test "generates happy path tests" do
      prompt = "Translate {{text | required}} from {{source_lang}} to {{target_lang}}."
      domain_context = %{type: :translation, complexity: :medium}

      test_cases = TestingFramework.generate_comprehensive_test_cases(prompt, domain_context)

      happy_path_tests = Enum.filter(test_cases, fn tc -> tc.category == :happy_path end)

      assert length(happy_path_tests) > 0

      assert Enum.all?(happy_path_tests, fn test ->
               Map.has_key?(test.parameters, "text") &&
                 Map.has_key?(test.parameters, "source_lang") &&
                 Map.has_key?(test.parameters, "target_lang")
             end)
    end

    test "generates edge case tests" do
      prompt = "Process the input: {{input | required}}"
      domain_context = %{type: :text_processing}

      test_cases = TestingFramework.generate_comprehensive_test_cases(prompt, domain_context)

      edge_case_tests = Enum.filter(test_cases, fn tc -> tc.category == :edge_case end)

      assert length(edge_case_tests) > 0

      # Should include empty input test
      empty_input_test =
        Enum.find(edge_case_tests, fn test ->
          test.name == "Empty Input Test"
        end)

      assert empty_input_test != nil
      assert Enum.member?(empty_input_test.input_variations, "")

      # Should include maximum length test
      max_length_test =
        Enum.find(edge_case_tests, fn test ->
          String.contains?(test.name, "Maximum")
        end)

      assert max_length_test != nil
    end

    test "generates error condition tests" do
      prompt = "Calculate {{operation}} of {{numbers | required}}"
      domain_context = %{type: :calculation}

      test_cases = TestingFramework.generate_comprehensive_test_cases(prompt, domain_context)

      error_tests = Enum.filter(test_cases, fn tc -> tc.category == :error_condition end)

      assert length(error_tests) > 0

      assert Enum.any?(error_tests, fn test ->
               test.expected_behavior == :graceful_error_handling
             end)
    end

    test "generates boundary tests" do
      prompt =
        "Rate the quality from {{min_score | default: 1}} to {{max_score | default: 10}}: {{content}}"

      domain_context = %{type: :rating}

      test_cases = TestingFramework.generate_comprehensive_test_cases(prompt, domain_context)

      boundary_tests = Enum.filter(test_cases, fn tc -> tc.category == :boundary end)

      assert length(boundary_tests) > 0

      assert Enum.any?(boundary_tests, fn test ->
               String.contains?(test.name, "Boundary")
             end)
    end

    test "generates performance tests" do
      prompt = "Analyze the large dataset: {{data | required}}"
      domain_context = %{type: :data_analysis, expected_complexity: :high}

      test_cases = TestingFramework.generate_comprehensive_test_cases(prompt, domain_context)

      performance_tests = Enum.filter(test_cases, fn tc -> tc.category == :performance end)

      assert length(performance_tests) > 0

      assert Enum.all?(performance_tests, fn test ->
               Map.has_key?(test, :performance_expectations)
             end)
    end

    test "prioritizes test cases by importance" do
      prompt = "Help with {{task | required}}"
      domain_context = %{type: :general_help}

      test_cases = TestingFramework.generate_comprehensive_test_cases(prompt, domain_context)

      # Should be sorted by priority
      priorities = Enum.map(test_cases, & &1.priority)
      sorted_priorities = Enum.sort(priorities, :desc)
      assert priorities == sorted_priorities

      # Critical tests should come first
      first_test = List.first(test_cases)
      assert first_test.priority >= 0.8
    end

    test "optimizes test coverage" do
      prompt = "Process {{type}} with {{method | enum: [fast, thorough]}} approach"
      domain_context = %{type: :processing}

      test_cases = TestingFramework.generate_comprehensive_test_cases(prompt, domain_context)

      # Should cover all parameter combinations efficiently
      method_values =
        test_cases
        |> Enum.map(fn tc -> Map.get(tc.parameters, "method") end)
        |> Enum.uniq()
        |> Enum.reject(&is_nil/1)

      assert Enum.member?(method_values, "fast")
      assert Enum.member?(method_values, "thorough")

      # Should not have redundant test cases
      unique_test_signatures =
        test_cases
        |> Enum.map(fn tc -> {tc.category, tc.parameters} end)
        |> Enum.uniq()

      assert length(unique_test_signatures) == length(test_cases)
    end
  end

  describe "validation criteria" do
    test "defines functional validation criteria" do
      criteria = ValidationCriteria.functional_criteria()

      assert Map.has_key?(criteria, :response_relevance)
      assert Map.has_key?(criteria, :instruction_following)
      assert Map.has_key?(criteria, :parameter_usage)
      assert Map.has_key?(criteria, :output_completeness)
    end

    test "defines performance validation criteria" do
      criteria = ValidationCriteria.performance_criteria()

      assert Map.has_key?(criteria, :response_time)
      assert Map.has_key?(criteria, :token_efficiency)
      assert Map.has_key?(criteria, :memory_usage)
      assert Map.has_key?(criteria, :throughput)
    end

    test "defines quality validation criteria" do
      criteria = ValidationCriteria.quality_criteria()

      assert Map.has_key?(criteria, :accuracy)
      assert Map.has_key?(criteria, :coherence)
      assert Map.has_key?(criteria, :completeness)
      assert Map.has_key?(criteria, :creativity)
      assert Map.has_key?(criteria, :factual_correctness)
    end
  end
end
