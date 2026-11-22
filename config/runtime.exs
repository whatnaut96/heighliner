import Config
import Dotenvy

env_dir_prefix = System.get_env("RELEASE_ROOT") || Path.expand("./envs")

source!([
  Path.absname(".env", env_dir_prefix)
])

config :heighliner, :db_connections, %{
  stellartel: [
    hostname: env!("STELLARTEL_DB_HOST", :string!),
    username: env!("STELLARTEL_DB_USER", :string!),
    password: env!("STELLARTEL_DB_PASSWORD", :string!),
    database: env!("STELLARTEL_DB_DATABASE", :string!),
    port: env!("STELLARTEL_DB_PORT", :integer),
    pool_size: env!("STELLARTEL_DB_POOL_SIZE", :integer)
  ],
  synco: [
    hostname: env!("SYNCO_DB_HOST", :string!),
    username: env!("SYNCO_DB_USER", :string!),
    password: env!("SYNCO_DB_PASSWORD", :string!),
    database: env!("SYNCO_DB_DATABASE", :string!),
    port: env!("SYNCO_DB_PORT", :integer),
    pool_size: env!("SYNCO_DB_POOL_SIZE", :integer)
  ]
}

config :heighliner, :synco_path, env!("SYNCO_PAYLOAD_PATH")
