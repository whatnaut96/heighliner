// TODO: Add the capability to change the response strings
// TODO: Explore a potential abstraction here
import gleam/bytes_tree
import gleam/http/response.{type Response}
import mist.{type ResponseData}

pub const ok_code = 200

const not_found_code = 404

const bad_request_code = 400

const method_not_supported_code = 501

const internal_error_code = 500

pub fn bad_request() -> Response(ResponseData) {
  response.new(bad_request_code)
  |> response.set_body(mist.Bytes(bytes_tree.from_string("invalid request")))
}

pub fn not_found() -> Response(ResponseData) {
  response.new(not_found_code)
  |> response.set_body(
    mist.Bytes(bytes_tree.from_string("not a valid endpoint")),
  )
}

pub fn not_supported() -> Response(ResponseData) {
  response.new(method_not_supported_code)
  |> response.set_body(
    mist.Bytes(bytes_tree.from_string("method not supported")),
  )
}

pub fn internal_error(body_string: String) -> Response(ResponseData) {
  response.new(internal_error_code)
  |> response.set_body(mist.Bytes(bytes_tree.from_string(body_string)))
}
