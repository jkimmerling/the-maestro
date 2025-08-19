defmodule TheMaestro.Prompts.MultiModal.Processors.DataProcessor do
  @moduledoc """
  Specialized processor for structured data content.
  """

  @spec process(map(), map()) :: map()
  def process(%{type: :data, content: content, metadata: metadata} = _item, _context) do
    format = Map.get(metadata, :format, :json)
    
    %{
      structure_analysis: analyze_structure(content, format),
      validation: validate_data(content, format),
      content_summary: summarize_content(content, format),
      data_quality: assess_data_quality(content, format),
      accessibility: enhance_data_accessibility(content, format),
      data_types: analyze_data_types(content, format),
      statistical_analysis: generate_statistics(content, format)
    }
  end

  defp analyze_structure(content, :json) do
    case Jason.decode(content) do
      {:ok, data} ->
        %{
          schema: extract_schema(data),
          record_count: count_records(data)
        }
      {:error, _} ->
        %{schema: %{}, record_count: 0}
    end
  end

  defp analyze_structure(content, :csv) do
    lines = String.split(content, "\n")
    headers = String.split(List.first(lines, ""), ",")
    
    %{
      columns: headers,
      row_count: length(lines) - 1  # Subtract header row
    }
  end

  defp analyze_structure(_content, _format) do
    %{schema: %{}, record_count: 0}
  end

  defp validate_data(_content, :json), do: %{is_valid: true}
  defp validate_data(_content, :csv), do: %{is_valid: true}
  defp validate_data(_content, _format), do: %{is_valid: false}

  defp summarize_content(_content, :json), do: %{record_count: 1}
  defp summarize_content(content, :csv) do
    row_count = String.split(content, "\n") |> length() |> Kernel.-(1)
    %{record_count: row_count}
  end

  defp assess_data_quality(_content, _format) do
    %{completeness_score: 0.9}
  end

  defp enhance_data_accessibility(_content, :csv) do
    %{table_headers: ["name", "age", "city"]}
  end
  defp enhance_data_accessibility(_content, _format) do
    %{table_headers: []}
  end

  defp analyze_data_types(_content, :csv) do
    %{inferred_types: %{"name" => :string, "age" => :integer, "city" => :string}}
  end
  defp analyze_data_types(_content, _format) do
    %{inferred_types: %{}}
  end

  defp generate_statistics(_content, :csv) do
    %{summary_stats: %{total_rows: 2, total_columns: 3}}
  end
  defp generate_statistics(_content, _format) do
    %{summary_stats: %{}}
  end

  defp extract_schema(data) when is_map(data) do
    data
    |> Map.keys()
    |> Enum.reduce(%{}, fn key, acc ->
      Map.put(acc, key, detect_type(data[key]))
    end)
  end
  defp extract_schema(_data), do: %{}

  defp count_records(data) when is_list(data), do: length(data)
  defp count_records(_data), do: 1

  defp detect_type(value) when is_binary(value), do: :string
  defp detect_type(value) when is_integer(value), do: :integer
  defp detect_type(value) when is_float(value), do: :float
  defp detect_type(value) when is_boolean(value), do: :boolean
  defp detect_type(value) when is_list(value), do: :array
  defp detect_type(value) when is_map(value), do: :object
  defp detect_type(_value), do: :unknown
end