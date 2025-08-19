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

  @doc """
  Processes content by delegating to the appropriate specialized processor.
  
  ## Parameters
  
  - `content` - Content item with type, content, and metadata
  - `context` - Processing context and configuration
  
  ## Returns
  
  Processed content result with analysis, enhancements, and metadata.
  """
  @spec process_content(map(), map()) :: map()
  def process_content(%{type: type} = content, context) do
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
        %{processor_used: :document_processor, analysis: DocumentProcessor.process(content, context)}
      
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
  @spec process_batch(list(map()), map()) :: map()
  def process_batch(content_items, context) do
    start_time = System.monotonic_time(:millisecond)
    processing_mode = Map.get(context, :processing_mode, :sequential)
    
    results = case processing_mode do
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

  defp process_sequential(content_items, context) do
    Enum.map(content_items, &process_content(&1, context))
  end

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
end