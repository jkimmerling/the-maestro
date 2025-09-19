defmodule TheMaestro.SuppliedContext do
  @moduledoc """
  The SuppliedContext context.
  """

  import Ecto.Query, warn: false
  alias TheMaestro.Repo

  alias TheMaestro.SuppliedContext.SuppliedContextItem

  @cache_table :supplied_context_prompt_cache
  @cache_ttl_ms 120_000

  @doc """
  Returns the list of supplied_context_items.

  ## Examples

      iex> list_supplied_context_items()
      [%SuppliedContextItem{}, ...]

  """
  def list_supplied_context_items do
    Repo.all(
      from i in SuppliedContextItem,
        order_by: [asc: i.type, asc: i.provider, asc: i.position, desc: i.version, asc: i.name]
    )
  end

  @doc """
  List system prompts scoped to a provider, optionally including shared defaults.

  Options:
    * `:only_defaults` (boolean, default `false`) — limits the result to default prompt versions.
    * `:include_shared` (boolean, default `true` except when provider `:shared`) — include shared prompts.
    * `:group_by_family` (boolean, default `false`) — when true groups versions by family id.
  """
  @spec list_system_prompts(:all | SuppliedContextItem.provider(), keyword()) ::
          [SuppliedContextItem.t()] | [map()]
  def list_system_prompts(provider, opts \\ []) do
    include_shared? = Keyword.get(opts, :include_shared, provider not in [:shared, :all])
    only_defaults? = Keyword.get(opts, :only_defaults, false)
    group_by_family? = Keyword.get(opts, :group_by_family, false)

    cache_key =
      {:list_system_prompts, provider, only_defaults?, include_shared?, group_by_family?}

    cache_fetch(cache_key, fn ->
      provider
      |> providers_for(include_shared?)
      |> fetch_system_prompts(provider, only_defaults?, group_by_family?)
    end)
  end

  @doc """
  Fetch the default system prompt for the given provider/name combination.
  Falls back to the shared prompt when provider-specific default is absent (if shared prompts included).
  """
  @spec get_default_prompt!(SuppliedContextItem.provider(), String.t(), keyword()) ::
          SuppliedContextItem.t()
  def get_default_prompt!(provider, name, opts \\ []) when is_binary(name) do
    include_shared? = Keyword.get(opts, :include_shared, provider != :shared)

    cache_key = {:default_system_prompt, provider, name, include_shared?}

    cache_fetch(cache_key, fn ->
      provider
      |> providers_for(include_shared?)
      |> fetch_default_prompt(provider, name)
    end)
  end

  @doc """
  Convenience: list items filtered by `type` (:persona | :system_prompt).
  """
  def list_items(type) when type in [:persona, :system_prompt] do
    import Ecto.Query

    Repo.all(
      from i in SuppliedContextItem,
        where: i.type == ^type,
        order_by: [asc: i.provider, asc: i.position, desc: i.version, asc: i.name]
    )
  end

  @doc """
  Gets a single supplied_context_item.

  Raises `Ecto.NoResultsError` if the Supplied context item does not exist.

  ## Examples

      iex> get_supplied_context_item!(123)
      %SuppliedContextItem{}

      iex> get_supplied_context_item!(456)
      ** (Ecto.NoResultsError)

  """
  def get_supplied_context_item!(id), do: Repo.get!(SuppliedContextItem, id)
  def get_item!(id), do: get_supplied_context_item!(id)

  @doc """
  Creates a supplied_context_item.

  ## Examples

      iex> create_supplied_context_item(%{field: value})
      {:ok, %SuppliedContextItem{}}

      iex> create_supplied_context_item(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_supplied_context_item(attrs) do
    %SuppliedContextItem{}
    |> SuppliedContextItem.changeset(attrs)
    |> Repo.insert()
    |> tap_success(&maybe_invalidate_prompt_cache/1)
  end

  def create_item(attrs), do: create_supplied_context_item(attrs)

  @doc """
  Updates a supplied_context_item.

  ## Examples

      iex> update_supplied_context_item(supplied_context_item, %{field: new_value})
      {:ok, %SuppliedContextItem{}}

      iex> update_supplied_context_item(supplied_context_item, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_supplied_context_item(%SuppliedContextItem{} = supplied_context_item, attrs) do
    supplied_context_item
    |> SuppliedContextItem.changeset(attrs)
    |> Repo.update()
    |> tap_success(&maybe_invalidate_prompt_cache/1)
  end

  def update_item(item, attrs), do: update_supplied_context_item(item, attrs)

  @doc """
  Deletes a supplied_context_item.

  ## Examples

      iex> delete_supplied_context_item(supplied_context_item)
      {:ok, %SuppliedContextItem{}}

      iex> delete_supplied_context_item(supplied_context_item)
      {:error, %Ecto.Changeset{}}

  """
  def delete_supplied_context_item(%SuppliedContextItem{} = supplied_context_item) do
    Repo.delete(supplied_context_item)
    |> tap_success(fn _ -> maybe_invalidate_prompt_cache(supplied_context_item) end)
  end

  def delete_item(item), do: delete_supplied_context_item(item)

  @doc """
  Bulk delete by id list.
  """
  def delete_items(ids) when is_list(ids) do
    import Ecto.Query
    result = Repo.delete_all(from i in SuppliedContextItem, where: i.id in ^ids)
    invalidate_prompt_cache()
    result
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking supplied_context_item changes.

  ## Examples

      iex> change_supplied_context_item(supplied_context_item)
      %Ecto.Changeset{data: %SuppliedContextItem{}}

  """
  def change_supplied_context_item(%SuppliedContextItem{} = supplied_context_item, attrs \\ %{}) do
    SuppliedContextItem.changeset(supplied_context_item, attrs)
  end

  @doc false
  def invalidate_prompt_cache do
    ensure_cache_table()
    :ets.delete_all_objects(@cache_table)
    :ok
  end

  defp fetch_system_prompts(provider_list, requested_provider, only_defaults?, group_by_family?) do
    query =
      from i in SuppliedContextItem,
        where: i.type == :system_prompt and i.provider in ^provider_list

    query = if only_defaults?, do: from(i in query, where: i.is_default == true), else: query

    items =
      query
      |> Repo.all()
      |> Enum.sort_by(&prompt_sort_key(&1, requested_provider))

    if group_by_family? do
      group_prompts_by_family(items, requested_provider)
    else
      items
    end
  end

  defp fetch_default_prompt(provider_list, requested_provider, name) do
    results =
      Repo.all(
        from i in SuppliedContextItem,
          where:
            i.type == :system_prompt and i.name == ^name and i.provider in ^provider_list and
              i.is_default == true,
          order_by: [desc: i.version]
      )

    case pick_preferred_prompt(results, requested_provider) do
      nil ->
        raise Ecto.NoResultsError,
          queryable: {SuppliedContextItem, %{provider: requested_provider, name: name}}

      prompt ->
        prompt
    end
  end

  defp providers_for(:all, include_shared?) do
    providers_for([:openai, :anthropic, :gemini], include_shared?)
  end

  defp providers_for(provider, true) when provider in [:openai, :anthropic, :gemini] do
    [provider, :shared]
  end

  defp providers_for(provider, false) when provider in [:openai, :anthropic, :gemini] do
    [provider]
  end

  defp providers_for(:shared, _include_shared), do: [:shared]

  defp providers_for(providers, include_shared?) when is_list(providers) do
    providers
    |> Enum.reduce([], fn provider, acc ->
      acc ++ providers_for(provider, include_shared?)
    end)
    |> Enum.uniq()
  end

  defp prompt_sort_key(%SuppliedContextItem{} = prompt, requested_provider) do
    provider_priority = provider_priority(prompt.provider, requested_provider)
    default_priority = if prompt.is_default, do: 0, else: 1
    position = prompt.position || 0

    {provider_priority, default_priority, position, -prompt.version, prompt.name, prompt.id}
  end

  defp provider_priority(provider, :all) do
    case provider do
      :openai -> 0
      :anthropic -> 1
      :gemini -> 2
      :shared -> 3
      _ -> 4
    end
  end

  defp provider_priority(provider, provider) when is_atom(provider), do: 0
  defp provider_priority(:shared, _requested), do: 1
  defp provider_priority(_other, _requested), do: 2

  defp group_prompts_by_family(items, requested_provider) do
    items
    |> Enum.group_by(& &1.family_id)
    |> Enum.map(fn {family_id, versions} ->
      sorted_versions =
        Enum.sort_by(versions, fn prompt -> {-prompt.version, prompt.inserted_at} end)

      default =
        pick_preferred_prompt(sorted_versions, requested_provider) || List.first(sorted_versions)

      %{
        family_id: family_id,
        default: default,
        versions: sorted_versions
      }
    end)
    |> Enum.sort_by(fn %{default: default} -> prompt_sort_key(default, requested_provider) end)
  end

  defp pick_preferred_prompt(prompts, requested_provider) do
    Enum.find(prompts, &(&1.provider == requested_provider)) ||
      Enum.find(prompts, &(&1.provider == :shared))
  end

  defp cache_fetch(key, fun) do
    ensure_cache_table()

    case :ets.lookup(@cache_table, key) do
      [{^key, %{value: value, at_ms: at_ms}}] ->
        if fresh_cache_entry?(at_ms) do
          value
        else
          compute_and_cache(key, fun)
        end

      _ ->
        compute_and_cache(key, fun)
    end
  end

  defp compute_and_cache(key, fun) do
    value = fun.()
    :ets.insert(@cache_table, {key, %{value: value, at_ms: now_ms()}})
    value
  end

  defp ensure_cache_table do
    case :ets.whereis(@cache_table) do
      :undefined ->
        try do
          :ets.new(@cache_table, [:named_table, :set, :public, read_concurrency: true])
          :ok
        rescue
          ArgumentError -> :ok
        end

      _ ->
        :ok
    end
  end

  defp fresh_cache_entry?(at_ms) when is_integer(at_ms) do
    now_ms() - at_ms < @cache_ttl_ms
  end

  defp fresh_cache_entry?(_), do: false

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp tap_success({:ok, result} = ok, fun) when is_function(fun, 1) do
    fun.(result)
    ok
  end

  defp tap_success(other, _fun), do: other

  defp maybe_invalidate_prompt_cache(%SuppliedContextItem{type: :system_prompt}),
    do: invalidate_prompt_cache()

  defp maybe_invalidate_prompt_cache(_), do: :ok
end
