import gleam/erlang/charlist.{type Charlist}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import simplifile

@external(erlang, "os", "putenv")
fn put_env_raw(key: Charlist, value: Charlist) -> Bool

pub fn put_env(key: String, value: String) -> Bool {
  put_env_raw(charlist.from_string(key), charlist.from_string(value))
}

@external(erlang, "os", "getenv")
fn get_env_raw(key: Charlist, default: Charlist) -> Charlist

pub fn get_env(key: String) -> Result(String, Nil) {
  let sentinel = charlist.from_string("")
  let raw = get_env_raw(charlist.from_string(key), sentinel)
  case charlist.to_string(raw) {
    "" -> Error(Nil)
    value -> Ok(value)
  }
}

fn parse_env_file(contents: String) -> Bool {
  // Split by newline
  case
    string.split(contents, "\n")
    // pass each line pairing to put_env, placing bools in list
    |> list.map(fn(line) -> Bool {
      case string.split_once(line, "=") {
        Ok(pair) -> {
          let #(env_key, env_value) = pair
          let env_value = string.replace(env_value, "\"", "")
          put_env(env_key, env_value)
        }
        Error(_) -> False
      }
    })
    |> list.find(fn(_) { False })
  {
    Ok(v) -> v
    Error(_) -> True
  }
}

pub fn load_dotenv(path: Option(String)) -> Bool {
  let file_path = case path {
    Some(v) -> {
      v
    }
    None -> {
      ".env"
    }
  }

  case simplifile.read(file_path) {
    Ok(contents) -> {
      parse_env_file(contents)
    }
    Error(_) -> False
  }
}
