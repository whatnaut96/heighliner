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
    payload_atom =
      Plug.Conn.Query.decode(conn.query_string)["type"]
      |> String.to_atom()

    case read_full_body(conn) do
      {:ok, body, conn} ->
        case Synco.Handler.handle_payload(payload_atom, body) do
          :ok -> send_resp(conn, 200, "foo")
        end
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
