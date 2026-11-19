defmodule Heighliner.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    db_configs = Application.get_env(:heighliner, :db_connections, %{})

    children = [
      {Postgrex, Keyword.put(db_configs[:stellartel], :name, StellarTel.Postgres)},
      {Bandit, plug: Heighliner.Plug, port: 10191}
    ]

    opts = [strategy: :one_for_one, name: Heighliner.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
