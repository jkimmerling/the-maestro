#!/usr/bin/env elixir
# Runs the backend agent loop against a ChatGPT OAuth session to validate tool turns.

Application.ensure_all_started(:logger)
Application.ensure_all_started(:finch)

alias TheMaestro.AgentLoop

session = System.get_env("OPENAI_OAUTH_SESSION") || "ChatGPTAgent"
model = System.get_env("OPENAI_MODEL") || "gpt-5"

prompt = "Use the shell tool to run ['bash','-lc','echo external-ok'] and then answer 'done'."
messages = [%{"role" => "user", "content" => prompt}]

IO.puts("Running AgentLoop with session=#{session} model=#{model} ...")

case AgentLoop.run_turn(:openai, session, model, messages) do
  {:ok, res} ->
    IO.puts("tools: " <> inspect(res.tools))
    IO.puts("final_text: \n" <> (res.final_text || ""))
    IO.puts("usage: " <> inspect(res.usage))
  {:error, reason} ->
    IO.puts("ERROR: " <> inspect(reason))
end

