defmodule BracketBattle.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BracketBattleWeb.Telemetry,
      BracketBattle.Repo,
      {DNSCluster, query: Application.get_env(:bracket_battle, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: BracketBattle.PubSub},
      # Oban for background jobs
      {Oban, Application.fetch_env!(:bracket_battle, Oban)},
      # Start to serve requests, typically the last entry
      BracketBattleWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BracketBattle.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BracketBattleWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
