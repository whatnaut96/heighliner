# TODO: Pattern matching on id fetches
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

           allegiance_id =
             case get_or_create_id(conn, "allegiances", event["SystemAllegiance"]) do
               {:error, reason} ->
                 Postgrex.rollback(conn, reason)

               id ->
                 id
             end

           primary_economy_id =
             case get_or_create_id(conn, "economy_types", event["SystemEconomy_Localised"]) do
               {:error, reason} -> Postgrex.rollback(conn, reason)
               id -> id
             end

           secondary_economy_id =
             case get_or_create_id(conn, "economy_types", event["SystemSecondEconomy_Localised"]) do
               {:error, reason} -> Postgrex.rollback(conn, reason)
               id -> id
             end

           government_id =
             case get_or_create_id(conn, "government_types", event["SystemGovernment_Localised"]) do
               {:error, reason} -> Postgrex.rollback(conn, reason)
               id -> id
             end

           body_type_id =
             case get_or_create_id(conn, "body_types", event["BodyType"]) do
               {:error, reason} -> Postgrex.rollback(conn, reason)
               id -> id
             end

           controlling_power_id =
             case get_or_create_id(conn, "powers", event["ControllingPower"]) do
               {:error, reason} -> Postgrex.rollback(conn, reason)
               id -> id
             end

           powerplay_state_id =
             case get_or_create_id(conn, "powerplay_states", event["PowerplayState"]) do
               {:error, reason} -> Postgrex.rollback(conn, reason)
               id -> id
             end

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

           power_ids =
             event["Powers"]
             |> Enum.map(fn power_name ->
               case get_or_create_id(conn, "powers", power_name) do
                 {:error, reason} -> Postgrex.rollback(conn, reason)
                 id -> id
               end
             end)

           powers_system_bridge_query = """
             INSERT INTO powers_system_bridge (power_id, system_id, last_updated)
             SELECT power_id, $2, $3 FROM UNNEST($1::int[]) as t(power_id)
             ON CONFLICT (power_id, system_id) DO UPDATE SET last_updated = EXCLUDED.last_updated
           """

           Postgrex.query(conn, powers_system_bridge_query, [
             power_ids,
             event["SystemAddress"],
             System.system_time(:millisecond)
           ])

           faction_insert_query = """
            INSERT INTO factions (
              government_id,
              happiness_id,
              allegiance_id,
              current_reputation,
              last_updated,
              name
            )
            SELECT * FROM UNNEST($1::int[], $2::int[], $3::int[], $4::float[], $5::bigint[], $6::text[])
            ON CONFLICT (name) DO UPDATE SET
              government_id = EXCLUDED.government_id,
              happiness_id = EXCLUDED.happiness_id,
              allegiance_id = EXCLUDED.allegiance_id,
              current_reputation = EXCLUDED.current_reputation,
              last_updated = EXCLUDED.last_updated
            RETURNING id
           """

           faction_state_insert_query = """
            INSERT INTO faction_state_bridge (
              faction_id,
              state_id,
              last_updated
            )
            SELECT faction_id, state_id, $3 FROM UNNEST($1::int[], $2::int[]) as t(faction_id, state_id)
            ON CONFLICT (faction_id) DO UPDATE SET
              state_id = EXCLUDED.state_id,
              last_updated = EXCLUDED.last_updated
           """

           faction_system_bridge_upsert_query = """
           WITH faction_data AS (
             SELECT faction_id, in_control
             FROM UNNEST($1::int[], $4::boolean[]) AS t(faction_id, in_control)
           ), updated AS (
             UPDATE faction_system_bridge AS bridge
             SET in_control = faction_data.in_control, last_updated = $3::bigint
             FROM faction_data
             WHERE bridge.faction_id = faction_data.faction_id AND bridge.system_id = $2::bigint
             RETURNING bridge.faction_id
           )
           INSERT INTO faction_system_bridge (faction_id, system_id, in_control, last_updated)
           SELECT faction_id, $2::bigint, in_control, $3::bigint
           FROM faction_data
           WHERE faction_id NOT IN (SELECT faction_id FROM updated)
           """

           if event["Factions"] != [] do
             prepared =
               Enum.map(event["Factions"], fn faction ->
                 gov_id = get_or_create_id(conn, "government_types", faction["Government"])

                 happy_id =
                   get_or_create_id(conn, "happiness_levels", faction["Happiness_Localised"])

                 alleg_id = get_or_create_id(conn, "allegiances", faction["Allegiance"])

                 state_name =
                   case Map.get(faction, "ActiveStates") do
                     [%{"State" => s} | _] when is_binary(s) and s != "" -> s
                     _ -> faction["FactionState"]
                   end

                 state_id = get_or_create_id(conn, "faction_states", state_name)

                 in_control = faction["Name"] == event["SystemFaction"]["Name"]

                 %{
                   gov_id: gov_id,
                   happy_id: happy_id,
                   alleg_id: alleg_id,
                   reputation: faction["MyReputation"] || 0.0,
                   name: faction["Name"],
                   state_id: state_id,
                   in_control: in_control
                 }
               end)

             %{rows: id_rows} =
               Postgrex.query!(
                 conn,
                 faction_insert_query,
                 [
                   Enum.map(prepared, & &1.gov_id),
                   Enum.map(prepared, & &1.happy_id),
                   Enum.map(prepared, & &1.alleg_id),
                   Enum.map(prepared, & &1.reputation),
                   List.duplicate(System.system_time(:millisecond), length(prepared)),
                   Enum.map(prepared, & &1.name)
                 ]
               )

             factions_with_ids =
               Enum.zip_with(prepared, id_rows, fn item, [faction_id] ->
                 Map.put(item, :faction_id, faction_id)
               end)

             faction_ids = Enum.map(factions_with_ids, & &1.faction_id)
             state_ids = Enum.map(factions_with_ids, & &1.state_id)
             in_controls = Enum.map(factions_with_ids, & &1.in_control)

             Postgrex.query!(conn, faction_state_insert_query, [
               faction_ids,
               state_ids,
               System.system_time(:millisecond)
             ])

             Postgrex.query!(
               conn,
               faction_system_bridge_upsert_query,
               [
                 faction_ids,
                 event["SystemAddress"],
                 System.system_time(:millisecond),
                 in_controls
               ]
             )
           end
         end) do
      {:ok, _result} ->
        :ok

      {:error, reason} ->
        Logger.error("route=stellartel Databse error: #{inspect(reason)}")
        :internal_error
    end
  end

  def handle_journal(:docked, event) do
    station_insert_query = """
    INSERT INTO stations (
      system_id,
      name,
      type_id,
      small_landing_pads,
      medium_landing_pads,
      large_landing_pads,
      government_type_id
    ) VALUES ($1::int, $2::text, $3::int, $4::int, $5::int, $6::int, $7::int)
    """

    case Postgrex.transaction(StellarTel.Postgres, fn conn ->
           station_type_id =
             case get_or_create_id(conn, "station_types", event["StationType"]) do
               {:error, reason} -> Postgrex.rollback(conn, reason)
               id -> id
             end

           government_type_id =
             case get_or_create_id(conn, "government_types", event["StationGovernment_Localised"]) do
               {:error, reason} -> Postgrex.rollback(conn, reason)
               id -> id
             end

           Postgrex.query!(
             conn,
             station_insert_query,
             [
               event["SystemAddress"],
               event["StationName"],
               station_type_id,
               event["LandingPads"]["Small"],
               event["LandingPads"]["Medium"],
               event["LandingPads"]["Large"],
               government_type_id
             ]
           )
         end) do
      {:ok, _result} ->
        :ok

      {:error, reason} ->
        Logger.error("route=stellartel Database error: #{inspect(reason)}")
        :internal_error
    end
  end

  def handle_journal(unknown_event_type, _event) do
    Logger.info("received an event that is not yet supported: #{unknown_event_type}")
    {:error, :event_type_not_supported}
  end

  defp get_or_create_id(pg_conn, table_name, value) do
    query =
      """
      WITH #{table_name}_ins as (
        INSERT INTO #{table_name} (name) VALUES ($1)
        ON CONFLICT (name) DO NOTHING
        RETURNING id
      ) SELECT ID from #{table_name}_ins UNION ALL
      SELECT id FROM #{table_name}
      WHERE name = $1;
      """

    case Postgrex.query(pg_conn, query, [value]) do
      {:ok, %Postgrex.Result{rows: [[id]]}} ->
        id

      {:error, reason} ->
        {:error, reason}
    end
  end
end
