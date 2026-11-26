import gleam/bytes_tree
import gleam/http/response.{type Response}
import gleam/list
import gleam/set
import mist.{type ResponseData}
import pog
import utils/responses

const synco_insert_query: String = "INSERT INTO synco_snapshots(snapshot_type, snapshot) VALUES ($1, $2)"

const synco_payload_types: List(String) = [
  "economy",
  "buildings",
  "citizens",
  "roads",
  "production",
  "resources",
]

pub fn handle_synco_request(
  parameters: List(#(String, String)),
  body: String,
  synco_db_pool: pog.Connection,
) -> Response(ResponseData) {
  let acceptable_payload_types = set.from_list(synco_payload_types)

  case parameters |> list.key_find("type") {
    Ok(payload_type) -> {
      case set.contains(acceptable_payload_types, payload_type) {
        True -> {
          case
            pog.query(synco_insert_query)
            |> pog.parameter(pog.text(payload_type))
            |> pog.parameter(pog.text(body))
            |> pog.execute(synco_db_pool)
          {
            Ok(_) -> {
              response.new(responses.ok_code)
              |> response.set_body(mist.Bytes(bytes_tree.new()))
            }
            Error(_) -> {
              responses.internal_error("failed to execute internal query")
            }
          }
        }
        False -> responses.bad_request()
      }
    }
    Error(_) -> {
      responses.bad_request()
    }
  }
}
