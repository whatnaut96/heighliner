defmodule StellarTel.Handler do
  require Logger

  def handle_journal(:fsdjump, event) do
    case Postgrex.transaction(StellarTel.Postgres, fn conn ->
           system_upsert_query = """
             INSERT INTO systems values (
               $1,
               ST_SetSRID(ST_MakePoint($2, $3, $4), 0),
               $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15
             ) ON CONFLICT (id)
               DO UPDATE SET
                id = EXCLUDED.id,
                allegiance_id = EXCLUDED.allegiance_id,
                primary_economy_id = EXCLUDED.primary_economy_id,
                secondary_economy_id = EXCLUDED.secondary_economy_id,
                government_id = EXCLUDED.government_id,
                population = EXCLUDED.population,
                controlling_power_id = EXCLUDED.controlling_power_id,
                power_play_state_id = EXCLUDED.power_play_state_id,
                conflicts = EXCLUDED.conflicts,
                last_updated = EXCLUDED.last_updated
           """

           allegiance_id = get_or_create_id(conn, "allegiances", event["SystemAllegiance"])

           primary_economy_id =
             get_or_create_id(conn, "economy_types", event["SystemEconomy_Localised"])

           secondary_economy_id =
             get_or_create_id(conn, "economy_types", event["SystemSecondEconomy_Localised"])

           government_id =
             get_or_create_id(conn, "government_types", event["SystemGovernment_Localised"])

           body_type_id = get_or_create_id(conn, "body_types", event["BodyType"])

           controlling_power_id = get_or_create_id(conn, "powers", event["ControllingPower"])

           powerplay_state_id =
             get_or_create_id(conn, "powerplay_states", event["PowerplayState"])

           [star_pos_x, star_pos_y, star_pos_z] = event["StarPos"]

           Postgrex.query!(
             conn,
             system_upsert_query,
             [
               event["SystemAddress"],
               star_pos_x,
               star_pos_y,
               star_pos_z,
               event["Body"],
               allegiance_id,
               primary_economy_id,
               secondary_economy_id,
               government_id,
               body_type_id,
               event["Population"],
               controlling_power_id,
               powerplay_state_id,
               JSON.encode!(event["Conflicts"]),
               System.system_time(:millisecond)
             ]
           )
         end) do
      {:ok, _result} ->
        :ok

      {:error, reason} ->
        Logger.error("route=stellartel Databse error: #{inspect(reason)}")
        :internal_error
    end
  end

  def handle_journal(unknown_event_type, _event) do
    Logger.info("received an event that is not yet supported: #{unknown_event_type}")
    {:error, :event_type_not_supported}
  end

  def get_or_create_id(pg_conn, table_name, value) do
    query =
      "INSERT INTO #{table_name} (name) VALUES ($1) ON CONFLICT (name) DO NOTHING RETURNING id"

    case Postgrex.query(pg_conn, query, [value]) do
      {:ok, %Postgrex.Result{rows: [[id]]}} ->
        id

      {:error, reason} ->
        Logger.error("route=stellartel Could not get id from #{table_name}: #{reason}")
        {:error, reason}
    end
  end
end
