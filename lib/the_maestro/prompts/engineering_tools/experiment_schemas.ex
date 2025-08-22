defmodule TheMaestro.Prompts.EngineeringTools.ExperimentSchemas do
  @moduledoc """
  Ecto schemas for experiment data persistence.
  Provides real database integration for ExperimentationPlatform.
  """
  
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false
  alias TheMaestro.Repo

  # Main experiment schema
  defmodule Experiment do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "experiments" do
      field :name, :string
      field :description, :string
      field :status, :string, default: "draft"
      field :experiment_type, :string
      field :configuration, :map
      field :variants, {:array, :map}
      field :baseline_configuration, :map
      field :start_date, :utc_datetime
      field :end_date, :utc_datetime
      field :created_by, :string
      field :metadata, :map

      has_many :executions, TheMaestro.Prompts.EngineeringTools.ExperimentSchemas.ExperimentExecution, foreign_key: :experiment_id
      has_many :metrics, TheMaestro.Prompts.EngineeringTools.ExperimentSchemas.ExperimentMetric, foreign_key: :experiment_id
      has_many :segments, TheMaestro.Prompts.EngineeringTools.ExperimentSchemas.UserSegment, foreign_key: :experiment_id
      has_one :progress, TheMaestro.Prompts.EngineeringTools.ExperimentSchemas.ExperimentProgress, foreign_key: :experiment_id

      timestamps()
    end

    def changeset(experiment, attrs) do
      experiment
      |> cast(attrs, [:name, :description, :status, :experiment_type, :configuration,
                      :variants, :baseline_configuration, :start_date, :end_date, 
                      :created_by, :metadata])
      |> validate_required([:name, :experiment_type])
      |> validate_inclusion(:status, ["draft", "running", "paused", "completed", "terminated"])
      |> validate_inclusion(:experiment_type, ["a_b_test", "multivariate", "performance", "quality"])
    end
  end

  # Experiment execution schema
  defmodule ExperimentExecution do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "experiment_executions" do
      field :variant_name, :string
      field :prompt_content, :string
      field :input_data, :map
      field :output_data, :map
      field :execution_time_ms, :integer
      field :success, :boolean, default: true
      field :error_message, :string
      field :user_context, :map
      field :metrics, :map
      field :executed_at, :utc_datetime

      belongs_to :experiment, TheMaestro.Prompts.EngineeringTools.ExperimentSchemas.Experiment

      timestamps()
    end

    def changeset(execution, attrs) do
      execution
      |> cast(attrs, [:experiment_id, :variant_name, :prompt_content, :input_data,
                      :output_data, :execution_time_ms, :success, :error_message,
                      :user_context, :metrics, :executed_at])
      |> validate_required([:experiment_id, :variant_name, :executed_at])
      |> foreign_key_constraint(:experiment_id)
    end
  end

  # Experiment metrics schema
  defmodule ExperimentMetric do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "experiment_metrics" do
      field :variant_name, :string
      field :metric_type, :string
      field :metric_value, :float
      field :sample_size, :integer
      field :confidence_interval, :map
      field :statistical_significance, :boolean
      field :calculated_at, :utc_datetime

      belongs_to :experiment, TheMaestro.Prompts.EngineeringTools.ExperimentSchemas.Experiment

      timestamps()
    end

    def changeset(metric, attrs) do
      metric
      |> cast(attrs, [:experiment_id, :variant_name, :metric_type, :metric_value,
                      :sample_size, :confidence_interval, :statistical_significance,
                      :calculated_at])
      |> validate_required([:experiment_id, :metric_type, :metric_value, :calculated_at])
      |> foreign_key_constraint(:experiment_id)
    end
  end

  # User segment schema
  defmodule UserSegment do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "user_segments" do
      field :segment_name, :string
      field :segment_criteria, :map
      field :segment_size, :integer
      field :performance_metrics, :map
      field :statistical_analysis, :map

      belongs_to :experiment, TheMaestro.Prompts.EngineeringTools.ExperimentSchemas.Experiment

      timestamps()
    end

    def changeset(segment, attrs) do
      segment
      |> cast(attrs, [:experiment_id, :segment_name, :segment_criteria,
                      :segment_size, :performance_metrics, :statistical_analysis])
      |> validate_required([:experiment_id, :segment_name])
      |> foreign_key_constraint(:experiment_id)
    end
  end

  # Experiment progress schema
  defmodule ExperimentProgress do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "experiment_progress" do
      field :total_executions, :integer, default: 0
      field :successful_executions, :integer, default: 0
      field :failed_executions, :integer, default: 0
      field :last_execution_at, :utc_datetime
      field :completion_percentage, :float, default: 0.0
      field :estimated_completion, :utc_datetime

      belongs_to :experiment, TheMaestro.Prompts.EngineeringTools.ExperimentSchemas.Experiment

      timestamps()
    end

    def changeset(progress, attrs) do
      progress
      |> cast(attrs, [:experiment_id, :total_executions, :successful_executions,
                      :failed_executions, :last_execution_at, :completion_percentage,
                      :estimated_completion])
      |> validate_required([:experiment_id])
      |> validate_number(:completion_percentage, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 100.0)
      |> foreign_key_constraint(:experiment_id)
    end
  end

  # Database operation functions

  @doc """
  Creates a new experiment in the database.
  """
  def create_experiment(attrs) do
    %Experiment{}
    |> Experiment.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Loads an experiment by ID from the database.
  """
  def load_experiment(experiment_id) do
    case Repo.get(Experiment, experiment_id) do
      nil -> {:error, "Experiment not found"}
      experiment -> {:ok, experiment}
    end
  end

  @doc """
  Loads experiment with all related data (executions, metrics, etc.).
  """
  def load_experiment_with_relations(experiment_id) do
    case Repo.get(Experiment, experiment_id) do
      nil -> 
        {:error, "Experiment not found"}
      experiment ->
        experiment_with_relations = experiment
        |> Repo.preload([:executions, :metrics, :segments, :progress])
        
        {:ok, experiment_with_relations}
    end
  end

  @doc """
  Stores execution metrics to the database.
  """
  def store_execution_metrics(execution_data) do
    execution_attrs = %{
      experiment_id: execution_data.experiment_id,
      variant_name: execution_data.variant_name,
      prompt_content: execution_data.prompt_content,
      input_data: execution_data.input_data,
      output_data: execution_data.output_data,
      execution_time_ms: execution_data.execution_time_ms,
      success: execution_data.success,
      error_message: execution_data.error_message,
      user_context: execution_data.user_context,
      metrics: execution_data.metrics,
      executed_at: execution_data.executed_at || DateTime.utc_now()
    }

    %ExperimentExecution{}
    |> ExperimentExecution.changeset(execution_attrs)
    |> Repo.insert()
  end

  @doc """
  Updates experiment progress tracking in the database.
  """
  def update_experiment_progress(experiment_id, execution_data) do
    # Get or create progress record
    progress = case Repo.get_by(ExperimentProgress, experiment_id: experiment_id) do
      nil ->
        %ExperimentProgress{experiment_id: experiment_id}
      existing_progress ->
        existing_progress
    end

    # Calculate updated metrics
    total_executions = progress.total_executions + 1
    successful_executions = if execution_data.success do
      progress.successful_executions + 1
    else
      progress.successful_executions
    end
    failed_executions = if execution_data.success do
      progress.failed_executions
    else
      progress.failed_executions + 1
    end

    # Update progress
    progress_attrs = %{
      experiment_id: experiment_id,
      total_executions: total_executions,
      successful_executions: successful_executions,
      failed_executions: failed_executions,
      last_execution_at: execution_data.executed_at || DateTime.utc_now(),
      completion_percentage: calculate_completion_percentage(experiment_id, total_executions)
    }

    progress
    |> ExperimentProgress.changeset(progress_attrs)
    |> Repo.insert_or_update()
  end

  @doc """
  Stores aggregated metrics for an experiment.
  """
  def store_aggregated_metrics(experiment_id, variant_name, metrics_data) do
    Enum.each(metrics_data, fn {metric_type, metric_info} ->
      metric_attrs = %{
        experiment_id: experiment_id,
        variant_name: variant_name,
        metric_type: to_string(metric_type),
        metric_value: metric_info.value,
        sample_size: metric_info.sample_size,
        confidence_interval: metric_info.confidence_interval,
        statistical_significance: metric_info.significant,
        calculated_at: DateTime.utc_now()
      }

      %ExperimentMetric{}
      |> ExperimentMetric.changeset(metric_attrs)
      |> Repo.insert()
    end)
  end

  @doc """
  Loads user segments for an experiment from the database.
  """
  def load_user_segments(experiment_id) do
    segments = from(s in UserSegment,
      where: s.experiment_id == ^experiment_id,
      order_by: [desc: s.segment_size]
    )
    |> Repo.all()

    case segments do
      [] ->
        # Generate default segments if none exist
        create_default_user_segments(experiment_id)
      existing_segments ->
        {:ok, existing_segments}
    end
  end

  @doc """
  Creates default user segments for analysis.
  """
  def create_default_user_segments(experiment_id) do
    # Get execution data to analyze user patterns
    executions = from(e in ExperimentExecution,
      where: e.experiment_id == ^experiment_id,
      select: %{variant_name: e.variant_name, user_context: e.user_context, success: e.success}
    )
    |> Repo.all()

    if length(executions) > 0 do
      segments = generate_segments_from_executions(experiment_id, executions)
      
      # Store segments in database
      Enum.each(segments, fn segment_attrs ->
        %UserSegment{}
        |> UserSegment.changeset(segment_attrs)
        |> Repo.insert()
      end)

      load_user_segments(experiment_id)
    else
      {:ok, []}
    end
  end

  # Helper functions

  defp calculate_completion_percentage(_experiment_id, total_executions) do
    # Simple estimation: assume 100 executions represents completion
    # In a real system, this would be based on experiment configuration
    min(total_executions / 100.0 * 100.0, 100.0)
  end

  defp generate_segments_from_executions(experiment_id, executions) do
    # Group executions by success/failure and other criteria
    total_executions = length(executions)
    successful_executions = Enum.filter(executions, & &1.success)
    failed_executions = Enum.filter(executions, &(not &1.success))

    # Create segments based on success patterns
    segments = []

    # All users segment
    all_users_segment = %{
      experiment_id: experiment_id,
      segment_name: "all_users",
      segment_criteria: %{type: "all"},
      segment_size: total_executions,
      performance_metrics: calculate_segment_performance(executions),
      statistical_analysis: %{
        success_rate: length(successful_executions) / total_executions,
        sample_size: total_executions
      }
    }
    segments = [all_users_segment | segments]

    # Success-based segments
    segments = if length(successful_executions) > 0 do
      success_segment = %{
        experiment_id: experiment_id,
        segment_name: "successful_users",
        segment_criteria: %{type: "success", value: true},
        segment_size: length(successful_executions),
        performance_metrics: calculate_segment_performance(successful_executions),
        statistical_analysis: %{
          success_rate: 1.0,
          sample_size: length(successful_executions)
        }
      }
      [success_segment | segments]
    else
      segments
    end

    segments = if length(failed_executions) > 0 do
      failed_segment = %{
        experiment_id: experiment_id,
        segment_name: "failed_users",
        segment_criteria: %{type: "success", value: false},
        segment_size: length(failed_executions),
        performance_metrics: calculate_segment_performance(failed_executions),
        statistical_analysis: %{
          success_rate: 0.0,
          sample_size: length(failed_executions)
        }
      }
      [failed_segment | segments]
    else
      segments
    end

    segments
  end

  defp calculate_segment_performance(executions) do
    total_count = length(executions)
    
    if total_count > 0 do
      success_count = Enum.count(executions, & &1.success)
      success_rate = success_count / total_count
      
      %{
        success_rate: success_rate,
        total_executions: total_count,
        successful_executions: success_count,
        failed_executions: total_count - success_count
      }
    else
      %{
        success_rate: 0.0,
        total_executions: 0,
        successful_executions: 0,
        failed_executions: 0
      }
    end
  end

  @doc """
  Gets experiment execution statistics from database.
  """
  def get_experiment_statistics(experiment_id) do
    # Get basic execution counts
    execution_stats = from(e in ExperimentExecution,
      where: e.experiment_id == ^experiment_id,
      group_by: [e.variant_name, e.success],
      select: %{
        variant_name: e.variant_name,
        success: e.success,
        count: count(e.id)
      }
    )
    |> Repo.all()

    # Get performance metrics
    performance_stats = from(e in ExperimentExecution,
      where: e.experiment_id == ^experiment_id,
      group_by: e.variant_name,
      select: %{
        variant_name: e.variant_name,
        avg_execution_time: avg(e.execution_time_ms),
        total_executions: count(e.id),
        success_rate: fragment("SUM(CASE WHEN ? THEN 1 ELSE 0 END) * 1.0 / COUNT(*)", e.success)
      }
    )
    |> Repo.all()

    %{
      execution_counts: execution_stats,
      performance_metrics: performance_stats
    }
  end
end