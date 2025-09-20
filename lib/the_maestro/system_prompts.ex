defmodule TheMaestro.SystemPrompts do
  @moduledoc """
  System prompt resolver and session association helpers.
  """

  import Ecto.Query, warn: false
  alias TheMaestro.Repo
  require Logger

  alias TheMaestro.Conversations.Session
  alias TheMaestro.SuppliedContext.SuppliedContextItem
  alias TheMaestro.SystemPrompts.SessionPromptItem
  alias TheMaestro.SystemPrompts.Renderer.{Anthropic, Gemini, OpenAI}
  @type provider :: :openai | :anthropic | :gemini
  @copyable_fields [
    :type,
    :provider,
    :render_format,
    :name,
    :text,
    :labels,
    :metadata,
    :position,
    :immutable,
    :source_ref
  ]

  @doc """
  List default system prompts for a provider (including shared ones) in display order.
  """
  @spec list_provider_defaults(provider()) :: [SuppliedContextItem.t()]
  def list_provider_defaults(provider) when provider in [:openai, :anthropic, :gemini] do
    provider_atom = provider_to_enum(provider)

    Repo.all(
      from i in SuppliedContextItem,
        where: i.type == :system_prompt and i.is_default == true
    )
    |> Enum.filter(&(&1.provider in [provider_atom, :shared]))
    |> Enum.sort_by(fn prompt ->
      ordering = if prompt.provider == provider_atom, do: 0, else: 1
      {ordering, prompt.position || 0, prompt.name}
    end)
  end

  @doc """
  Return prompt specs for the provider's default stack suitable for `set_session_prompts/3`.
  """
  @spec default_prompt_specs(provider()) :: [map()]
  def default_prompt_specs(provider) when provider in [:openai, :anthropic, :gemini] do
    list_provider_defaults(provider)
    |> Enum.map(fn prompt ->
      %{
        id: prompt.id,
        enabled: true,
        overrides: %{}
      }
    end)
  end

  @doc """
  Build a resolved prompt stack using provider defaults and shared prompts.
  """
  @spec default_stack(provider()) :: %{source: :default, prompts: [map()]}
  def default_stack(provider) when provider in [:openai, :anthropic, :gemini] do
    prompts =
      list_provider_defaults(provider)
      |> Enum.map(fn prompt -> %{prompt: prompt, overrides: %{}, session_prompt_item: nil} end)

    %{source: :default, prompts: prompts}
  end

  @doc """
  Ensure a session has the provider defaults configured.
  """
  @spec set_session_defaults(Session.t() | Session.id(), provider(), keyword()) ::
          {:ok, [SessionPromptItem.t()]} | {:error, term()}
  def set_session_defaults(session_or_id, provider, opts \\ [])
      when provider in [:openai, :anthropic, :gemini] do
    specs = default_prompt_specs(provider)

    if specs == [] do
      {:ok, []}
    else
      set_session_prompts(session_or_id, provider, specs, opts)
    end
  end

  @doc """
  List all versions for a prompt family, newest first.
  Accepts a `SuppliedContextItem` or a `family_id` UUID.
  """
  @spec list_versions(SuppliedContextItem.t() | binary()) :: [SuppliedContextItem.t()]
  def list_versions(%SuppliedContextItem{} = item), do: list_versions(item.family_id)

  def list_versions(family_id) when is_binary(family_id) do
    Repo.all(
      from i in SuppliedContextItem,
        where: i.family_id == ^family_id,
        order_by: [desc: i.version, desc: i.inserted_at]
    )
  end

  @doc """
  Create a new version for an existing prompt family.
  By default copies the latest attributes, bumps the version number, and optionally marks it as default.
  """
  @spec create_version(SuppliedContextItem.t(), map()) ::
          {:ok, SuppliedContextItem.t()} | {:error, term()}
  def create_version(%SuppliedContextItem{} = base, attrs \\ %{}) do
    attrs = atomize_prompt_attrs(attrs)

    Repo.transaction(fn ->
      next_version = next_version(base.family_id)

      new_attrs =
        build_prompt_attrs(
          base,
          attrs,
          family_id: base.family_id,
          default_version: next_version,
          default_is_default: Map.get(attrs, :is_default, false),
          default_editor: Map.get(attrs, :editor, Map.get(base, :editor))
        )

      changeset = SuppliedContextItem.changeset(%SuppliedContextItem{}, new_attrs)

      case Repo.insert(changeset) do
        {:ok, prompt} ->
          maybe_disable_other_defaults(base.family_id, prompt.id, Map.get(new_attrs, :is_default))
          prompt

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, prompt} -> {:ok, prompt}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_disable_other_defaults(_family_id, _new_id, false), do: :ok

  defp maybe_disable_other_defaults(family_id, new_id, true) do
    Repo.update_all(
      from(i in SuppliedContextItem, where: i.family_id == ^family_id and i.id != ^new_id),
      set: [is_default: false]
    )

    :ok
  end

  @doc """
  Fork an existing prompt into a brand new family.
  Returns `{:ok, prompt}` with version defaulting to 1 (or provided value).
  """
  @spec fork_version(SuppliedContextItem.t(), map()) ::
          {:ok, SuppliedContextItem.t()} | {:error, term()}
  def fork_version(%SuppliedContextItem{} = base, attrs \\ %{}) do
    attrs = atomize_prompt_attrs(attrs)

    new_attrs =
      build_prompt_attrs(
        base,
        attrs,
        family_id: nil,
        default_version: Map.get(attrs, :version, 1),
        default_is_default: Map.get(attrs, :is_default, true),
        default_editor: Map.get(attrs, :editor, Map.get(base, :editor))
      )
      |> Map.delete(:family_id)

    changeset = SuppliedContextItem.changeset(%SuppliedContextItem{}, new_attrs)

    case Repo.insert(changeset) do
      {:ok, prompt} -> {:ok, prompt}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Promote the provided version to be the default for its family.
  """
  @spec set_default_version(SuppliedContextItem.t()) :: :ok | {:error, term()}
  def set_default_version(%SuppliedContextItem{} = version) do
    Repo.transaction(fn ->
      Repo.update_all(
        from(i in SuppliedContextItem, where: i.family_id == ^version.family_id),
        set: [is_default: false]
      )

      Repo.update_all(
        from(i in SuppliedContextItem, where: i.id == ^version.id),
        set: [is_default: true]
      )
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Alias for `set_default_version/1` to restore a previous version as active.
  """
  @spec restore_version(SuppliedContextItem.t()) :: :ok | {:error, term()}
  def restore_version(%SuppliedContextItem{} = version), do: set_default_version(version)

  @doc """
  Delete a version. Aborts if it is the default, immutable, or in use by any session.
  """
  @spec delete_version(SuppliedContextItem.t()) :: :ok | {:error, term()}
  def delete_version(%SuppliedContextItem{} = version) do
    Repo.transaction(fn ->
      in_use? =
        Repo.aggregate(
          from(spi in SessionPromptItem, where: spi.supplied_context_item_id == ^version.id),
          :count,
          :id
        ) > 0

      cond do
        version.immutable -> Repo.rollback(:immutable_prompt)
        version.is_default -> Repo.rollback(:cannot_delete_default)
        in_use? -> Repo.rollback(:prompt_in_use)
        true -> :ok
      end

      case Repo.delete(version) do
        {:ok, _} -> :ok
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Resolve system prompts for a session and provider. Returns a map with:
    * `:source` — `:session` when session-specific prompts are present, `:default` otherwise
    * `:prompts` — ordered list of `%{prompt: SuppliedContextItem.t(), overrides: map(), session_prompt_item: SessionPromptItem.t() | nil}`
  """
  @spec resolve_for_session(Session.t() | Session.id(), provider(), keyword()) ::
          {:ok, %{source: :session | :default, prompts: [map()]}}
  def resolve_for_session(session_or_id, provider, opts \\ [])
      when provider in [:openai, :anthropic, :gemini] do
    session_id = ensure_session_id(session_or_id)
    emit_telemetry? = Keyword.get(opts, :telemetry?, true)
    start_time = System.monotonic_time()

    session_prompts =
      Repo.all(session_prompt_query(session_id, provider))
      |> Enum.filter(& &1.session_prompt_item.enabled)

    result =
      case session_prompts do
        [] ->
          defaults = list_provider_defaults(provider)

          %{
            source: :default,
            prompts:
              Enum.map(defaults, fn prompt ->
                %{prompt: prompt, overrides: %{}, session_prompt_item: nil}
              end)
          }

        items ->
          %{
            source: :session,
            prompts:
              Enum.map(items, fn %{prompt: prompt, session_prompt_item: spi} ->
                %{prompt: prompt, overrides: spi.overrides || %{}, session_prompt_item: spi}
              end)
          }
      end

    maybe_emit_resolved_telemetry(session_id, provider, result, start_time, emit_telemetry?)

    {:ok, result}
  end

  @doc """
  Return the raw session prompt associations (enabled or disabled) for UI usage.
  """
  @spec list_session_prompts(Session.t() | Session.id(), provider()) :: [SessionPromptItem.t()]
  def list_session_prompts(session_or_id, provider)
      when provider in [:openai, :anthropic, :gemini] do
    session_id = ensure_session_id(session_or_id)

    Repo.all(session_prompt_query(session_id, provider))
    |> Enum.map(fn %{session_prompt_item: spi, prompt: prompt} ->
      Map.put(spi, :prompt, prompt)
    end)
  end

  @doc """
  Replace the entire prompt stack for a session/provider with the provided ordered list.

  Each item may be:
    * `%{id: prompt_id, enabled: boolean(), overrides: map()}`
    * `%{"id" => prompt_id, "enabled" => ..., "overrides" => ...}`

  Overrides default to `%{}` and enabled defaults to `true`.
  Prompts marked immutable cannot be disabled and must be included.
  """
  @spec set_session_prompts(Session.t() | Session.id(), provider(), [map()], keyword()) ::
          {:ok, [SessionPromptItem.t()]} | {:error, term()}
  def set_session_prompts(session_or_id, provider, prompt_specs, opts \\ [])
      when provider in [:openai, :anthropic, :gemini] and is_list(prompt_specs) do
    session_id = ensure_session_id(session_or_id)
    normalized = Enum.map(prompt_specs, &normalize_spec/1)
    provider_enum = provider_to_enum(provider)
    repo = Keyword.get(opts, :repo, Repo)
    transactional? = Keyword.get(opts, :transaction?, true)

    with :ok <- validate_spec_list(normalized),
         {:ok, prompts_by_id} <- load_prompts(normalized, provider) do
      do_set_session_prompts(
        repo,
        transactional?,
        session_id,
        provider_enum,
        normalized,
        prompts_by_id
      )
    end
  end

  defp do_set_session_prompts(
         repo,
         transactional?,
         session_id,
         provider_enum,
         normalized,
         prompts_by_id
       ) do
    operation = fn ->
      clear_session_prompts(repo, session_id, provider_enum)

      with :ok <- insert_all_prompts(repo, session_id, provider_enum, normalized, prompts_by_id) do
        {:ok, load_session_prompts(repo, session_id, provider_enum)}
      end
    end

    if transactional?, do: wrap_tx(repo, operation), else: operation.()
  end

  defp wrap_tx(repo, operation) do
    repo.transaction(fn ->
      case operation.() do
        {:ok, list} -> {:ok, list}
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> normalize_tx_result()
  end

  defp normalize_tx_result({:ok, list}), do: {:ok, list}
  defp normalize_tx_result({:error, reason}), do: {:error, reason}

  defp clear_session_prompts(repo, session_id, provider_enum) do
    provider_value = Atom.to_string(provider_enum)

    repo.delete_all(
      from spi in SessionPromptItem,
        where: spi.session_id == ^session_id and spi.provider == type(^provider_value, :string)
    )
  end

  defp insert_all_prompts(repo, session_id, provider_enum, normalized, prompts_by_id) do
    normalized
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {spec, idx}, acc ->
      case insert_one_prompt(repo, session_id, provider_enum, spec, idx, prompts_by_id) do
        :ok -> {:cont, acc}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp insert_one_prompt(
         repo,
         session_id,
         provider_enum,
         %{prompt_id: prompt_id, enabled: enabled, overrides: overrides},
         idx,
         prompts_by_id
       ) do
    prompt = Map.fetch!(prompts_by_id, prompt_id)

    if prompt.immutable and not enabled do
      {:error, {:immutable_prompt_disabled, prompt_id}}
    else
      attrs = %{
        session_id: session_id,
        supplied_context_item_id: prompt_id,
        provider: provider_enum,
        position: idx,
        enabled: enabled,
        overrides: overrides
      }

      case SessionPromptItem.changeset(%SessionPromptItem{}, attrs) |> repo.insert() do
        {:ok, _spi} -> :ok
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  defp load_session_prompts(repo, session_id, provider_enum) do
    repo.all(session_prompt_query(session_id, provider_enum))
    |> Enum.map(fn %{session_prompt_item: spi, prompt: prompt} ->
      Map.put(spi, :prompt, prompt)
    end)
  end

  @doc """
  Reorder existing session prompts according to the supplied list of session_prompt_item ids.
  """
  @spec reorder_session_prompts(Session.t() | Session.id(), provider(), [SessionPromptItem.id()]) ::
          :ok | {:error, term()}
  def reorder_session_prompts(session_or_id, provider, ordered_ids)
      when provider in [:openai, :anthropic, :gemini] and is_list(ordered_ids) do
    session_id = ensure_session_id(session_or_id)

    provider_value = Atom.to_string(provider_to_enum(provider))

    existing =
      Repo.all(
        from spi in SessionPromptItem,
          where: spi.session_id == ^session_id and spi.provider == type(^provider_value, :string),
          select: spi.id
      )
      |> MapSet.new()

    if MapSet.new(ordered_ids) != existing,
      do: {:error, :mismatched_ids},
      else: reorder_in_tx(ordered_ids)
  end

  defp reorder_in_tx(ordered_ids) do
    Repo.transaction(fn ->
      ordered_ids
      |> Enum.with_index()
      |> Enum.each(fn {id, idx} ->
        Repo.update_all(
          from(spi in SessionPromptItem, where: spi.id == ^id),
          set: [position: idx]
        )
      end)
    end)
  end

  @doc """
  Toggle a session prompt’s enabled flag.
  """
  @spec toggle_session_prompt(SessionPromptItem.id(), boolean()) :: :ok | {:error, term()}
  def toggle_session_prompt(session_prompt_item_id, enabled) when is_boolean(enabled) do
    Repo.transaction(fn -> toggle_in_tx(session_prompt_item_id, enabled) end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp toggle_in_tx(session_prompt_item_id, enabled) do
    case Repo.one(session_prompt_with_prompt_query(session_prompt_item_id)) do
      nil ->
        Repo.rollback(:not_found)

      %{session_prompt_item: spi, prompt: prompt} ->
        if prompt.immutable and enabled == false do
          Repo.rollback(:immutable_prompt_disabled)
        else
          Repo.update_all(
            from(s in SessionPromptItem, where: s.id == ^spi.id),
            set: [enabled: enabled]
          )

          :ok
        end
    end
  end

  @doc """
  Render resolved prompts into provider-specific payload structures while preserving order and formatting.
  Expects the result of `resolve_for_session/3`.
  """
  @spec render_for_provider(provider(), map()) :: any()
  def render_for_provider(:openai, stack) do
    OpenAI.render(stack)
  end

  def render_for_provider(:anthropic, stack) do
    Anthropic.render(stack)
  end

  def render_for_provider(:gemini, stack) do
    Gemini.render(stack)
  end

  defp atomize_prompt_attrs(%{} = attrs) do
    Enum.reduce(attrs, %{}, fn
      {key, value}, acc when is_atom(key) ->
        Map.put(acc, key, value)

      {key, value}, acc when is_binary(key) ->
        case prompt_atom_from_string(key) do
          nil -> acc
          atom_key -> Map.put(acc, atom_key, value)
        end

      {_other, _value}, acc ->
        acc
    end)
  end

  defp atomize_prompt_attrs(_), do: %{}

  defp prompt_atom_from_string("type"), do: :type
  defp prompt_atom_from_string("provider"), do: :provider
  defp prompt_atom_from_string("render_format"), do: :render_format
  defp prompt_atom_from_string("name"), do: :name
  defp prompt_atom_from_string("text"), do: :text
  defp prompt_atom_from_string("labels"), do: :labels
  defp prompt_atom_from_string("metadata"), do: :metadata
  defp prompt_atom_from_string("position"), do: :position
  defp prompt_atom_from_string("is_default"), do: :is_default
  defp prompt_atom_from_string("immutable"), do: :immutable
  defp prompt_atom_from_string("source_ref"), do: :source_ref
  defp prompt_atom_from_string("version"), do: :version
  defp prompt_atom_from_string("editor"), do: :editor
  defp prompt_atom_from_string("change_note"), do: :change_note
  defp prompt_atom_from_string(_), do: nil

  defp build_prompt_attrs(base, attrs, opts) do
    family_id = Keyword.get(opts, :family_id)
    default_version = Keyword.fetch!(opts, :default_version)
    default_is_default = Keyword.get(opts, :default_is_default, false)
    default_editor = Keyword.get(opts, :default_editor, Map.get(base, :editor))

    base_attrs = copy_attrs_from_base(base)
    overrides = Map.take(attrs, @copyable_fields)

    labels = ensure_map(Map.get(overrides, :labels, Map.get(base_attrs, :labels)))
    metadata = ensure_map(Map.get(overrides, :metadata, Map.get(base_attrs, :metadata)))

    merged =
      base_attrs
      |> Map.merge(overrides)
      |> Map.put(:labels, labels)
      |> Map.put(:metadata, metadata)
      |> Map.put(:version, Map.get(attrs, :version, default_version))
      |> Map.put(:is_default, Map.get(attrs, :is_default, default_is_default))
      |> Map.put(:immutable, Map.get(attrs, :immutable, Map.get(base, :immutable)))
      |> Map.put(:editor, Map.get(attrs, :editor, default_editor))
      |> Map.put(:change_note, Map.get(attrs, :change_note, nil))

    merged =
      if family_id do
        Map.put(merged, :family_id, family_id)
      else
        merged
      end

    merged
  end

  defp copy_attrs_from_base(base) do
    Enum.reduce(@copyable_fields, %{}, fn key, acc ->
      Map.put(acc, key, Map.get(base, key))
    end)
  end

  defp ensure_map(nil), do: %{}
  defp ensure_map(map) when is_map(map), do: map
  defp ensure_map(_), do: %{}

  defp next_version(family_id) do
    (Repo.one(
       from i in SuppliedContextItem,
         where: i.family_id == ^family_id,
         select: max(i.version)
     ) || 0) + 1
  end

  # Helper queries

  defp session_prompt_query(session_id, provider) do
    provider_value = Atom.to_string(provider_to_enum(provider))

    from spi in SessionPromptItem,
      join: prompt in SuppliedContextItem,
      on: prompt.id == spi.supplied_context_item_id,
      where: spi.session_id == ^session_id and spi.provider == type(^provider_value, :string),
      order_by: [asc: spi.position, asc: spi.inserted_at],
      preload: [supplied_context_item: prompt],
      select: %{session_prompt_item: spi, prompt: prompt}
  end

  defp session_prompt_with_prompt_query(id) do
    from spi in SessionPromptItem,
      join: prompt in SuppliedContextItem,
      on: prompt.id == spi.supplied_context_item_id,
      where: spi.id == ^id,
      select: %{session_prompt_item: spi, prompt: prompt}
  end

  defp ensure_session_id(%Session{id: id}) when is_binary(id), do: id
  defp ensure_session_id(id) when is_binary(id), do: id

  defp ensure_session_id(id) do
    raise ArgumentError, "expected session struct or id, got: #{inspect(id)}"
  end

  defp provider_to_enum(provider) when is_atom(provider), do: provider

  defp normalize_spec(%{id: id} = spec) do
    spec
    |> Map.delete(:id)
    |> Map.put(:prompt_id, id)
    |> normalize_spec()
  end

  defp normalize_spec(%{"id" => id} = spec) do
    spec
    |> Map.delete("id")
    |> Map.put("prompt_id", id)
    |> normalize_spec()
  end

  defp normalize_spec(%{prompt_id: id} = spec) when is_binary(id) do
    %{
      prompt_id: id,
      enabled: Map.get(spec, :enabled, Map.get(spec, "enabled", true)) |> truthy?(),
      overrides: normalize_overrides(Map.get(spec, :overrides) || Map.get(spec, "overrides"))
    }
  end

  defp normalize_spec(%{"prompt_id" => id} = spec) when is_binary(id) do
    normalize_spec(%{
      prompt_id: id,
      enabled: Map.get(spec, "enabled"),
      overrides: Map.get(spec, "overrides")
    })
  end

  defp normalize_spec(other), do: raise(ArgumentError, "invalid prompt spec: #{inspect(other)}")

  defp truthy?(value) when value in [nil, "", %{}], do: true
  defp truthy?(value) when value in [false, "false", "FALSE", 0], do: false
  defp truthy?(value) when value in [true, "true", "TRUE", 1], do: true
  defp truthy?(value) when is_boolean(value), do: value
  defp truthy?(_), do: true

  defp normalize_overrides(nil), do: %{}
  defp normalize_overrides(map) when is_map(map), do: map
  defp normalize_overrides(_), do: %{}

  defp validate_spec_list([]), do: :ok

  defp validate_spec_list(list) do
    ids = Enum.map(list, & &1.prompt_id)

    if Enum.uniq(ids) == ids do
      :ok
    else
      {:error, :duplicate_prompts}
    end
  end

  defp load_prompts(normalized, provider) do
    ids = Enum.map(normalized, & &1.prompt_id)

    prompts =
      Repo.all(
        from i in SuppliedContextItem,
          where: i.id in ^ids and i.type == :system_prompt
      )

    by_id = Map.new(prompts, &{&1.id, &1})

    case {
      length(prompts) == length(ids),
      Enum.all?(prompts, fn prompt -> prompt.provider in [provider, :shared] end)
    } do
      {false, _} -> {:error, :unknown_prompt}
      {_, false} -> {:error, :provider_mismatch}
      {true, true} -> {:ok, by_id}
    end
  end

  defp maybe_emit_resolved_telemetry(_session_id, _provider, _result, _start_time, false), do: :ok

  defp maybe_emit_resolved_telemetry(session_id, provider, result, start_time, true) do
    duration = System.monotonic_time() - start_time
    prompts = Map.get(result, :prompts, [])
    prompt_structs = Enum.map(prompts, & &1.prompt)
    prompt_count = length(prompt_structs)

    overrides_count =
      Enum.count(prompts, fn %{overrides: overrides} -> map_size(overrides || %{}) > 0 end)

    immutable_ids =
      prompt_structs
      |> Enum.filter(& &1.immutable)
      |> Enum.map(& &1.id)

    missing_defaults = if result.source == :default and prompt_count == 0, do: 1, else: 0

    measurements = %{
      duration: duration,
      prompt_count: prompt_count,
      overrides_count: overrides_count,
      missing_defaults: missing_defaults
    }

    metadata = %{
      provider: provider,
      session_id: session_id,
      source: result.source,
      prompt_ids: Enum.map(prompt_structs, & &1.id),
      immutable_prompt_ids: immutable_ids
    }

    :telemetry.execute([:system_prompts, :resolved], measurements, metadata)

    if missing_defaults == 1 do
      Logger.warning(fn ->
        "system_prompts default stack empty for provider=#{provider}, falling back to empty prompts"
      end)
    end

    if duration_exceeds_guardrail?(duration) do
      Logger.warning(fn ->
        "system_prompts resolution exceeded guardrail (duration=#{System.convert_time_unit(duration, :native, :millisecond)}ms, provider=#{provider})"
      end)
    end
  end

  defp duration_exceeds_guardrail?(duration_native) do
    duration_ms = System.convert_time_unit(duration_native, :native, :millisecond)
    duration_ms > 150
  end
end
