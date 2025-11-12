defmodule MimimiWeb.Router do
  use MimimiWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MimimiWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug MimimiWeb.Plugs.UserSession
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", MimimiWeb do
    pipe_through :browser

    live_session :default, on_mount: MimimiWeb.ActiveGamesHook do
      live "/", HomeLive.Index, :index
      live "/choose-avatar/:invitation_id", AvatarLive.Choose, :choose
      live "/dashboard/:id", DashboardLive.Show, :show
      live "/games/:id/current", GameLive.Play, :play
    end
  end

  # Health check endpoint for deployment verification
  scope "/", MimimiWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  # Other scopes may use custom stacks.
  # scope "/api", MimimiWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:mimimi, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MimimiWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
