# TheMaestro

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Gemini OAuth (Optional Local Callback)

You can complete Gemini OAuth locally via an optional endpoint. This does not change other providers and is safe to leave unused.

- Generate URL with PKCE:
  - `iex -S mix`
  - `{:ok, {auth_url, pkce}} = TheMaestro.Auth.generate_gemini_oauth_url()`
  - Open `auth_url` and sign in.

- Local callback (optional):
  - Configure Google redirect: `http://localhost:4000/api/oauth/gemini/callback`
  - The callback accepts `code` (and `state`); `state` is used as PKCE verifier if present.

- Manual finish (without callback):
  - Copy the `code` and run: `{:ok, _} = TheMaestro.Auth.finish_gemini_oauth("AUTH_CODE", pkce, "personal_gemini_oauth")`

- Stream via universal interface:
  - `mix run scripts/e2e_dual_prompt_stream_test.exs gemini personal_gemini_oauth`

API key alternative:
- Export `GOOGLE_API_KEY` (or `GEMINI_API_KEY`) in your shell
- Or create a named session:
  - `TheMaestro.Provider.create_session(:gemini, :api_key, name: "personal_gemini", credentials: %{api_key: System.get_env("GOOGLE_API_KEY")})`

Helper script for headless OAuth:

- Start flow and persist PKCE locally:
  - `mix run scripts/gemini_oauth_cli_helper.exs start personal_gemini_oauth`
  - Open URL printed by the script

- Finish with code (no server needed):
  - `mix run scripts/gemini_oauth_cli_helper.exs finish personal_gemini_oauth AUTH_CODE`

- Or send code to local callback via curl:
  - `mix run scripts/gemini_oauth_cli_helper.exs curl personal_gemini_oauth` (prints command)

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
