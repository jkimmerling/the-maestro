#!/usr/bin/env elixir
# Runs the backend agent loop against an Anthropic OAuth session to validate tool turns.

Application.ensure_all_started(:logger)
Application.ensure_all_started(:finch)

alias TheMaestro.AgentLoop

session = System.get_env("ANTHROPIC_OAUTH_SESSION") || "personal_oauth_claude"
model = System.get_env("ANTHROPIC_MODEL") || "claude-3-5-sonnet-20241022"

prompt = "Use the shell tool to run ['bash','-lc','echo external-ok'] and then answer 'done'."
messages = [%{"role" => "user", "content" => prompt}]

IO.puts("Running Anthropic AgentLoop with session=#{session} model=#{model} ...")

case AgentLoop.run_turn(:anthropic, session, model, messages, []) do
  {:ok, res} ->
    IO.puts("tools: " <> inspect(res.tools))
    IO.puts("final_text: \n" <> (res.final_text || ""))
    IO.puts("usage: " <> inspect(res.usage))
  {:error, reason} ->
    IO.puts("ERROR: " <> inspect(reason))
end
