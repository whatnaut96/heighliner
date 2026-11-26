// TODO: Consider magic number removal across the board
// TODO: Consider following some of the NASA power of 10 rules
// TODO: Stellartel handling
import gleam/bit_array
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/io
import gleam/option
import gleam/otp/static_supervisor.{type Supervisor} as supervisor
import gleam/otp/supervision
import gleam/result
import gleam/string
import mist.{type Connection, type ResponseData}
import pog
import synco/handler.{handle_synco_request}
import utils/dotenv
import utils/logging
import utils/responses

fn heighliner_http_server_setup(
  _stellartel_db_pool: pog.Connection,
  synco_db_pool: pog.Connection,
  req: Request(Connection),
) -> Response(ResponseData) {
  case request.path_segments(req) {
    ["stellartel"] -> {
      case http.Post {
        http.Post -> {
          case mist.stream(req) {
            Ok(consume) -> {
              case do_handle_stream(consume, <<>>) {
                Ok(_body) -> {
                  // send to stellartel handler
                  response.new(responses.ok_code)
                  |> response.set_body(
                    mist.Bytes(bytes_tree.from_string("payload accepted")),
                  )
                }
                Error(reason) -> {
                  logging.error(
                    "failed to read the body route=synco error="
                    <> string.inspect(reason),
                  )
                  responses.bad_request()
                }
              }
            }
            Error(reason) -> {
              logging.error(
                "failed to start reading the body route=stellartel error="
                <> string.inspect(reason),
              )
              responses.bad_request()
            }
          }
        }
      }
    }

    ["synco"] -> {
      case req.method {
        http.Post -> {
          case mist.stream(req) {
            Ok(consume) ->
              case
                do_handle_stream(consume, <<>>)
                |> result.try(bit_array.to_string)
              {
                Ok(body) -> {
                  case request.get_query(req) {
                    Ok(params) -> {
                      handle_synco_request(params, body, synco_db_pool)
                    }
                    Error(reason) -> {
                      logging.error(
                        "failed to capture query parmeters: "
                        <> string.inspect(reason),
                      )
                      responses.bad_request()
                    }
                  }
                }
                Error(reason) -> {
                  logging.error(
                    "failed to read the body route=synco error="
                    <> string.inspect(reason),
                  )
                  responses.bad_request()
                }
              }
            Error(reason) -> {
              logging.error(
                "failed to start reading the body route=synco error="
                <> string.inspect(reason),
              )
              responses.bad_request()
            }
          }
        }
        _ -> {
          responses.not_supported()
        }
      }
    }
    _ -> {
      responses.not_found()
    }
  }
}

fn do_handle_stream(
  consume: fn(Int) -> Result(mist.Chunk, mist.ReadError),
  body: BitArray,
) -> Result(BitArray, Nil) {
  case consume(1024) {
    Ok(mist.Chunk(data, consume)) ->
      do_handle_stream(consume, <<body:bits, data:bits>>)
    Ok(mist.Done) -> Ok(body)
    Error(_reason) -> Error(Nil)
  }
}

fn build_mist_supervisor(
  stellartel_db,
  synco_db,
) -> supervision.ChildSpecification(Supervisor) {
  heighliner_http_server_setup(stellartel_db, synco_db, _)
  |> mist.new
  |> mist.bind("localhost")
  |> mist.with_ipv6
  |> mist.port(10_191)
  |> mist.supervised
}

fn build_stellartel_db_pool(
  stellartel_db_pool_proc_name: process.Name(pog.Message),
) {
  let stellartel_db_host = case dotenv.get_env("SYNCO_DB_HOST") {
    Ok(v) -> v
    Error(_) -> "localhost"
  }

  let stellartel_db_port = case dotenv.get_env("SYNCO_DB_PORT") {
    Ok(v) -> {
      case int.parse(v) {
        Ok(port) -> port
        Error(_) ->
          panic as "failed to parse the SYNCO_DB_PORT value as an integer"
      }
    }
    Error(_) -> {
      logging.warning("SYNCO_DB_PORT not set. defaulting to 5432")
      5432
    }
  }

  let stellartel_db_user = case dotenv.get_env("SYNCO_DB_USER") {
    Ok(v) -> v
    Error(_) -> panic as "no SYNCO_DB_USER set"
  }

  let stellartel_db_password = case dotenv.get_env("SYNCO_DB_PASSWORD") {
    Ok(v) -> option.Some(v)
    Error(_) -> {
      logging.warning("no SYNCO_DB_PASSWORD set. defaulting to nil")
      option.None
    }
  }

  let stellartel_db_database = case dotenv.get_env("SYNCO_DB_DATABASE") {
    Ok(v) -> v
    Error(_) -> {
      panic as "no SYNCO_DB_DATABASE set"
    }
  }

  let stellartel_db_pool_size = case dotenv.get_env("SYNCO_DB_POOL_SIZE") {
    Ok(v) -> {
      case int.parse(v) {
        Ok(pool_size) -> pool_size
        Error(_) ->
          panic as "failed to parse the SYNCO_DB_POOL_SIZE value as an integer"
      }
    }
    Error(_) -> {
      logging.warning(
        "SYNCO_DB_POOL_SIZE not set. using default of 10 connections",
      )
      10
    }
  }

  pog.default_config(stellartel_db_pool_proc_name)
  |> pog.host(stellartel_db_host)
  |> pog.port(stellartel_db_port)
  |> pog.user(stellartel_db_user)
  |> pog.password(stellartel_db_password)
  |> pog.database(stellartel_db_database)
  // I know the default is already 10 but I'd rather explicitly set it here
  // rather than write a conditional branch modifying the config
  |> pog.pool_size(stellartel_db_pool_size)
  |> pog.supervised
}

fn build_synco_db_pool(synco_db_pool_proc_name: process.Name(pog.Message)) {
  let synco_db_host = case dotenv.get_env("SYNCO_DB_HOST") {
    Ok(v) -> v
    Error(_) -> "localhost"
  }

  let synco_db_port = case dotenv.get_env("SYNCO_DB_PORT") {
    Ok(v) -> {
      case int.parse(v) {
        Ok(port) -> port
        Error(_) ->
          panic as "failed to parse the SYNCO_DB_PORT value as an integer"
      }
    }
    Error(_) -> {
      logging.warning("SYNCO_DB_PORT not set. defaulting to 5432")
      5432
    }
  }

  let synco_db_user = case dotenv.get_env("SYNCO_DB_USER") {
    Ok(v) -> v
    Error(_) -> panic as "no SYNCO_DB_USER set"
  }

  let synco_db_password = case dotenv.get_env("SYNCO_DB_PASSWORD") {
    Ok(v) -> option.Some(v)
    Error(_) -> {
      logging.warning("no SYNCO_DB_PASSWORD set. defaulting to nil")
      option.None
    }
  }

  let synco_db_database = case dotenv.get_env("SYNCO_DB_DATABASE") {
    Ok(v) -> v
    Error(_) -> {
      panic as "no SYNCO_DB_DATABASE set"
    }
  }

  let synco_db_pool_size = case dotenv.get_env("SYNCO_DB_POOL_SIZE") {
    Ok(v) -> {
      case int.parse(v) {
        Ok(pool_size) -> pool_size
        Error(_) ->
          panic as "failed to parse the SYNCO_DB_POOL_SIZE value as an integer"
      }
    }
    Error(_) -> {
      logging.warning(
        "SYNCO_DB_POOL_SIZE not set. using default of 10 connections",
      )
      10
    }
  }

  pog.default_config(synco_db_pool_proc_name)
  |> pog.host(synco_db_host)
  |> pog.port(synco_db_port)
  |> pog.user(synco_db_user)
  |> pog.password(synco_db_password)
  |> pog.database(synco_db_database)
  // I know the default is already 10 but I'd rather explicitly set it here
  // rather than write a conditional branch modifying the config
  |> pog.pool_size(synco_db_pool_size)
  |> pog.supervised
}

pub fn main() {
  let worked = dotenv.load_dotenv(option.Some("envs/.env"))
  io.println(string.inspect(worked))
  case worked {
    True -> {
      let synco_db_pool_proc_name = process.new_name("SyncoPostgres")
      let synco_db_pool_pog_connection =
        pog.named_connection(synco_db_pool_proc_name)

      let stellartel_db_pool_proc_name = process.new_name("StellarTelPostgres")
      let stellartel_db_pool_pog_connection =
        pog.named_connection(stellartel_db_pool_proc_name)

      let assert Ok(_) =
        supervisor.new(supervisor.OneForOne)
        |> supervisor.add(build_synco_db_pool(synco_db_pool_proc_name))
        |> supervisor.add(build_stellartel_db_pool(stellartel_db_pool_proc_name))
        |> supervisor.add(build_mist_supervisor(
          stellartel_db_pool_pog_connection,
          synco_db_pool_pog_connection,
        ))
        |> supervisor.start

      process.sleep_forever()
    }

    False -> panic
  }
}
