defmodule Heighliner.PlugTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test

  setup do
    previous_endpoint = Application.fetch_env(:heighliner, :prometheus_endpoint)

    on_exit(fn ->
      case previous_endpoint do
        {:ok, endpoint} -> Application.put_env(:heighliner, :prometheus_endpoint, endpoint)
        :error -> Application.delete_env(:heighliner, :prometheus_endpoint)
      end
    end)
  end

  test "GET /health reports an empty successful response" do
    conn =
      conn(:get, "/health")
      |> Heighliner.Plug.call(Heighliner.Plug.init([]))

    assert conn.status == 200
    assert conn.resp_body == ""
  end

  test "POST /stellartel processes a status journal entry" do
    endpoint = start_upstream(204)
    Application.put_env(:heighliner, :prometheus_endpoint, endpoint)

    body = JSON.encode!(%{"event" => "Status", "Flags" => 0, "legalstate" => "Clean"})

    conn =
      conn(:post, "/stellartel", body)
      |> put_req_header("content-type", "application/json")
      |> Heighliner.Plug.call(Heighliner.Plug.init([]))

    assert conn.status == 200
    assert conn.resp_body == "journal processed successfully"
  end

  test "POST /stellartel reports unsupported journal events" do
    body = JSON.encode!(%{"event" => "FSDJump"})

    conn =
      conn(:post, "/stellartel", body)
      |> put_req_header("content-type", "application/json")
      |> Heighliner.Plug.call(Heighliner.Plug.init([]))

    assert conn.status == 423
    assert conn.resp_body == "FSDJump not supported"
  end

  test "POST /stellartel reports upstream failures as internal errors" do
    endpoint = start_upstream(503)
    Application.put_env(:heighliner, :prometheus_endpoint, endpoint)

    body = JSON.encode!(%{"event" => "Status", "Flags" => 0, "legalstate" => "Clean"})

    conn =
      conn(:post, "/stellartel", body)
      |> put_req_header("content-type", "application/json")
      |> Heighliner.Plug.call(Heighliner.Plug.init([]))

    assert conn.status == 500
    assert conn.resp_body == "internal error"
  end

  test "an unmatched route raises a function clause error" do
    assert_raise FunctionClauseError, fn ->
      conn(:get, "/missing")
      |> Heighliner.Plug.call(Heighliner.Plug.init([]))
    end
  end

  defp start_upstream(status) do
    plug = fn conn, _options -> Plug.Conn.send_resp(conn, status, "") end
    pid = start_supervised!({Bandit, plug: plug, port: 0, startup_log: false})
    {:ok, {_address, port}} = ThousandIsland.listener_info(pid)
    "http://127.0.0.1:#{port}/metrics"
  end
end
