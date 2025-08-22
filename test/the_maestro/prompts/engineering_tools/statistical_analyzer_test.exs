defmodule TheMaestro.Prompts.EngineeringTools.StatisticalAnalyzerTest do
  use ExUnit.Case, async: true
  
  alias TheMaestro.Prompts.EngineeringTools.StatisticalAnalyzer

  describe "descriptive_analysis/2" do
    test "calculates basic statistics for numeric data" do
      data = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
      result = StatisticalAnalyzer.descriptive_analysis(data)
      
      assert result.count == 10
      assert result.mean == 5.5
      assert result.median == 5.5
      assert is_number(result.standard_deviation)
      assert is_number(result.variance)
    end

    test "handles empty data" do
      result = StatisticalAnalyzer.descriptive_analysis([])
      assert result.error == "No data provided for analysis"
    end
  end

  describe "hypothesis_test/3" do
    test "performs t-test between two groups" do
      group1 = [1, 2, 3, 4, 5]
      group2 = [6, 7, 8, 9, 10]
      
      result = StatisticalAnalyzer.hypothesis_test(group1, group2, test_type: :t_test, alpha: 0.05)
      
      assert result.test_type == :t_test
      assert is_number(result.statistic)
      assert is_number(result.p_value)
      assert is_boolean(result.significant)
      assert is_number(result.effect_size)
      assert result.mean_difference == -5.0  # Mean of group1 (3) - mean of group2 (8)
    end

    test "handles insufficient data" do
      group1 = [1]
      group2 = [2]
      
      result = StatisticalAnalyzer.hypothesis_test(group1, group2, test_type: :t_test)
      assert Map.has_key?(result, :error)
    end
  end

  describe "confidence_intervals/2" do
    test "calculates confidence intervals for data" do
      data = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
      
      result = StatisticalAnalyzer.confidence_intervals(data, 0.95)
      
      assert is_map(result)
      assert Map.has_key?(result, :mean)
      assert Map.has_key?(result, :margin_of_error)
      assert Map.has_key?(result, :lower_bound)
      assert Map.has_key?(result, :upper_bound)
    end

    test "handles different confidence levels" do
      data = [1, 2, 3, 4, 5]
      
      result_95 = StatisticalAnalyzer.confidence_intervals(data, 0.95)
      result_99 = StatisticalAnalyzer.confidence_intervals(data, 0.99)
      
      # 99% CI should have larger margin of error than 95% CI
      assert result_99.margin_of_error > result_95.margin_of_error
    end
  end

  describe "comparative_analysis/2" do
    test "compares multiple groups" do
      groups = [
        %{name: "Group A", data: [1, 2, 3, 4, 5]},
        %{name: "Group B", data: [6, 7, 8, 9, 10]},
        %{name: "Group C", data: [2, 4, 6, 8, 10]}
      ]
      
      result = StatisticalAnalyzer.comparative_analysis(groups)
      
      assert result.groups_analyzed == 3
      assert Map.has_key?(result, :pairwise_comparisons)
      assert Map.has_key?(result, :anova_results)
      assert Map.has_key?(result, :effect_sizes)
    end

    test "requires at least 2 groups" do
      groups = [%{name: "Group A", data: [1, 2, 3]}]
      
      result = StatisticalAnalyzer.comparative_analysis(groups)
      assert result.error == "At least 2 groups required for comparative analysis"
    end
  end

  describe "generate_statistical_report/2" do
    test "generates report from analysis data" do
      analysis_data = %{
        mean: 5.5,
        variance: 10.0,
        test_results: [%{test: :t_test, p_value: 0.03, significant: true}]
      }
      
      {:ok, report} = StatisticalAnalyzer.generate_statistical_report(analysis_data)
      
      assert is_binary(report)
      assert String.contains?(report, "Statistical Analysis Report")
    end
  end
end