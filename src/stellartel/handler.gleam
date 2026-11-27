import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import gleam/time/timestamp
import pog
import utils/logging

pub type HandlerError {
  MalformedPayload
  EventTypeNotSupported
  InternalError
}

type JournalEvent {
  FsdJump(FsdJumpEvent)
  Docked(DockedEvent)
  Market(MarketEvent)
  Unsupported
}

type FsdJumpEvent {
  FsdJumpEvent(
    system_address: Int,
    star_system: String,
    star_position: #(Float, Float, Float),
    system_allegiance: String,
    primary_economy: String,
    secondary_economy: String,
    government: String,
    body_type: String,
    population: Int,
    controlling_power: String,
    powerplay_state: String,
    powers: List(String),
    factions: List(Faction),
    controlling_faction: String,
  )
}

type Faction {
  Faction(
    government: String,
    happiness: String,
    allegiance: String,
    reputation: Float,
    name: String,
    state: String,
  )
}

type DockedEvent {
  DockedEvent(
    system_address: Int,
    station_name: String,
    station_type: String,
    small_pads: Int,
    medium_pads: Int,
    large_pads: Int,
    government: String,
  )
}

type MarketEvent {
  MarketEvent(
    market_id: Int,
    station_name: String,
    star_system: String,
    items: List(MarketItem),
  )
}

type MarketItem {
  MarketItem(
    name: String,
    category: String,
    buy_price: Int,
    sell_price: Int,
    mean_price: Int,
    stock_bracket: Int,
    demand_bracket: Int,
    stock: Int,
    demand: Int,
    consumer: Bool,
    producer: Bool,
    rare: Bool,
  )
}

type PreparedFaction {
  PreparedFaction(
    government_id: Int,
    happiness_id: Int,
    allegiance_id: Int,
    reputation: Float,
    name: String,
    state_id: Int,
    in_control: Bool,
  )
}

type PreparedMarketItem {
  PreparedMarketItem(
    commodity_id: Int,
    buy_price: Int,
    sell_price: Int,
    mean_price: Int,
    stock_bracket: Int,
    demand_bracket: Int,
    stock: Int,
    demand: Int,
    consumer: Bool,
    producer: Bool,
    rare: Bool,
  )
}

type DatabaseFailure {
  QueryFailed(pog.QueryError)
  MissingStationOrControllingFaction
  MissingReturnedRow
}

const system_upsert_query = "
INSERT INTO systems (
  id, star_position, name, allegiance_id, primary_economy_id,
  secondary_economy_id, government_id, body_type_id, population,
  controlling_power_id, powerplay_state_id, conflicts, last_updated
) VALUES (
  $1::bigint, ST_SetSRID(ST_MakePoint($2, $3, $4), 0), $5::text,
  $6::int, $7::int, $8::int, $9::int, $10::int, $11::int,
  $12::int, $13::int, ($14::jsonb -> 'Conflicts'), $15::bigint
) ON CONFLICT (id) DO UPDATE SET
  allegiance_id = EXCLUDED.allegiance_id,
  primary_economy_id = EXCLUDED.primary_economy_id,
  secondary_economy_id = EXCLUDED.secondary_economy_id,
  government_id = EXCLUDED.government_id,
  population = EXCLUDED.population,
  controlling_power_id = EXCLUDED.controlling_power_id,
  powerplay_state_id = EXCLUDED.powerplay_state_id,
  conflicts = EXCLUDED.conflicts,
  last_updated = EXCLUDED.last_updated
"

const powers_system_bridge_query = "
INSERT INTO powers_system_bridge (power_id, system_id, last_updated)
SELECT power_id, $2, $3 FROM UNNEST($1::int[]) AS t(power_id)
ON CONFLICT (power_id, system_id) DO UPDATE SET
  last_updated = EXCLUDED.last_updated
"

const faction_insert_query = "
INSERT INTO factions (
  government_id, happiness_id, allegiance_id, current_reputation,
  last_updated, name
)
SELECT * FROM UNNEST(
  $1::int[], $2::int[], $3::int[], $4::float[], $5::bigint[], $6::text[]
)
ON CONFLICT (name) DO UPDATE SET
  government_id = EXCLUDED.government_id,
  happiness_id = EXCLUDED.happiness_id,
  allegiance_id = EXCLUDED.allegiance_id,
  current_reputation = EXCLUDED.current_reputation,
  last_updated = EXCLUDED.last_updated
RETURNING id
"

const faction_state_insert_query = "
INSERT INTO faction_state_bridge (faction_id, state_id, last_updated)
SELECT faction_id, state_id, $3
FROM UNNEST($1::int[], $2::int[]) AS t(faction_id, state_id)
ON CONFLICT (faction_id) DO UPDATE SET
  state_id = EXCLUDED.state_id,
  last_updated = EXCLUDED.last_updated
"

const faction_system_bridge_upsert_query = "
WITH faction_data AS (
  SELECT faction_id, in_control
  FROM UNNEST($1::int[], $4::boolean[]) AS t(faction_id, in_control)
), updated AS (
  UPDATE faction_system_bridge AS bridge
  SET in_control = faction_data.in_control, last_updated = $3::bigint
  FROM faction_data
  WHERE bridge.faction_id = faction_data.faction_id
    AND bridge.system_id = $2::bigint
  RETURNING bridge.faction_id
)
INSERT INTO faction_system_bridge (
  faction_id, system_id, in_control, last_updated
)
SELECT faction_id, $2::bigint, in_control, $3::bigint
FROM faction_data
WHERE faction_id NOT IN (SELECT faction_id FROM updated)
"

const station_insert_query = "
INSERT INTO stations (
  system_id, name, type_id, small_landing_pads, medium_landing_pads,
  large_landing_pads, government_type_id
) VALUES ($1::bigint, $2::text, $3::int, $4::int, $5::int, $6::int, $7::int)
"

const station_and_faction_query = "
SELECT stations.id, faction_system_bridge.faction_id
FROM stations
JOIN systems ON systems.id = stations.system_id
JOIN faction_system_bridge
  ON faction_system_bridge.system_id = systems.id
  AND faction_system_bridge.in_control = TRUE
WHERE stations.name = $1 AND systems.name = $2
ORDER BY faction_system_bridge.last_updated DESC
LIMIT 1
"

const station_market_upsert_query = "
INSERT INTO station_markets (
  id, station_id, commodity_id, faction_id, buy_price, sell_price,
  mean_price, stock_bracket, demand_bracket, stock, demand, consumer,
  producer, rare, last_updated
)
SELECT
  $1::bigint, $2::int, item.commodity_id, $3::int, item.buy_price,
  item.sell_price, item.mean_price, item.stock_bracket,
  item.demand_bracket, item.stock, item.demand, item.consumer,
  item.producer, item.rare, $15::bigint
FROM UNNEST(
  $4::int[], $5::int[], $6::int[], $7::int[], $8::int[], $9::int[],
  $10::int[], $11::int[], $12::boolean[], $13::boolean[], $14::boolean[]
) AS item(
  commodity_id, buy_price, sell_price, mean_price, stock_bracket,
  demand_bracket, stock, demand, consumer, producer, rare
)
ON CONFLICT (id, commodity_id) DO UPDATE SET
  station_id = EXCLUDED.station_id,
  faction_id = EXCLUDED.faction_id,
  buy_price = EXCLUDED.buy_price,
  sell_price = EXCLUDED.sell_price,
  mean_price = EXCLUDED.mean_price,
  stock_bracket = EXCLUDED.stock_bracket,
  demand_bracket = EXCLUDED.demand_bracket,
  stock = EXCLUDED.stock,
  demand = EXCLUDED.demand,
  consumer = EXCLUDED.consumer,
  producer = EXCLUDED.producer,
  rare = EXCLUDED.rare,
  last_updated = EXCLUDED.last_updated
"

pub fn handle_stellartel_request(
  body: String,
  connection: pog.Connection,
) -> Result(Nil, HandlerError) {
  case json.parse(body, journal_event_decoder()) {
    Error(_) -> Error(MalformedPayload)
    Ok(Unsupported) -> Error(EventTypeNotSupported)
    Ok(event) ->
      case event {
        FsdJump(event) ->
          run_transaction(connection, fn(transaction) {
            handle_fsd_jump(transaction, event, body)
          })
        Docked(event) ->
          run_transaction(connection, fn(transaction) {
            handle_docked(transaction, event)
          })
        Market(event) ->
          run_transaction(connection, fn(transaction) {
            handle_market(transaction, event)
          })
        Unsupported -> Error(EventTypeNotSupported)
      }
  }
}

pub fn handle_journal(
  body: String,
  connection: pog.Connection,
) -> Result(Nil, HandlerError) {
  handle_stellartel_request(body, connection)
}

fn run_transaction(
  connection: pog.Connection,
  callback: fn(pog.Connection) -> Result(Nil, DatabaseFailure),
) -> Result(Nil, HandlerError) {
  case pog.transaction(connection, callback) {
    Ok(Nil) -> Ok(Nil)
    Error(reason) -> {
      logging.error(
        "route=stellartel Database error: " <> string.inspect(reason),
      )
      Error(InternalError)
    }
  }
}

fn handle_fsd_jump(
  connection: pog.Connection,
  event: FsdJumpEvent,
  raw_json: String,
) -> Result(Nil, DatabaseFailure) {
  use allegiance_id <- result_try(get_or_create_id(
    connection,
    "allegiances",
    event.system_allegiance,
  ))
  use primary_economy_id <- result_try(get_or_create_id(
    connection,
    "economy_types",
    event.primary_economy,
  ))
  use secondary_economy_id <- result_try(get_or_create_id(
    connection,
    "economy_types",
    event.secondary_economy,
  ))
  use government_id <- result_try(get_or_create_id(
    connection,
    "government_types",
    event.government,
  ))
  use body_type_id <- result_try(get_or_create_id(
    connection,
    "body_types",
    event.body_type,
  ))
  use controlling_power_id <- result_try(get_or_create_id(
    connection,
    "powers",
    event.controlling_power,
  ))
  use powerplay_state_id <- result_try(get_or_create_id(
    connection,
    "powerplay_states",
    event.powerplay_state,
  ))

  let #(star_x, star_y, star_z) = event.star_position
  let now = unix_milliseconds()

  use _ <- result_try(
    pog.query(system_upsert_query)
    |> pog.parameter(pog.int(event.system_address))
    |> pog.parameter(pog.float(star_x))
    |> pog.parameter(pog.float(star_y))
    |> pog.parameter(pog.float(star_z))
    |> pog.parameter(pog.text(event.star_system))
    |> pog.parameter(pog.int(allegiance_id))
    |> pog.parameter(pog.int(primary_economy_id))
    |> pog.parameter(pog.int(secondary_economy_id))
    |> pog.parameter(pog.int(government_id))
    |> pog.parameter(pog.int(body_type_id))
    |> pog.parameter(pog.int(event.population))
    |> pog.parameter(pog.int(controlling_power_id))
    |> pog.parameter(pog.int(powerplay_state_id))
    |> pog.parameter(pog.text(raw_json))
    |> pog.parameter(pog.int(now))
    |> execute(connection),
  )

  use power_ids <- result_try(
    list.try_map(event.powers, fn(power_name) {
      get_or_create_id(connection, "powers", power_name)
    }),
  )

  use _ <- result_try(
    pog.query(powers_system_bridge_query)
    |> pog.parameter(pog.array(pog.int, power_ids))
    |> pog.parameter(pog.int(event.system_address))
    |> pog.parameter(pog.int(now))
    |> execute(connection),
  )

  case event.factions {
    [] -> Ok(Nil)
    factions -> handle_factions(connection, factions, event, now)
  }
}

fn handle_factions(
  connection: pog.Connection,
  factions: List(Faction),
  event: FsdJumpEvent,
  now: Int,
) -> Result(Nil, DatabaseFailure) {
  use prepared <- result_try(
    list.try_map(factions, fn(faction) {
      use government_id <- result_try(get_or_create_id(
        connection,
        "government_types",
        faction.government,
      ))
      use happiness_id <- result_try(get_or_create_id(
        connection,
        "happiness_levels",
        faction.happiness,
      ))
      use allegiance_id <- result_try(get_or_create_id(
        connection,
        "allegiances",
        faction.allegiance,
      ))
      use state_id <- result_try(get_or_create_id(
        connection,
        "faction_states",
        faction.state,
      ))

      Ok(PreparedFaction(
        government_id: government_id,
        happiness_id: happiness_id,
        allegiance_id: allegiance_id,
        reputation: faction.reputation,
        name: faction.name,
        state_id: state_id,
        in_control: faction.name == event.controlling_faction,
      ))
    }),
  )

  let id_decoder = decode.field(0, decode.int, decode.success)
  use faction_ids <- result_try(
    pog.query(faction_insert_query)
    |> pog.parameter(pog.array(
      pog.int,
      list.map(prepared, fn(v) { v.government_id }),
    ))
    |> pog.parameter(pog.array(
      pog.int,
      list.map(prepared, fn(v) { v.happiness_id }),
    ))
    |> pog.parameter(pog.array(
      pog.int,
      list.map(prepared, fn(v) { v.allegiance_id }),
    ))
    |> pog.parameter(pog.array(
      pog.float,
      list.map(prepared, fn(v) { v.reputation }),
    ))
    |> pog.parameter(pog.array(pog.int, list.map(prepared, fn(_) { now })))
    |> pog.parameter(pog.array(pog.text, list.map(prepared, fn(v) { v.name })))
    |> pog.returning(id_decoder)
    |> execute_rows(connection),
  )

  use _ <- result_try(
    pog.query(faction_state_insert_query)
    |> pog.parameter(pog.array(pog.int, faction_ids))
    |> pog.parameter(pog.array(
      pog.int,
      list.map(prepared, fn(v) { v.state_id }),
    ))
    |> pog.parameter(pog.int(now))
    |> execute(connection),
  )

  pog.query(faction_system_bridge_upsert_query)
  |> pog.parameter(pog.array(pog.int, faction_ids))
  |> pog.parameter(pog.int(event.system_address))
  |> pog.parameter(pog.int(now))
  |> pog.parameter(pog.array(
    pog.bool,
    list.map(prepared, fn(v) { v.in_control }),
  ))
  |> execute(connection)
}

fn handle_docked(
  connection: pog.Connection,
  event: DockedEvent,
) -> Result(Nil, DatabaseFailure) {
  use station_type_id <- result_try(get_or_create_id(
    connection,
    "station_types",
    event.station_type,
  ))
  use government_id <- result_try(get_or_create_id(
    connection,
    "government_types",
    event.government,
  ))

  pog.query(station_insert_query)
  |> pog.parameter(pog.int(event.system_address))
  |> pog.parameter(pog.text(event.station_name))
  |> pog.parameter(pog.int(station_type_id))
  |> pog.parameter(pog.int(event.small_pads))
  |> pog.parameter(pog.int(event.medium_pads))
  |> pog.parameter(pog.int(event.large_pads))
  |> pog.parameter(pog.int(government_id))
  |> execute(connection)
}

fn handle_market(
  connection: pog.Connection,
  event: MarketEvent,
) -> Result(Nil, DatabaseFailure) {
  let station_decoder = {
    use station_id <- decode.field(0, decode.int)
    use faction_id <- decode.field(1, decode.int)
    decode.success(#(station_id, faction_id))
  }

  use station_rows <- result_try(
    pog.query(station_and_faction_query)
    |> pog.parameter(pog.text(event.station_name))
    |> pog.parameter(pog.text(event.star_system))
    |> pog.returning(station_decoder)
    |> execute_rows(connection),
  )

  use station_and_faction <- result_try(case station_rows {
    [row] -> Ok(row)
    _ -> Error(MissingStationOrControllingFaction)
  })
  let #(station_id, faction_id) = station_and_faction

  let categories =
    event.items
    |> list.map(fn(item) { item.category })
    |> unique_strings

  use category_ids <- result_try(
    list.try_map(categories, fn(category) {
      use id <- result_try(get_or_create_id(
        connection,
        "commodity_categories",
        category,
      ))
      Ok(#(category, id))
    }),
  )

  use prepared <- result_try(
    list.try_map(event.items, fn(item) {
      use category_id <- result_try(
        case list.key_find(category_ids, item.category) {
          Ok(id) -> Ok(id)
          Error(_) -> Error(MissingReturnedRow)
        },
      )
      use commodity_id <- result_try(get_or_create_commodity_id(
        connection,
        item.name,
        category_id,
      ))

      Ok(PreparedMarketItem(
        commodity_id: commodity_id,
        buy_price: item.buy_price,
        sell_price: item.sell_price,
        mean_price: item.mean_price,
        stock_bracket: item.stock_bracket,
        demand_bracket: item.demand_bracket,
        stock: item.stock,
        demand: item.demand,
        consumer: item.consumer,
        producer: item.producer,
        rare: item.rare,
      ))
    }),
  )

  pog.query(station_market_upsert_query)
  |> pog.parameter(pog.int(event.market_id))
  |> pog.parameter(pog.int(station_id))
  |> pog.parameter(pog.int(faction_id))
  |> pog.parameter(pog.array(
    pog.int,
    list.map(prepared, fn(v) { v.commodity_id }),
  ))
  |> pog.parameter(pog.array(pog.int, list.map(prepared, fn(v) { v.buy_price })))
  |> pog.parameter(pog.array(
    pog.int,
    list.map(prepared, fn(v) { v.sell_price }),
  ))
  |> pog.parameter(pog.array(
    pog.int,
    list.map(prepared, fn(v) { v.mean_price }),
  ))
  |> pog.parameter(pog.array(
    pog.int,
    list.map(prepared, fn(v) { v.stock_bracket }),
  ))
  |> pog.parameter(pog.array(
    pog.int,
    list.map(prepared, fn(v) { v.demand_bracket }),
  ))
  |> pog.parameter(pog.array(pog.int, list.map(prepared, fn(v) { v.stock })))
  |> pog.parameter(pog.array(pog.int, list.map(prepared, fn(v) { v.demand })))
  |> pog.parameter(pog.array(pog.bool, list.map(prepared, fn(v) { v.consumer })))
  |> pog.parameter(pog.array(pog.bool, list.map(prepared, fn(v) { v.producer })))
  |> pog.parameter(pog.array(pog.bool, list.map(prepared, fn(v) { v.rare })))
  |> pog.parameter(pog.int(unix_milliseconds()))
  |> execute(connection)
}

fn get_or_create_id(
  connection: pog.Connection,
  table_name: String,
  value: String,
) -> Result(Int, DatabaseFailure) {
  let query =
    "WITH "
    <> table_name
    <> "_ins AS (INSERT INTO "
    <> table_name
    <> " (name) VALUES ($1) ON CONFLICT (name) DO NOTHING RETURNING id) "
    <> "SELECT id FROM "
    <> table_name
    <> "_ins UNION ALL SELECT id FROM "
    <> table_name
    <> " WHERE name = $1"

  let id_decoder = decode.field(0, decode.int, decode.success)
  case
    pog.query(query)
    |> pog.parameter(pog.text(value))
    |> pog.returning(id_decoder)
    |> pog.execute(connection)
  {
    Ok(pog.Returned(_, [id])) -> Ok(id)
    Ok(_) -> Error(MissingReturnedRow)
    Error(error) -> Error(QueryFailed(error))
  }
}

fn get_or_create_commodity_id(
  connection: pog.Connection,
  name: String,
  category_id: Int,
) -> Result(Int, DatabaseFailure) {
  let id_decoder = decode.field(0, decode.int, decode.success)
  case
    pog.query(
      "INSERT INTO commodities (name, category_id) VALUES ($1, $2) ON CONFLICT (name) DO UPDATE SET category_id = EXCLUDED.category_id RETURNING id",
    )
    |> pog.parameter(pog.text(name))
    |> pog.parameter(pog.int(category_id))
    |> pog.returning(id_decoder)
    |> pog.execute(connection)
  {
    Ok(pog.Returned(_, [id])) -> Ok(id)
    Ok(_) -> Error(MissingReturnedRow)
    Error(error) -> Error(QueryFailed(error))
  }
}

fn execute(
  query: pog.Query(Nil),
  connection: pog.Connection,
) -> Result(Nil, DatabaseFailure) {
  case pog.execute(query, connection) {
    Ok(_) -> Ok(Nil)
    Error(error) -> Error(QueryFailed(error))
  }
}

fn execute_rows(
  query: pog.Query(a),
  connection: pog.Connection,
) -> Result(List(a), DatabaseFailure) {
  case pog.execute(query, connection) {
    Ok(pog.Returned(_, rows)) -> Ok(rows)
    Error(error) -> Error(QueryFailed(error))
  }
}

fn result_try(
  result: Result(a, e),
  next: fn(a) -> Result(b, e),
) -> Result(b, e) {
  case result {
    Ok(value) -> next(value)
    Error(error) -> Error(error)
  }
}

fn unique_strings(values: List(String)) -> List(String) {
  list.fold(values, [], fn(unique, value) {
    case list.contains(unique, value) {
      True -> unique
      False -> [value, ..unique]
    }
  })
}

fn unix_milliseconds() -> Int {
  let #(seconds, nanoseconds) =
    timestamp.system_time()
    |> timestamp.to_unix_seconds_and_nanoseconds
  seconds * 1000 + nanoseconds / 1_000_000
}

fn journal_event_decoder() -> decode.Decoder(JournalEvent) {
  use event_type <- decode.field("event", decode.string)
  case string.lowercase(event_type) {
    "fsdjump" -> decode.map(fsd_jump_decoder(), FsdJump)
    "docked" -> decode.map(docked_decoder(), Docked)
    "market" -> decode.map(market_decoder(), Market)
    _ -> decode.success(Unsupported)
  }
}

fn fsd_jump_decoder() -> decode.Decoder(FsdJumpEvent) {
  use system_address <- decode.field("SystemAddress", decode.int)
  use star_system <- decode.field("StarSystem", decode.string)
  use star_position <- decode.field("StarPos", star_position_decoder())
  use system_allegiance <- decode.field("SystemAllegiance", decode.string)
  use primary_economy <- decode.field("SystemEconomy_Localised", decode.string)
  use secondary_economy <- decode.field(
    "SystemSecondEconomy_Localised",
    decode.string,
  )
  use government <- decode.field("SystemGovernment_Localised", decode.string)
  use body_type <- decode.field("BodyType", decode.string)
  use population <- decode.field("Population", decode.int)
  use controlling_power <- decode.field("ControllingPower", decode.string)
  use powerplay_state <- decode.field("PowerplayState", decode.string)
  use powers <- decode.field("Powers", decode.list(decode.string))
  use factions <- decode.field("Factions", decode.list(faction_decoder()))
  use controlling_faction <- decode.subfield(
    ["SystemFaction", "Name"],
    decode.string,
  )
  decode.success(FsdJumpEvent(
    system_address: system_address,
    star_system: star_system,
    star_position: star_position,
    system_allegiance: system_allegiance,
    primary_economy: primary_economy,
    secondary_economy: secondary_economy,
    government: government,
    body_type: body_type,
    population: population,
    controlling_power: controlling_power,
    powerplay_state: powerplay_state,
    powers: powers,
    factions: factions,
    controlling_faction: controlling_faction,
  ))
}

fn faction_decoder() -> decode.Decoder(Faction) {
  use government <- decode.field("Government", decode.string)
  use happiness <- decode.field("Happiness_Localised", decode.string)
  use allegiance <- decode.field("Allegiance", decode.string)
  use reputation <- decode.optional_field(
    "MyReputation",
    0.0,
    numeric_decoder(),
  )
  use name <- decode.field("Name", decode.string)
  use faction_state <- decode.field("FactionState", decode.string)
  use active_states <- decode.optional_field(
    "ActiveStates",
    [],
    decode.list(active_state_decoder()),
  )
  let state = case active_states {
    [state, ..] if state != "" -> state
    _ -> faction_state
  }
  decode.success(Faction(
    government: government,
    happiness: happiness,
    allegiance: allegiance,
    reputation: reputation,
    name: name,
    state: state,
  ))
}

fn active_state_decoder() -> decode.Decoder(String) {
  decode.field("State", decode.string, decode.success)
}

fn docked_decoder() -> decode.Decoder(DockedEvent) {
  use system_address <- decode.field("SystemAddress", decode.int)
  use station_name <- decode.field("StationName", decode.string)
  use station_type <- decode.field("StationType", decode.string)
  use small_pads <- decode.subfield(["LandingPads", "Small"], decode.int)
  use medium_pads <- decode.subfield(["LandingPads", "Medium"], decode.int)
  use large_pads <- decode.subfield(["LandingPads", "Large"], decode.int)
  use government <- decode.field("StationGovernment_Localised", decode.string)
  decode.success(DockedEvent(
    system_address: system_address,
    station_name: station_name,
    station_type: station_type,
    small_pads: small_pads,
    medium_pads: medium_pads,
    large_pads: large_pads,
    government: government,
  ))
}

fn market_decoder() -> decode.Decoder(MarketEvent) {
  use market_id <- decode.field("MarketID", decode.int)
  use station_name <- decode.field("StationName", decode.string)
  use star_system <- decode.field("StarSystem", decode.string)
  use items <- decode.field("Items", decode.list(market_item_decoder()))
  decode.success(MarketEvent(
    market_id: market_id,
    station_name: station_name,
    star_system: star_system,
    items: items,
  ))
}

fn market_item_decoder() -> decode.Decoder(MarketItem) {
  use name <- decode.field("Name_Localised", decode.string)
  use category <- decode.field("Category_Localised", decode.string)
  use buy_price <- decode.field("BuyPrice", decode.int)
  use sell_price <- decode.field("SellPrice", decode.int)
  use mean_price <- decode.field("MeanPrice", decode.int)
  use stock_bracket <- decode.field("StockBracket", decode.int)
  use demand_bracket <- decode.field("DemandBracket", decode.int)
  use stock <- decode.field("Stock", decode.int)
  use demand <- decode.field("Demand", decode.int)
  use consumer <- decode.field("Consumer", decode.bool)
  use producer <- decode.field("Producer", decode.bool)
  use rare <- decode.field("Rare", decode.bool)
  decode.success(MarketItem(
    name: name,
    category: category,
    buy_price: buy_price,
    sell_price: sell_price,
    mean_price: mean_price,
    stock_bracket: stock_bracket,
    demand_bracket: demand_bracket,
    stock: stock,
    demand: demand,
    consumer: consumer,
    producer: producer,
    rare: rare,
  ))
}

fn star_position_decoder() -> decode.Decoder(#(Float, Float, Float)) {
  use values <- decode.then(decode.list(numeric_decoder()))
  case values {
    [x, y, z] -> decode.success(#(x, y, z))
    _ -> decode.failure(#(0.0, 0.0, 0.0), "three coordinates")
  }
}

fn numeric_decoder() -> decode.Decoder(Float) {
  decode.one_of(decode.float, [decode.map(decode.int, int.to_float)])
}
