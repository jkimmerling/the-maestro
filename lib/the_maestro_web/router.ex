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

  scope "/", TheMaestroWeb do
    pipe_through :browser
    live "/", DashboardLive, :index
    live "/dashboard", DashboardLive, :index
    live "/auths/new", AuthNewLive, :new
    live "/auths/:id", AuthShowLive, :show
    live "/auths/:id/edit", AuthEditLive, :edit
    # SuppliedContext CRUD routes
    live "/supplied_context", SuppliedContextItemLive.Index, :index
    live "/supplied_context/new", SuppliedContextItemLive.Form, :new
    live "/supplied_context/:id", SuppliedContextItemLive.Show, :show
    live "/supplied_context/:id/edit", SuppliedContextItemLive.Form, :edit

    # Agents routes removed after session-centric cleanup

    # Sessions LiveViews
    live "/sessions/:id/chat", SessionChatLive, :chat
    live "/sessions/:id/edit", SessionEditLive, :edit
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
