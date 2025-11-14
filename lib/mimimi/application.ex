defmodule Mimimi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Enable hot code upgrades before starting supervision tree
    Mimimi.HotDeploy.startup_reapply_current()

    children = [
      MimimiWeb.Telemetry,
      Mimimi.Repo,
      Mimimi.WortSchuleRepo,
      {DNSCluster, query: Application.get_env(:mimimi, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Mimimi.PubSub},
      # Start a worker by calling: Mimimi.Worker.start_link(arg)
      # {Mimimi.Worker, arg},
      # Start to serve requests, typically the last entry
      MimimiWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Mimimi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MimimiWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
