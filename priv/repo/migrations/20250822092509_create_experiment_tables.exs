defmodule TheMaestro.Repo.Migrations.CreateExperimentTables do
  use Ecto.Migration

  def change do
    # Main experiments table
    create table(:experiments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "draft"
      add :experiment_type, :string, null: false
      add :configuration, :map
      add :variants, {:array, :map}
      add :baseline_configuration, :map
      add :start_date, :utc_datetime
      add :end_date, :utc_datetime
      add :created_by, :string
      add :metadata, :map
      
      timestamps()
    end

    # Experiment executions table - tracks each execution/run
    create table(:experiment_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :experiment_id, references(:experiments, type: :binary_id, on_delete: :delete_all)
      add :variant_name, :string
      add :prompt_content, :text
      add :input_data, :map
      add :output_data, :map
      add :execution_time_ms, :integer
      add :success, :boolean, default: true
      add :error_message, :text
      add :user_context, :map
      add :metrics, :map
      add :executed_at, :utc_datetime
      
      timestamps()
    end

    # Experiment metrics aggregation table
    create table(:experiment_metrics, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :experiment_id, references(:experiments, type: :binary_id, on_delete: :delete_all)
      add :variant_name, :string
      add :metric_type, :string
      add :metric_value, :float
      add :sample_size, :integer
      add :confidence_interval, :map
      add :statistical_significance, :boolean
      add :calculated_at, :utc_datetime
      
      timestamps()
    end

    # User segments table for advanced analysis
    create table(:user_segments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :experiment_id, references(:experiments, type: :binary_id, on_delete: :delete_all)
      add :segment_name, :string
      add :segment_criteria, :map
      add :segment_size, :integer
      add :performance_metrics, :map
      add :statistical_analysis, :map
      
      timestamps()
    end

    # Progress tracking table
    create table(:experiment_progress, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :experiment_id, references(:experiments, type: :binary_id, on_delete: :delete_all)
      add :total_executions, :integer, default: 0
      add :successful_executions, :integer, default: 0
      add :failed_executions, :integer, default: 0
      add :last_execution_at, :utc_datetime
      add :completion_percentage, :float, default: 0.0
      add :estimated_completion, :utc_datetime
      
      timestamps()
    end

    # Create indexes for performance
    create index(:experiments, [:status])
    create index(:experiments, [:experiment_type])
    create index(:experiments, [:created_by])
    create index(:experiment_executions, [:experiment_id])
    create index(:experiment_executions, [:variant_name])
    create index(:experiment_executions, [:success])
    create index(:experiment_executions, [:executed_at])
    create index(:experiment_metrics, [:experiment_id, :variant_name])
    create index(:experiment_metrics, [:metric_type])
    create index(:user_segments, [:experiment_id])
    create index(:experiment_progress, [:experiment_id])
    
    # Composite indexes for common queries
    create index(:experiment_executions, [:experiment_id, :variant_name, :executed_at])
    create index(:experiment_metrics, [:experiment_id, :metric_type, :calculated_at])
  end
end