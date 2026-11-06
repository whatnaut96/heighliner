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

        Logger.info(event_atom)

        case event_atom do
          :status ->
            Logger.debug("status payload received")
        end

        send_resp(conn, 200, "")

      {:error, reason} ->
        Logger.error("failed to read the body error=#{reason}")
        send_resp(conn, 400, "failed to read the body: #{reason}")
    end
  end
end
