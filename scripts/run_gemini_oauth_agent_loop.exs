#!/usr/bin/env elixir
# Runs the backend agent loop against a Gemini OAuth session to validate streaming.

Application.ensure_all_started(:logger)
Application.ensure_all_started(:finch)

# If running with `mix run --no-start`, the application tree (including Oban)
# is not started. Manually start only what we need: the Ecto repo.
_ = Application.ensure_all_started(:ecto_sql)
case Process.whereis(TheMaestro.Repo) do
  nil ->
    {:ok, _} = TheMaestro.Repo.start_link()
  _pid -> :ok
end

# Ensure named Finch pools used by providers are running
finch_pools = Application.get_env(:the_maestro, :finch_pools, [])

start_pool = fn name, cfg, default_url ->
  case Process.whereis(name) do
    nil ->
      pool_cfg = (cfg || []) |> Keyword.get(:pool_config, [size: 5, count: 1])
      base_url = (cfg || []) |> Keyword.get(:base_url, default_url)
      {:ok, _} = Finch.start_link(name: name, pools: %{base_url => pool_cfg})
    _pid -> :ok
  end
end

start_pool.(:anthropic_finch, finch_pools[:anthropic], "https://api.anthropic.com")
start_pool.(:openai_finch, finch_pools[:openai], "https://api.openai.com")
start_pool.(:gemini_finch, finch_pools[:gemini], "https://generativelanguage.googleapis.com")

alias TheMaestro.AgentLoop

session = System.get_env("GEMINI_OAUTH_SESSION") || "personal_oauth_gemini"
model = System.get_env("GEMINI_MODEL") || "gemini-2.5-pro"

# Adjusted prompt to exercise tool use. The Gemini provider now
# advertises basic tools and supports follow-up with functionResponse.
prompt = "List the files in your current working directory. If tools are available, use them to execute the listing."
messages = [%{"role" => "user", "content" => prompt}]

IO.puts("Running Gemini AgentLoop with session=#{session} model=#{model} ...")

case AgentLoop.run_turn(:gemini, session, model, messages) do
  {:ok, res} ->
    IO.puts("tools: " <> inspect(res.tools))
    IO.puts("final_text: \n" <> (res.final_text || ""))
    IO.puts("usage: " <> inspect(res.usage))
  {:error, reason} ->
    IO.puts("ERROR: " <> inspect(reason))
end
