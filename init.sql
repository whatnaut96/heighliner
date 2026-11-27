create database stellartel;
create database synco;
\connect stellartel

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE TABLE allegiances(
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
);

CREATE TABLE economy_types(
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
);

CREATE TABLE government_types(
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
);

CREATE TABLE security_levels(
    id SERIAL PRIMARY KEY,
    level TEXT NOT NULL
);

CREATE TABLE body_types(
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
);

CREATE TABLE powers (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    allegiance_id INT REFERENCES allegiances(id)
);

CREATE TABLE powerplay_states(
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
);

CREATE TABLE faction_states (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
);

INSERT INTO faction_states (name) VALUES ('None');

CREATE TABLE happiness_levels(
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
);

CREATE TABLE factions (
    id SERIAL PRIMARY KEY,
    government_id INT NOT NULL REFERENCES government_types(id),
    happiness_id INT NOT NULL REFERENCES happiness_levels(id),
    allegiance_id INT NOT NULL REFERENCES allegiances(id),
    current_reputation FLOAT NOT NULL,
    last_updated bigint NOT NULL,
    name TEXT UNIQUE NOT NULL
);


CREATE TABLE faction_state_bridge(
    id SERIAL PRIMARY KEY,
    faction_id INT UNIQUE REFERENCES factions(id),
    state_id INT REFERENCES faction_states(id),
    last_updated bigint NOT NULL
);


CREATE TABLE systems (
    id BIGINT PRIMARY KEY,
    star_position geometry(POINTZ, 0) not null,
    name TEXT UNIQUE NOT NULL,
    allegiance_id INT NOT NULL REFERENCES allegiances(id),
    primary_economy_id INT NOT NULL REFERENCES economy_types(id),
    secondary_economy_id INT NOT NULL REFERENCES economy_types(id),
    government_id INT NOT NULL REFERENCES government_types(id),
    body_type_id INT NOT NULL REFERENCES body_types(id),
    population INT NOT NULL,
    controlling_power_id INT NOT NULL REFERENCES powers(id),
    powerplay_state_id INT NOT NULL REFERENCES powerplay_states(id),
    conflicts jsonb NOT NULL,
    last_updated bigint NOT NULL,
    UNIQUE(id, name)
);

CREATE TABLE powers_system_bridge(
    id SERIAL PRIMARY KEY,
    power_id INT REFERENCES powers(id),
    system_id BIGINT REFERENCES systems(id),
    last_updated bigint NOT NULL,
    UNIQUE(power_id, system_id)
);

CREATE TABLE commodity_categories(
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
);

CREATE TABLE commodities (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    category_id INT NOT NULL REFERENCES commodity_categories
);

CREATE TABLE station_types(
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
);

CREATE TABLE stations(
    id SERIAL PRIMARY KEY,
    system_id BIGINT references systems(id),
    name TEXT UNIQUE NOT NULL,
    type_id INT NOT NULL REFERENCES station_types(id),
    small_landing_pads INT NOT NULL,
    medium_landing_pads INT NOT NULL,
    large_landing_pads INT NOT NULL,
    government_type_id INT NOT NULL REFERENCES government_types(id)
);

CREATE TABLE station_economy_bridge(
    id SERIAL PRIMARY KEY,
    station_id INT NOT NULL REFERENCES stations(id),
    economy_type_id INT NOT NULL REFERENCES economy_types(id),
    proportion FLOAT NOT NULL
);

CREATE TABLE station_markets(
    id BIGINT NOT NULL,
    station_id INT NOT NULL REFERENCES stations(id),
    commodity_id INT NOT NULL REFERENCES commodities(id),
    faction_id INT NOT NULL REFERENCES factions(id),
    buy_price INT NOT NULL,
    sell_price INT NOT NULL,
    mean_price INT NOT NULL,
    stock_bracket INT NOT NULL,
    demand_bracket INT NOT NULL,
    stock INT NOT NULL,
    demand INT NOT NULL,
    consumer BOOLEAN NOT NULL,
    producer BOOLEAN NOT NULL,
    rare BOOLEAN NOT NULL,
    last_updated bigint not null,
    PRIMARY KEY(id, commodity_id)
);

CREATE TABLE faction_system_bridge(
    id SERIAL PRIMARY KEY,
    faction_id INT NOT NULL REFERENCES factions(id),
    system_id BIGINT NOT NULL REFERENCES systems(id),
    in_control BOOLEAN NOT NULL,
    last_updated bigint NOT NULL
);

\connect synco

create type synco_snapshot_type as enum('economy', 'buildings', 'citizens', 'roads', 'production', 'resources');

create table synco_snapshots(
    id serial primary key,
    snapshot_type synco_snapshot_type not null,    
    snapshot jsonb not null
);

