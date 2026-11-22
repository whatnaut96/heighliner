defmodule Heighliner.Plug do
  use Plug.Router
  require Logger

  plug(Plug.Logger)
  plug(:match)
  plug(:dispatch)

  get "/health" do
    case Postgrex.query(StellarTel.Postgres, "SELECT 1", []) do
      {:ok, _} -> send_resp(conn, 200, "All health checks passed")
      {:error, reason} -> send_resp(conn, 503, "#{inspect(reason)}")
    end
  end

  post "/stellartel" do
    case Plug.Conn.read_body(conn) do
      {:ok, body, conn} ->
        {:ok, event} = JSON.decode(body)

        event_atom =
          event["event"]
          |> String.downcase()
          |> String.to_atom()

        result = StellarTel.Handler.handle_journal(event_atom, event)

        case result do
          :ok ->
            send_resp(conn, 200, "journal processed successfully")

          {:error, :event_type_not_supported} ->
            send_resp(conn, 423, "#{event["event"]} not supported")

          :internal_error ->
            send_resp(conn, 500, "internal error")

          {:error, :malformed_payload} ->
            send_resp(
              conn,
              400,
              "The provided payload does not match the expected shape for the type #{event["event"]}"
            )
        end

      {:error, reason} ->
        Logger.error("failed to read the body error=#{reason}")
        send_resp(conn, 400, "failed to read the body: #{reason}")
    end
  end

  post "/synco" do
    payload_type =
      Plug.Conn.Query.decode(conn.query_string)["type"] || "unknown"

    case read_full_body(conn) do
      {:ok, body, conn} ->
        chunk_size = 5 * 1024 * 1024

        payload_stream =
          Stream.resource(
            fn -> 0 end,
            fn
              offset when offset >= byte_size(body) ->
                {:halt, offset}

              offset ->
                len = min(chunk_size, byte_size(body) - offset)
                {[binary_part(body, offset, len)], offset + len}
            end,
            fn _ -> :ok end
          )

        payload_hash =
          :crypto.hash(:sha256, body)
          |> Base.encode16(case: :lower)

        synco_path = Application.get_env(:heighliner, :synco_path)
        hashed_file_name = "#{payload_hash}.json"
        payload_type_path = "#{synco_path}/#{payload_type}"
        File.mkdir_p!(payload_type_path)

        payload_write_path = "#{payload_type_path}/#{hashed_file_name}"
        file = File.open!(payload_write_path, [:write])

        payload_stream
        |> Stream.chunk_every(1000)
        |> Enum.reduce(file, fn chunk, acc_file ->
          :ok = IO.write(acc_file, chunk)
          acc_file
        end)

        File.close(file)
        # send message to consumer
        send_resp(conn, 202, "")
    end
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp read_full_body(conn, acc \\ "") do
    case Plug.Conn.read_body(conn) do
      {:ok, body, conn} ->
        {:ok, acc <> body, conn}

      {:more, partial_body, conn} ->
        read_full_body(conn, acc <> partial_body)

      {:error, reason} ->
        Logger.error("failed to read the body error=#{reason}")
        {:error, reason}
    end
  end
end
