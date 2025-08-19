defmodule TheMaestro.Prompts.MultiModal.Optimization.PerformanceOptimizerTest do
  use ExUnit.Case, async: true

  alias TheMaestro.Prompts.MultiModal.Optimization.PerformanceOptimizer

  describe "optimize_processing_pipeline/2" do
    test "enables lazy loading for large content items" do
      large_content = [
        %{
          type: :video,
          content: "large_video_data",
          metadata: %{size_mb: 500, duration: 1800}  # 30-minute, 500MB video
        },
        %{
          type: :image,
          content: "high_res_image",
          metadata: %{size_mb: 25, width: 8000, height: 6000}
        },
        %{
          type: :text,
          content: "Short text content"
        }
      ]

      context = %{performance_constraints: %{max_memory_mb: 100, max_processing_time_ms: 10000}}

      result = PerformanceOptimizer.optimize_processing_pipeline(large_content, context)

      lazy_loading = result.optimizations_applied.lazy_loading
      assert lazy_loading.enabled == true
      assert lazy_loading.deferred_items |> length() == 2  # Video and large image
      assert lazy_loading.immediate_items |> length() == 1  # Text only

      video_opt = lazy_loading.deferred_items |> Enum.find(&(&1.type == :video))
      assert video_opt.loading_strategy == :on_demand
      assert video_opt.preview_generated == true
      assert video_opt.memory_savings_mb > 400
    end

    test "implements intelligent caching for repeated content types" do
      repeated_content = [
        %{type: :image, content: "screenshot_1", metadata: %{context: :ui_screenshot}},
        %{type: :image, content: "screenshot_2", metadata: %{context: :ui_screenshot}},
        %{type: :image, content: "screenshot_3", metadata: %{context: :ui_screenshot}},
        %{type: :code, content: "function_1", metadata: %{language: :elixir}},
        %{type: :code, content: "function_2", metadata: %{language: :elixir}}
      ]

      context = %{enable_caching: true, cache_strategy: :intelligent}

      result = PerformanceOptimizer.optimize_processing_pipeline(repeated_content, context)

      caching = result.optimizations_applied.caching
      assert caching.enabled == true
      assert caching.cached_processors |> Enum.member?(:ui_screenshot_analyzer)
      assert caching.cached_processors |> Enum.member?(:elixir_code_analyzer)
      assert caching.cache_hit_ratio >= 0.6  # 60% of items benefit from caching
      assert caching.processing_time_saved_ms > 1000
    end

    test "applies parallel processing for independent content items" do
      parallel_content = Enum.map(1..10, fn i ->
        %{
          type: :text,
          content: "Independent text content #{i}",
          metadata: %{complexity: :moderate}
        }
      end)

      context = %{
        parallel_processing: %{enabled: true, max_workers: 4},
        processing_constraints: %{max_processing_time_ms: 5000}
      }

      result = PerformanceOptimizer.optimize_processing_pipeline(parallel_content, context)

      parallel_opts = result.optimizations_applied.parallel_processing
      assert parallel_opts.enabled == true
      assert parallel_opts.workers_used == 4
      assert parallel_opts.batches_created >= 2
      assert parallel_opts.speedup_factor >= 2.0  # At least 2x faster than sequential
      assert result.performance_metrics.total_processing_time_ms < 3000
    end

    test "optimizes content compression for bandwidth constraints" do
      bandwidth_sensitive_content = [
        %{
          type: :image,
          content: "uncompressed_image",
          metadata: %{size_mb: 15, compression: :none}
        },
        %{
          type: :document,
          content: "large_pdf",
          metadata: %{size_mb: 20, pages: 100}
        }
      ]

      context = %{
        bandwidth_constraints: %{max_total_mb: 10, compression_acceptable: true},
        quality_requirements: %{min_quality_score: 0.7}
      }

      result = PerformanceOptimizer.optimize_processing_pipeline(bandwidth_sensitive_content, context)

      compression = result.optimizations_applied.compression
      assert compression.enabled == true
      assert compression.total_size_reduction_mb >= 20  # Significant reduction
      assert compression.quality_preserved >= 0.7
      assert result.optimized_content |> Enum.all?(&(&1.metadata.size_mb <= 10))
    end
  end

  describe "implement_lazy_loading/2" do
    test "creates preview versions for large media content" do
      large_media = [
        %{
          type: :video,
          content: "4k_tutorial_video",
          metadata: %{
            size_mb: 800,
            duration: 2400,  # 40 minutes
            resolution: "4K"
          }
        },
        %{
          type: :audio,
          content: "high_quality_podcast",
          metadata: %{
            size_mb: 200,
            duration: 3600,  # 1 hour
            bitrate: "320kbps"
          }
        }
      ]

      lazy_config = %{
        preview_quality: :medium,
        preview_duration_limit: 30,  # 30 seconds max for previews
        memory_threshold_mb: 50
      }

      result = PerformanceOptimizer.implement_lazy_loading(large_media, lazy_config)

      video_lazy = result.lazy_items |> Enum.find(&(&1.original_type == :video))
      audio_lazy = result.lazy_items |> Enum.find(&(&1.original_type == :audio))

      assert video_lazy.preview.size_mb < 10
      assert video_lazy.preview.duration == 30
      assert video_lazy.loading_strategy == :progressive_download
      assert video_lazy.memory_footprint_mb < 50

      assert audio_lazy.preview.size_mb < 5
      assert audio_lazy.preview.duration == 30
      assert audio_lazy.thumbnail_generated == true  # Audio waveform thumbnail
    end

    test "implements smart preloading based on user interaction patterns" do
      content_with_priority = [
        %{type: :image, content: "critical_diagram", metadata: %{priority: :critical, size_mb: 8}},
        %{type: :image, content: "reference_chart", metadata: %{priority: :high, size_mb: 12}},
        %{type: :document, content: "appendix_doc", metadata: %{priority: :low, size_mb: 30}}
      ]

      user_context = %{
        interaction_patterns: %{
          frequently_accesses_diagrams: true,
          rarely_accesses_appendices: true,
          preload_threshold: :high
        }
      }

      result = PerformanceOptimizer.implement_lazy_loading(content_with_priority, %{
        user_context: user_context,
        preloading_strategy: :smart
      })

      preloaded = result.preloaded_items
      deferred = result.deferred_items

      critical_item = preloaded |> Enum.find(&(&1.metadata.priority == :critical))
      appendix_item = deferred |> Enum.find(&(&1.metadata.priority == :low))

      assert critical_item != nil  # Critical items should be preloaded
      assert appendix_item != nil  # Low priority items should be deferred
      assert result.preloading_decisions.based_on_user_patterns == true
    end
  end

  describe "optimize_caching_strategy/2" do
    test "implements content-type specific caching" do
      diverse_content = [
        %{type: :code, content: "elixir_function_1", metadata: %{language: :elixir, complexity: :high}},
        %{type: :code, content: "elixir_function_2", metadata: %{language: :elixir, complexity: :moderate}},
        %{type: :image, content: "ui_screenshot_1", metadata: %{context: :ui_testing}},
        %{type: :image, content: "ui_screenshot_2", metadata: %{context: :ui_testing}},
        %{type: :text, content: "unique_description", metadata: %{uniqueness: :high}}
      ]

      cache_context = %{
        cache_levels: [:processor_cache, :result_cache, :pattern_cache],
        cache_duration_minutes: 60,
        max_cache_size_mb: 100
      }

      result = PerformanceOptimizer.optimize_caching_strategy(diverse_content, cache_context)

      caching_strategy = result.caching_strategy

      # Should cache Elixir code processor
      elixir_cache = caching_strategy.processor_caches |> Enum.find(&(&1.processor_type == :elixir_code))
      assert elixir_cache != nil
      assert elixir_cache.cache_hits_expected >= 2

      # Should cache UI screenshot analysis patterns
      ui_cache = caching_strategy.pattern_caches |> Enum.find(&(&1.pattern_type == :ui_screenshot))
      assert ui_cache != nil
      assert ui_cache.reuse_potential >= 0.5

      # Unique content should not be heavily cached
      assert result.cache_efficiency.overall_hit_ratio >= 0.4
      assert result.cache_efficiency.memory_efficiency >= 0.7
    end

    test "implements distributed caching for session continuity" do
      session_content = [
        %{type: :image, content: "session_screenshot_1", metadata: %{session_id: "user_123"}},
        %{type: :document, content: "working_doc", metadata: %{session_id: "user_123", version: 1}}
      ]

      distributed_config = %{
        enable_distributed_cache: true,
        cache_persistence: :redis,
        session_aware: true,
        cross_session_sharing: %{enabled: true, privacy_preserved: true}
      }

      result = PerformanceOptimizer.optimize_caching_strategy(session_content, distributed_config)

      distributed_cache = result.distributed_caching
      assert distributed_cache.enabled == true
      assert distributed_cache.cache_keys |> Enum.all?(&String.contains?(&1, "user_123"))
      assert distributed_cache.privacy_compliance.anonymized_sharing == true
      assert distributed_cache.session_continuity.restoration_time_ms < 500
    end
  end

  describe "enable_parallel_processing/2" do
    test "optimizes worker allocation based on content complexity" do
      mixed_complexity_content = [
        %{type: :text, content: "simple text", metadata: %{complexity: :low, processing_time_est: 100}},
        %{type: :image, content: "complex_diagram", metadata: %{complexity: :high, processing_time_est: 5000}},
        %{type: :video, content: "analysis_video", metadata: %{complexity: :very_high, processing_time_est: 15000}},
        %{type: :code, content: "algorithm", metadata: %{complexity: :moderate, processing_time_est: 1000}}
      ]

      parallel_config = %{
        available_workers: 8,
        allocation_strategy: :dynamic,
        load_balancing: :complexity_aware
      }

      result = PerformanceOptimizer.enable_parallel_processing(mixed_complexity_content, parallel_config)

      worker_allocation = result.worker_allocation
      
      # High complexity items should get more workers
      video_allocation = worker_allocation |> Enum.find(&(&1.content_type == :video))
      text_allocation = worker_allocation |> Enum.find(&(&1.content_type == :text))

      assert video_allocation.workers_assigned >= 3
      assert text_allocation.workers_assigned == 1
      assert result.load_distribution.balanced == true
      assert result.estimated_speedup >= 2.5
    end

    test "implements work stealing for dynamic load balancing" do
      uneven_workload = [
        %{type: :image, content: "quick_process_1", metadata: %{processing_time_est: 500}},
        %{type: :image, content: "quick_process_2", metadata: %{processing_time_est: 600}},
        %{type: :document, content: "slow_process_1", metadata: %{processing_time_est: 10000}},
        %{type: :document, content: "slow_process_2", metadata: %{processing_time_est: 12000}}
      ]

      work_stealing_config = %{
        work_stealing: %{enabled: true, steal_threshold_ms: 2000},
        dynamic_reallocation: true,
        worker_count: 4
      }

      result = PerformanceOptimizer.enable_parallel_processing(uneven_workload, work_stealing_config)

      work_stealing = result.work_stealing
      assert work_stealing.enabled == true
      assert work_stealing.steal_events_expected >= 1
      assert work_stealing.load_balancing_efficiency >= 0.8
      assert result.worker_utilization.average_utilization >= 0.85
    end
  end

  describe "optimize_memory_usage/2" do
    test "implements memory-efficient streaming for large content" do
      large_content = [
        %{
          type: :document,
          content: "massive_pdf_content",
          metadata: %{size_mb: 100, pages: 500, memory_intensive: true}
        },
        %{
          type: :video,
          content: "large_video_file",
          metadata: %{size_mb: 300, duration: 7200}  # 2 hours
        }
      ]

      memory_constraints = %{
        max_memory_mb: 50,
        streaming_threshold_mb: 20,
        garbage_collection_aggressive: true
      }

      result = PerformanceOptimizer.optimize_memory_usage(large_content, memory_constraints)

      streaming_opts = result.memory_optimizations.streaming
      assert streaming_opts.enabled == true
      assert streaming_opts.chunk_size_mb <= 10
      assert streaming_opts.items_streamed |> length() == 2

      garbage_collection = result.memory_optimizations.garbage_collection
      assert garbage_collection.aggressive_mode == true
      assert garbage_collection.collection_frequency == :after_each_item
      assert result.memory_efficiency.peak_usage_mb <= 50
    end

    test "implements object pooling for frequently created objects" do
      repetitive_content = Enum.map(1..50, fn i ->
        %{
          type: :image,
          content: "screenshot_#{i}",
          metadata: %{context: :ui_testing, similar_processing: true}
        }
      end)

      pooling_config = %{
        object_pooling: %{
          enabled: true,
          pool_size: 10,
          object_types: [:image_processor, :ui_analyzer, :result_buffer]
        }
      }

      result = PerformanceOptimizer.optimize_memory_usage(repetitive_content, pooling_config)

      object_pooling = result.memory_optimizations.object_pooling
      assert object_pooling.pools_created |> length() == 3
      assert object_pooling.memory_saved_mb > 20
      assert object_pooling.allocation_reduction_percentage >= 60
      assert result.performance_metrics.gc_pressure_reduced == true
    end
  end

  describe "monitor_performance_metrics/1" do
    test "tracks comprehensive performance metrics during processing" do
      {:ok, monitor_pid} = PerformanceOptimizer.start_performance_monitoring(%{
        metrics: [:cpu_usage, :memory_usage, :processing_time, :throughput],
        sampling_interval_ms: 100
      })

      # Simulate content processing
      test_content = [
        %{type: :image, processing_time_ms: 1500, memory_mb: 25},
        %{type: :video, processing_time_ms: 8000, memory_mb: 80},
        %{type: :text, processing_time_ms: 200, memory_mb: 2}
      ]

      Enum.each(test_content, fn content ->
        PerformanceOptimizer.record_processing_event(monitor_pid, content)
      end)

      metrics = PerformanceOptimizer.get_performance_metrics(monitor_pid)

      assert metrics.total_processing_time_ms == 9700
      assert metrics.peak_memory_usage_mb == 80
      assert metrics.average_throughput_items_per_second > 0
      assert metrics.processing_efficiency.cpu_utilization >= 0.0
      assert metrics.processing_efficiency.memory_efficiency >= 0.0

      PerformanceOptimizer.stop_performance_monitoring(monitor_pid)
    end

    test "identifies performance bottlenecks and optimization opportunities" do
      {:ok, monitor_pid} = PerformanceOptimizer.start_performance_monitoring(%{
        bottleneck_detection: true,
        optimization_suggestions: true
      })

      # Simulate bottleneck scenario
      bottleneck_events = [
        %{stage: :content_loading, time_ms: 500, expected_ms: 100},  # Slow loading
        %{stage: :image_processing, time_ms: 5000, expected_ms: 1000},  # Very slow processing
        %{stage: :result_formatting, time_ms: 200, expected_ms: 50}  # Slow formatting
      ]

      Enum.each(bottleneck_events, fn event ->
        PerformanceOptimizer.record_stage_performance(monitor_pid, event)
      end)

      bottleneck_analysis = PerformanceOptimizer.get_bottleneck_analysis(monitor_pid)

      bottlenecks = bottleneck_analysis.identified_bottlenecks
      image_bottleneck = bottlenecks |> Enum.find(&(&1.stage == :image_processing))
      
      assert image_bottleneck.severity == :critical
      assert image_bottleneck.performance_impact >= 0.8
      assert image_bottleneck.optimization_suggestions |> length() >= 2

      assert bottleneck_analysis.optimization_opportunities |> Enum.any?(&(&1.type == :parallel_processing))
      assert bottleneck_analysis.optimization_opportunities |> Enum.any?(&(&1.type == :caching))

      PerformanceOptimizer.stop_performance_monitoring(monitor_pid)
    end
  end

  describe "adaptive_optimization/2" do
    test "adjusts optimization strategy based on system resources" do
      content = [
        %{type: :video, content: "analysis_video", metadata: %{size_mb: 100}},
        %{type: :image, content: "diagram", metadata: %{size_mb: 15}}
      ]

      # Simulate low-resource environment
      system_context = %{
        available_memory_mb: 200,
        cpu_cores: 2,
        network_speed: :slow,
        battery_level: :low  # Mobile device consideration
      }

      result = PerformanceOptimizer.adaptive_optimization(content, system_context)

      adaptive_strategy = result.adaptive_strategy
      assert adaptive_strategy.optimization_level == :conservative
      assert adaptive_strategy.parallel_processing.workers_limited == true
      assert adaptive_strategy.parallel_processing.max_workers <= 2
      assert adaptive_strategy.memory_optimization.aggressive_gc == true
      assert adaptive_strategy.power_optimization.cpu_throttling == true
    end

    test "scales optimization aggressively on high-resource systems" do
      content = Enum.map(1..20, fn i ->
        %{type: :image, content: "batch_image_#{i}", metadata: %{size_mb: 5}}
      end)

      # Simulate high-resource environment
      system_context = %{
        available_memory_mb: 8000,
        cpu_cores: 16,
        network_speed: :very_fast,
        gpu_available: true
      }

      result = PerformanceOptimizer.adaptive_optimization(content, system_context)

      adaptive_strategy = result.adaptive_strategy
      assert adaptive_strategy.optimization_level == :aggressive
      assert adaptive_strategy.parallel_processing.max_workers >= 8
      assert adaptive_strategy.gpu_acceleration.enabled == true
      assert adaptive_strategy.batch_processing.large_batches == true
      assert result.expected_performance_gain >= 5.0  # 5x speedup expected
    end
  end

  describe "error handling and recovery" do
    test "gracefully handles optimization failures" do
      problematic_content = [
        %{type: :image, content: "corrupted_data", metadata: %{size_mb: :invalid}},  # Invalid metadata
        %{type: :video, content: nil, metadata: %{size_mb: 50}}  # Nil content
      ]

      optimization_config = %{
        error_recovery: %{enabled: true, fallback_to_basic: true}
      }

      result = PerformanceOptimizer.optimize_processing_pipeline(problematic_content, optimization_config)

      error_recovery = result.error_recovery
      assert error_recovery.errors_encountered == 2
      assert error_recovery.fallback_applied == true
      assert error_recovery.basic_processing_used == true
      assert result.optimization_status == :completed_with_fallback
    end

    test "provides degraded performance mode for resource constraints" do
      large_content = Enum.map(1..100, fn i ->
        %{type: :document, content: "doc_#{i}", metadata: %{pages: 50}}
      end)

      constrained_context = %{
        available_memory_mb: 10,  # Very low memory
        max_processing_time_ms: 1000,  # Very tight deadline
        degraded_mode_acceptable: true
      }

      result = PerformanceOptimizer.optimize_processing_pipeline(large_content, constrained_context)

      degraded_mode = result.degraded_mode
      assert degraded_mode.activated == true
      assert degraded_mode.features_disabled |> length() > 0
      assert degraded_mode.processing_quality == :basic
      assert degraded_mode.items_processed < 100  # Some items skipped
      assert result.performance_metrics.completion_time_ms <= 1000
    end
  end
end