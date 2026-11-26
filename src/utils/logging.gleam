import gleam/io
import gleam/time/calendar
import gleam/time/timestamp

pub fn info(message: String) {
  io.println_error(
    "[INFO] "
    <> timestamp.system_time() |> timestamp.to_rfc3339(calendar.utc_offset)
    <> " "
    <> message,
  )
}

pub fn debug(message: String) {
  io.println_error(
    "[DEBUG] "
    <> timestamp.system_time() |> timestamp.to_rfc3339(calendar.utc_offset)
    <> " "
    <> message,
  )
}

pub fn warning(message: String) {
  io.println_error(
    "[DEBUG] "
    <> timestamp.system_time() |> timestamp.to_rfc3339(calendar.utc_offset)
    <> " "
    <> message,
  )
}

pub fn error(message: String) {
  io.println_error(
    "[ERROR] "
    <> timestamp.system_time() |> timestamp.to_rfc3339(calendar.utc_offset)
    <> " "
    <> message,
  )
}
