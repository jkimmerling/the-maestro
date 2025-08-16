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

  pipeline :oauth do
    plug :accepts, ["html"]
    plug :fetch_query_params
  end

  scope "/", TheMaestroWeb do
    pipe_through :browser

    live "/", HomeLive, :index
  end

  # Authentication routes
  scope "/auth", TheMaestroWeb do
    pipe_through :browser

    get "/logout", AuthController, :logout
    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  # Main application routes
  scope "/", TheMaestroWeb do
    pipe_through :browser

    live "/setup", ProviderSelectionLive, :index
    live "/agent", AgentLive, :index
    get "/start_chat", SessionController, :start_chat
    post "/start_chat", SessionController, :start_chat
  end

  # OAuth callback endpoint (separate pipeline to avoid CSRF protection)
  scope "/", TheMaestroWeb do
    pipe_through :oauth

    get "/oauth2callback", OAuthController, :callback
  end

  # Provider API Routes
  scope "/api", TheMaestroWeb do
    pipe_through :api

    get "/providers", ProvidersController, :index
    post "/providers/:provider/auth", ProvidersController, :auth
    post "/providers/:provider/complete_device_flow", ProvidersController, :complete_device_flow
    get "/providers/:provider/models", ProvidersController, :models
    post "/providers/:provider/test", ProvidersController, :test
  end

  # CLI Authentication API Routes
  scope "/api/cli/auth", TheMaestroWeb do
    pipe_through :api

    post "/device", CliAuthController, :device
    get "/poll", CliAuthController, :poll
  end

  # CLI Authentication Browser Routes (need sessions and HTML)
  scope "/api/cli/auth", TheMaestroWeb do
    pipe_through :browser

    get "/authorize", CliAuthController, :authorize
    post "/authorize", CliAuthController, :authorize_post
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
