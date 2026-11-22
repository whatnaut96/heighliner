defmodule Heighliner.Application do
  use Application

  @impl true
  def start(_type, _args) do
    db_configs = Application.get_env(:heighliner, :db_connections, %{})

    children = [
      Supervisor.child_spec(
        {Postgrex, Keyword.put(db_configs[:stellartel], :name, StellarTel.Postgres)},
        id: StellarTel.Postgres
      ),
      # Supervisor.child_spec({Postgrex, Keyword.put(db_configs[:synco], :name, Synco.Postgres)},
      #   id: Synco.Postgres
      # ),
      Supervisor.child_spec({Bandit, plug: Heighliner.Plug, port: 10191}, id: BanditServer)
    ]

    opts = [strategy: :one_for_one, name: Heighliner.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
