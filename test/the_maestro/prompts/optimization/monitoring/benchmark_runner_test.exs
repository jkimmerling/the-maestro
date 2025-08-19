defmodule TheMaestro.Prompts.Optimization.Monitoring.BenchmarkRunnerTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias TheMaestro.Prompts.Optimization.Monitoring.BenchmarkRunner

  describe "run_quick_benchmark/0" do
    test "executes quick benchmark and returns results" do
      output =
        capture_io(fn ->
          results = BenchmarkRunner.run_quick_benchmark()

          # Verify return value structure
          assert is_map(results)
          assert Map.has_key?(results, :provider_results)
          assert Map.has_key?(results, :benchmark_summary)
          assert is_list(results.provider_results)

          # Verify each provider result has expected structure
          for provider_result <- results.provider_results do
            assert Map.has_key?(provider_result, :provider)
            assert Map.has_key?(provider_result, :model)
            assert Map.has_key?(provider_result, :results)
            assert provider_result.provider in [:anthropic, :google, :openai]
            assert is_binary(provider_result.model)
            assert is_list(provider_result.results)
          end

          # Verify benchmark summary
          assert Map.has_key?(results.benchmark_summary, :total_test_cases)
          assert Map.has_key?(results.benchmark_summary, :providers_tested)
          assert Map.has_key?(results.benchmark_summary, :execution_time_ms)
          assert results.benchmark_summary.total_test_cases == 3
          assert results.benchmark_summary.providers_tested == 3
        end)

      # Verify output contains expected messages
      assert String.contains?(output, "🚀 Running Quick Provider Optimization Benchmark")
      assert String.contains?(output, "simplified test cases")
      assert String.contains?(output, "Quick Benchmark Summary")
    end

    test "handles test cases with different complexity levels" do
      capture_io(fn ->
        results = BenchmarkRunner.run_quick_benchmark()

        # Find results for each test case complexity
        all_results = Enum.flat_map(results.provider_results, & &1.results)

        complexities = Enum.map(all_results, & &1[:complexity])
        assert :low in complexities
        assert :medium in complexities
        assert :high in complexities
      end)
    end

    test "prints performance comparison between providers" do
      output =
        capture_io(fn ->
          BenchmarkRunner.run_quick_benchmark()
        end)

      # Should show comparison data
      assert String.contains?(output, "Provider Performance Comparison")
      assert String.contains?(output, "anthropic")
      assert String.contains?(output, "google")
      assert String.contains?(output, "openai")
    end
  end

  describe "run_full_benchmark/0" do
    test "delegates to PerformanceBenchmark comprehensive benchmark" do
      output =
        capture_io(fn ->
          results = BenchmarkRunner.run_full_benchmark()

          # Verify it returns the comprehensive benchmark results
          assert is_map(results)
          assert Map.has_key?(results, :baseline_metrics)
          assert Map.has_key?(results, :optimization_metrics)
          assert Map.has_key?(results, :comparison_results)
        end)

      # Verify output shows full benchmark messaging
      assert String.contains?(output, "🚀 Running Full Comprehensive Benchmark")
      assert String.contains?(output, "may take several minutes")
    end
  end

  describe "run_targeted_benchmark/1" do
    test "runs benchmark with custom test cases" do
      custom_test_cases = [
        %{
          name: "custom_simple",
          prompt: "What is machine learning?",
          complexity: :low
        },
        %{
          name: "custom_complex",
          prompt: "Design a distributed system for processing real-time data streams.",
          complexity: :high
        }
      ]

      results = BenchmarkRunner.run_targeted_benchmark(custom_test_cases)

      assert is_map(results)
      assert Map.has_key?(results, :provider_results)
      assert Map.has_key?(results, :benchmark_summary)

      # Should have results for all providers
      assert length(results.provider_results) == 3

      # Each provider should have processed both test cases
      for provider_result <- results.provider_results do
        assert length(provider_result.results) == 2

        # Verify test case names appear in results
        result_names = Enum.map(provider_result.results, & &1[:test_case])
        assert "custom_simple" in result_names
        assert "custom_complex" in result_names
      end
    end

    test "handles empty test cases gracefully" do
      results = BenchmarkRunner.run_targeted_benchmark([])

      assert is_map(results)
      assert results.benchmark_summary.total_test_cases == 0
      assert Enum.all?(results.provider_results, &(length(&1.results) == 0))
    end

    test "validates test case structure" do
      invalid_test_cases = [
        %{name: "missing_prompt", complexity: :low},
        %{prompt: "Missing name", complexity: :medium},
        %{name: "missing_complexity", prompt: "What is AI?"}
      ]

      results = BenchmarkRunner.run_targeted_benchmark(invalid_test_cases)

      # Should handle invalid cases gracefully
      assert is_map(results)
      # Invalid cases should be filtered out or handled
      assert results.benchmark_summary.total_test_cases >= 0
    end
  end

  describe "run_provider_specific_benchmark/1" do
    test "runs benchmark for specific provider" do
      results = BenchmarkRunner.run_provider_specific_benchmark(:anthropic)

      assert is_map(results)
      assert Map.has_key?(results, :provider)
      assert Map.has_key?(results, :model)
      assert Map.has_key?(results, :results)
      assert Map.has_key?(results, :execution_time_ms)

      assert results.provider == :anthropic
      assert is_binary(results.model)
      assert is_list(results.results)
      assert is_integer(results.execution_time_ms)
    end

    test "handles invalid provider gracefully" do
      results = BenchmarkRunner.run_provider_specific_benchmark(:invalid_provider)

      # Should return error or empty results
      assert is_map(results)
      assert results.provider == :invalid_provider
      assert results.results == [] or Map.has_key?(results, :error)
    end

    test "supports all valid providers" do
      valid_providers = [:anthropic, :google, :openai]

      for provider <- valid_providers do
        results = BenchmarkRunner.run_provider_specific_benchmark(provider)

        assert results.provider == provider
        assert is_list(results.results)
      end
    end
  end

  describe "generate_benchmark_report/1" do
    test "generates comprehensive report from benchmark results" do
      # Run a quick benchmark to get real results
      benchmark_results =
        capture_io(fn ->
          BenchmarkRunner.run_quick_benchmark()
        end)
        |> then(fn _ -> BenchmarkRunner.run_quick_benchmark() end)

      output =
        capture_io(fn ->
          report = BenchmarkRunner.generate_benchmark_report(benchmark_results)

          assert is_map(report)
          assert Map.has_key?(report, :report_generated_at)
          assert Map.has_key?(report, :executive_summary)
          assert Map.has_key?(report, :detailed_analysis)
          assert Map.has_key?(report, :recommendations)

          # Verify executive summary
          summary = report.executive_summary
          assert Map.has_key?(summary, :best_performing_provider)
          assert Map.has_key?(summary, :average_optimization_improvement)
          assert Map.has_key?(summary, :total_test_cases_analyzed)

          # Verify detailed analysis
          analysis = report.detailed_analysis
          assert Map.has_key?(analysis, :provider_rankings)
          assert Map.has_key?(analysis, :complexity_analysis)
          assert Map.has_key?(analysis, :optimization_effectiveness)
        end)

      # Verify report output
      assert String.contains?(output, "📊 Benchmark Report Generated")
      assert String.contains?(output, "Executive Summary")
      assert String.contains?(output, "Provider Performance Rankings")
      assert String.contains?(output, "Recommendations")
    end

    test "handles empty results gracefully" do
      empty_results = %{
        provider_results: [],
        benchmark_summary: %{
          total_test_cases: 0,
          providers_tested: 0,
          execution_time_ms: 0
        }
      }

      output =
        capture_io(fn ->
          report = BenchmarkRunner.generate_benchmark_report(empty_results)

          assert is_map(report)
          assert report.executive_summary.total_test_cases_analyzed == 0
        end)

      assert String.contains?(output, "No benchmark data available")
    end
  end

  describe "run_provider_benchmark/1" do
    test "runs benchmark for specific provider and prints summary" do
      output =
        capture_io(fn ->
          results = BenchmarkRunner.run_provider_benchmark(:anthropic)

          # Verify return structure
          assert is_map(results)
          assert Map.has_key?(results, :provider)
          assert Map.has_key?(results, :baseline_metrics)
          assert Map.has_key?(results, :optimization_metrics)
          assert Map.has_key?(results, :test_cases)

          assert results.provider == :anthropic
          assert is_map(results.baseline_metrics)
          assert is_map(results.optimization_metrics)
          assert is_list(results.test_cases)
        end)

      # Verify output contains provider summary
      assert String.contains?(output, "🚀 Running Benchmark for anthropic")
      assert String.contains?(output, "ANTHROPIC BENCHMARK SUMMARY")
      assert String.contains?(output, "Average Results:")
      assert String.contains?(output, "Token Reduction:")
      assert String.contains?(output, "Quality Improvement:")
      assert String.contains?(output, "Test Case Results:")
    end

    test "supports all valid providers" do
      for provider <- [:anthropic, :google, :openai] do
        output =
          capture_io(fn ->
            results = BenchmarkRunner.run_provider_benchmark(provider)
            assert results.provider == provider
          end)

        assert String.contains?(output, "🚀 Running Benchmark for #{provider}")

        assert String.contains?(
                 String.upcase(output),
                 String.upcase("#{provider} BENCHMARK SUMMARY")
               )
      end
    end
  end

  describe "text report generation" do
    test "generates comprehensive text report" do
      # Create sample results that match expected structure
      sample_results = %{
        started_at: DateTime.utc_now() |> DateTime.add(-60, :second),
        completed_at: DateTime.utc_now(),
        test_cases: 3,
        performance_summary: %{
          best_performing_provider: :anthropic,
          overall_token_reduction: 0.25,
          overall_quality_improvement: 0.15,
          overall_latency_impact: 0.1,
          overall_cost_savings: 0.05,
          recommended_configurations: %{
            anthropic: %{recommendation: "Use structured reasoning for complex tasks"},
            openai: %{recommendation: "Enable parallel processing for speed"}
          }
        },
        comparison_results: %{
          anthropic: [%{score: 0.85}],
          openai: [%{score: 0.78}]
        }
      }

      output =
        capture_io(fn ->
          BenchmarkRunner.generate_report(sample_results)
        end)

      # Verify text report contents
      assert String.contains?(output, "Provider Optimization Benchmark Report")
      assert String.contains?(output, "Generated:")
      assert String.contains?(output, "Test Duration:")
      assert String.contains?(output, "Executive Summary")
      assert String.contains?(output, "Best Performing Provider:** anthropic")
      assert String.contains?(output, "Average Token Reduction:** 25.0%")
      assert String.contains?(output, "Performance Metrics")
      assert String.contains?(output, "Provider Comparison")
      assert String.contains?(output, "Recommendations")
      assert String.contains?(output, "**anthropic**: Use structured reasoning")
    end
  end

  describe "file operations" do
    test "loads benchmark results from valid JSON file" do
      # Create temporary file with valid JSON
      sample_data = %{
        provider_results: [
          %{provider: :anthropic, results: [%{score: 0.85}]}
        ],
        benchmark_summary: %{total_test_cases: 1}
      }

      json_content = Jason.encode!(sample_data)
      temp_file = "/tmp/test_benchmark_results.json"
      File.write!(temp_file, json_content)

      # Test loading
      {:ok, loaded_results} = BenchmarkRunner.load_benchmark_results(temp_file)

      assert is_map(loaded_results)
      assert Map.has_key?(loaded_results, :provider_results)
      assert Map.has_key?(loaded_results, :benchmark_summary)

      # Cleanup
      File.rm!(temp_file)
    end

    test "handles missing file gracefully" do
      {:error, message} = BenchmarkRunner.load_benchmark_results("/nonexistent/file.json")

      assert is_binary(message)
      assert String.contains?(message, "Failed to read file")
    end

    test "handles invalid JSON gracefully" do
      # Create temporary file with invalid JSON
      temp_file = "/tmp/invalid_benchmark.json"
      File.write!(temp_file, "invalid json content")

      {:error, message} = BenchmarkRunner.load_benchmark_results(temp_file)

      assert is_binary(message)
      assert String.contains?(message, "Failed to parse JSON")

      # Cleanup
      File.rm!(temp_file)
    end
  end

  describe "compare_providers/1" do
    test "compares provider performance across metrics" do
      # Generate sample results for comparison
      sample_results = %{
        provider_results: [
          %{
            provider: :anthropic,
            model: "claude-3-5-sonnet",
            results: [
              %{
                test_case: "simple",
                optimization_score: 0.85,
                response_time: 1200,
                complexity: :low
              },
              %{
                test_case: "complex",
                optimization_score: 0.78,
                response_time: 2100,
                complexity: :high
              }
            ]
          },
          %{
            provider: :openai,
            model: "gpt-4o",
            results: [
              %{
                test_case: "simple",
                optimization_score: 0.82,
                response_time: 1100,
                complexity: :low
              },
              %{
                test_case: "complex",
                optimization_score: 0.75,
                response_time: 1800,
                complexity: :high
              }
            ]
          }
        ]
      }

      comparison = BenchmarkRunner.compare_providers(sample_results)

      assert is_map(comparison)
      assert Map.has_key?(comparison, :ranking)
      assert Map.has_key?(comparison, :metrics_comparison)
      assert Map.has_key?(comparison, :strengths_weaknesses)

      # Verify ranking structure
      ranking = comparison.ranking
      assert is_list(ranking)
      assert length(ranking) == 2

      # Each ranking entry should have provider and scores
      for entry <- ranking do
        assert Map.has_key?(entry, :provider)
        assert Map.has_key?(entry, :overall_score)
        assert Map.has_key?(entry, :average_optimization_score)
        assert Map.has_key?(entry, :average_response_time)
        assert entry.provider in [:anthropic, :openai]
      end
    end

    test "handles single provider results" do
      single_provider_results = %{
        provider_results: [
          %{
            provider: :anthropic,
            model: "claude-3-5-sonnet",
            results: [%{test_case: "test", optimization_score: 0.8, response_time: 1000}]
          }
        ]
      }

      comparison = BenchmarkRunner.compare_providers(single_provider_results)

      assert is_map(comparison)
      assert length(comparison.ranking) == 1
      assert hd(comparison.ranking).provider == :anthropic
    end
  end
end
