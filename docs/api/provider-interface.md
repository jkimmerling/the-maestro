# Universal Provider Interface

Examples:

```elixir
# Create OAuth session (OpenAI)
{:ok, session} = TheMaestro.Provider.create_session(:openai, :oauth,
  name: "work_openai",
  auth_code: "...",
  pkce_params: %TheMaestro.Auth.PKCEParams{code_verifier: "...", code_challenge: "..."}
)

# List models
{:ok, models} = TheMaestro.Provider.list_models(:openai, :oauth, session)

# Stream chat
{:ok, stream} = TheMaestro.Provider.stream_chat(:openai, session, [%{"role" => "user", "content" => "Hi"}], model: "gpt-4o")

for msg <- TheMaestro.Streaming.parse_stream(stream, :openai) do
  if msg.type == :content, do: IO.write(msg.content)
end
```

See also: `docs/architecture/provider-architecture.md`.

