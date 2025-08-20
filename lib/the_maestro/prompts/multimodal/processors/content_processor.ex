defmodule TheMaestro.Prompts.MultiModal.Processors.ContentProcessor do
  @moduledoc """
  Main content processor that delegates to specialized processors based on content type.

  Handles processing of different content types including images, audio, video, documents,
  code, data, and other media formats. Each content type has a specialized processor
  that provides relevant analysis and enhancement capabilities.
  """

  alias TheMaestro.Prompts.MultiModal.Processors.{
    ImageProcessor,
    AudioProcessor,
    VideoProcessor,
    DocumentProcessor,
    CodeProcessor,
    DataProcessor,
    TextProcessor
  }

  alias TheMaestro.Prompts.MultiModal.Optimization.PerformanceOptimizer

  # Type definitions for content processing
  @type content_type ::
          :text | :image | :audio | :video | :document | :code | :data | :diagram | :web_content

  @type content_item :: %{
          type: content_type(),
          content: String.t() | binary(),
          metadata: map(),
          processed_content: map() | nil
        }

  @type processing_context :: %{
          optional(:performance_mode) => :optimized | :standard,
          optional(:processing_mode) => :parallel | :sequential,
          optional(:max_workers) => non_neg_integer()
        }

  @type processing_result ::
          %{
            processor_used: atom(),
            analysis: map()
          }
          | %{
              processor_used: atom(),
              analysis: map(),
              optimization_applied: [atom()],
              performance_metrics: map()
            }

  @type error_result :: %{
          status: :error,
          error: atom() | String.t(),
          error_details: map(),
          fallback_processing: map(),
          processor_used: atom()
        }

  @type batch_result :: %{
          results: [processing_result() | error_result()],
          parallel_processing: boolean(),
          processing_time_ms: non_neg_integer(),
          items_processed: non_neg_integer()
        }

  @doc """
  Processes content by delegating to the appropriate specialized processor.

  ## Parameters

  - `content` - Content item with type, content, and metadata
  - `context` - Processing context and configuration

  ## Returns

  Processed content result with analysis, enhancements, and metadata.
  """
  @spec process_content(content_item(), processing_context()) ::
          processing_result() | error_result()
  def process_content(%{type: type} = content, context) do
    result =
      case type do
        :text ->
          %{processor_used: :text_processor, analysis: TextProcessor.process(content, context)}

        :image ->
          %{processor_used: :image_processor, analysis: ImageProcessor.process(content, context)}

        :audio ->
          %{processor_used: :audio_processor, analysis: AudioProcessor.process(content, context)}

        :video ->
          %{processor_used: :video_processor, analysis: VideoProcessor.process(content, context)}

        :document ->
          %{
            processor_used: :document_processor,
            analysis: DocumentProcessor.process(content, context)
          }

        :code ->
          %{processor_used: :code_processor, analysis: CodeProcessor.process(content, context)}

        :data ->
          %{processor_used: :data_processor, analysis: DataProcessor.process(content, context)}

        :diagram ->
          %{processor_used: :image_processor, analysis: ImageProcessor.process(content, context)}

        :web_content ->
          %{processor_used: :text_processor, analysis: TextProcessor.process(content, context)}

        _ ->
          %{
            status: :error,
            error: :unsupported_content_type,
            processor_used: :none
          }
      end

    # Apply performance optimizations if requested
    case Map.get(context, :performance_mode) do
      :optimized ->
        apply_performance_optimizations(result, [content], context)

      _ ->
        result
    end
  rescue
    error ->
      %{
        status: :error,
        error_details: %{
          type: :content_malformed,
          message: Exception.message(error)
        },
        fallback_processing: %{attempted: true},
        processor_used: :error_handler
      }
  end

  @doc """
  Processes multiple content items in batch with optional parallel processing.
  """
  @spec process_batch([content_item()], processing_context()) :: batch_result()
  def process_batch(content_items, context) do
    start_time = System.monotonic_time(:millisecond)
    processing_mode = Map.get(context, :processing_mode, :sequential)

    results =
      case processing_mode do
        :parallel -> process_parallel(content_items, context)
        :sequential -> process_sequential(content_items, context)
      end

    end_time = System.monotonic_time(:millisecond)

    %{
      results: results,
      parallel_processing: processing_mode == :parallel,
      processing_time_ms: end_time - start_time,
      items_processed: length(content_items)
    }
  end

  # Private helper functions

  @spec process_sequential([content_item()], processing_context()) :: [
          processing_result() | error_result()
        ]
  defp process_sequential(content_items, context) do
    Enum.map(content_items, &process_content(&1, context))
  end

  @spec process_parallel([content_item()], processing_context()) :: [
          processing_result() | error_result()
        ]
  defp process_parallel(content_items, context) do
    max_workers = Map.get(context, :max_workers, System.schedulers_online())

    content_items
    |> Task.async_stream(
      &process_content(&1, context),
      max_concurrency: max_workers,
      timeout: 30_000
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, reason} -> %{status: :error, error: :processing_timeout, reason: reason}
    end)
  end

  @spec apply_performance_optimizations(
          processing_result(),
          [content_item()],
          processing_context()
        ) :: processing_result()
  defp apply_performance_optimizations(result, content, context) do
    # Apply performance optimizations using the PerformanceOptimizer
    optimization_result = PerformanceOptimizer.optimize_processing_pipeline(content, context)

    # Merge the optimization results with the processor result
    result
    |> Map.put(:optimization_applied, optimization_result.optimizations_applied)
    |> Map.put(:performance_metrics, optimization_result.performance_metrics)
  end
end
