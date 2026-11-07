defmodule StellarTel.HandlerTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  setup do
    previous_endpoint = Application.fetch_env(:heighliner, :prometheus_endpoint)

    on_exit(fn ->
      case previous_endpoint do
        {:ok, endpoint} -> Application.put_env(:heighliner, :prometheus_endpoint, endpoint)
        :error -> Application.delete_env(:heighliner, :prometheus_endpoint)
      end
    end)
  end

  test "status entries are converted to Prometheus metrics and posted" do
    endpoint = start_upstream(204, self())
    Application.put_env(:heighliner, :prometheus_endpoint, endpoint)

    flags =
      1
      |> Bitwise.bor(Bitwise.bsl(1, 16))
      |> Bitwise.bor(Bitwise.bsl(1, 20))
      |> Bitwise.bor(Bitwise.bsl(1, 23))

    assert StellarTel.Handler.handle_journal(:status, %{
             "Flags" => flags,
             "legalstate" => "Wanted"
           }) == :ok

    assert_receive {:upstream_request, request}
    assert request.method == "POST"
    assert request.path == "/metrics"
    assert request.content_type == ["text/plain"]

    assert request.body =~ "stellartel_mass_locked{} 1"
    assert request.body =~ "stellartel_low_fuel{} 0"
    assert request.body =~ "stellartel_overheating{} 1"
    assert request.body =~ "stellartel_in_danger{} 0"
    assert request.body =~ "stellartel_being_interdicted{} 1"
    assert request.body =~ "stellartel_legal_state{} 4"
  end

  test "a non-204 upstream response is logged and returned as an internal error" do
    endpoint = start_upstream(503, self())
    Application.put_env(:heighliner, :prometheus_endpoint, endpoint)

    log =
      capture_log(fn ->
        assert StellarTel.Handler.handle_journal(:status, %{
                 "Flags" => 0,
                 "legalstate" => "Clean"
               }) == :internal_error
      end)

    assert log =~ "Failed to push status metrics: got 503 back from endpoint"
  end

  test "a transport failure is logged and returned as an internal error" do
    Application.put_env(
      :heighliner,
      :prometheus_endpoint,
      "http://127.0.0.1:1/metrics"
    )

    log =
      capture_log(fn ->
        assert StellarTel.Handler.handle_journal(:status, %{
                 "Flags" => 0,
                 "legalstate" => "Clean"
               }) == :internal_error
      end)

    assert log =~ "Failed to push status metrics:"
  end

  test "an unsupported journal event returns an unsupported event error" do
    assert StellarTel.Handler.handle_journal(:fsd_jump, %{}) ==
             {:error, :event_type_not_supported}
  end

  defp start_upstream(status, owner) do
    plug = fn conn, _options ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      send(owner, {
        :upstream_request,
        %{
          method: conn.method,
          path: conn.request_path,
          content_type: Plug.Conn.get_req_header(conn, "content-type"),
          body: body
        }
      })

      Plug.Conn.send_resp(conn, status, "")
    end

    pid = start_supervised!({Bandit, plug: plug, port: 0, startup_log: false})
    {:ok, {_address, port}} = ThousandIsland.listener_info(pid)
    "http://127.0.0.1:#{port}/metrics"
  end
end
