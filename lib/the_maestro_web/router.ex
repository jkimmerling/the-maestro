defmodule TheMaestroWeb.Router do
  use TheMaestroWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TheMaestroWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :api_auth do
    plug TheMaestroWeb.ApiAuthPlug
  end

  scope "/", TheMaestroWeb do
    pipe_through :browser
    live "/", DashboardLive, :index
    live "/dashboard", DashboardLive, :index
    live "/chat_history", ChatEntryLive.Index, :index
    live "/chat_history/new", ChatEntryLive.Form, :new
    live "/chat_history/:id", ChatEntryLive.Show, :show
    live "/chat_history/:id/edit", ChatEntryLive.Form, :edit
    live "/auths/new", AuthNewLive, :new
    live "/auths/:id", AuthShowLive, :show
    live "/auths/:id/edit", AuthEditLive, :edit
    # SuppliedContext CRUD routes
    live "/supplied_context", SuppliedContextItemLive.Index, :index
    live "/supplied_context/new", SuppliedContextItemLive.Form, :new
    live "/supplied_context/:id", SuppliedContextItemLive.Show, :show
    live "/supplied_context/:id/edit", SuppliedContextItemLive.Form, :edit

    # MCP Hub
    live "/mcp/servers", MCPServersLive.Index, :index
    live "/mcp/servers/new", MCPServersLive.Index, :new
    live "/mcp/servers/import", MCPServersLive.Index, :import
    live "/mcp/servers/:id/edit", MCPServersLive.Index, :edit
    live "/mcp/servers/:id", MCPServersLive.Show, :show

    # Agents routes removed after session-centric cleanup

    # Sessions LiveViews
    live "/sessions/:id/chat", SessionChatLive, :chat
    # live "/sessions/:id/edit", SessionEditLive, :edit  # Now handled by modal in dashboard

    # API Keys management
    live "/api_keys", ApiKeyLive.Index, :index
    live "/api_keys/new", ApiKeyLive.Form, :new
    live "/api_keys/:id", ApiKeyLive.Show, :show
    live "/api_keys/:id/edit", ApiKeyLive.Form, :edit
  end

  # Other scopes may use custom stacks.
  # Generated controllers for Sessions (HTML CRUD)
  scope "/the_maestro_web", TheMaestroWeb.TheMaestroWeb do
    pipe_through :browser
    resources "/sessions", SessionController
  end

  scope "/api", TheMaestroWeb do
    pipe_through :api

    post "/oauth/openai/callback", OAuthController, :openai_callback
    post "/oauth/anthropic/callback", OAuthController, :anthropic_callback
    post "/oauth/gemini/callback", OAuthController, :gemini_callback
    post "/sessions/:id/turn", ChatController, :create
  end

  scope "/api", TheMaestroWeb.Api do
    pipe_through [:api, :api_auth]

    get "/providers", ProvidersController, :index
    get "/providers/:provider/saved_auths", ProvidersController, :saved_auths
    get "/providers/:_provider/saved_auths/:auth_id/models", ProvidersController, :models

    get "/sessions", SessionsController, :index
    post "/sessions", SessionsController, :create
    patch "/sessions/:id", SessionsController, :update
    delete "/sessions/:id", SessionsController, :delete
    post "/sessions/:session_id/turns", TurnsController, :create

    # SSE frames for a specific turn
    get "/sessions/:session_id/turns/:stream_id/frames", FramesController, :sse

    # Latest frames for a thread (polling fallback)
    get "/threads/:thread_id/turns/latest/frames", FramesController, :latest
    get "/threads/:thread_id/snapshot", FramesController, :snapshot

    # Tool results from remote clients (TUI)
    post "/sessions/:session_id/turns/:stream_id/tools/results", ToolResultsController, :create

    # Thread maintenance
    get "/sessions/:session_id/threads", ThreadsController, :index
    post "/sessions/:session_id/threads", ThreadsController, :create
    patch "/threads/:thread_id", ThreadsController, :update
    post "/threads/:thread_id/clear", ThreadsController, :clear
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:the_maestro, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TheMaestroWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
