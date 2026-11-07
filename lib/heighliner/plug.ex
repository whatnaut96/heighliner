defmodule Heighliner.Plug do
  use Plug.Router
  require Logger

  plug(Plug.Logger)
  plug(:match)
  plug(:dispatch)

  get "/health" do
    # TODO: Health checks
    send_resp(conn, 200, "")
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
        end

      {:error, reason} ->
        Logger.error("failed to read the body error=#{reason}")
        send_resp(conn, 400, "failed to read the body: #{reason}")
    end
  end
end
