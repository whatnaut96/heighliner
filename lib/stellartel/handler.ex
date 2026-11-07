defmodule StellarTel.Handler do
  require Logger
  import Bitwise

  @legal_states %{
    "Clean" => 1,
    "IllegalCargo" => 2,
    "Speeding" => 3,
    "Wanted" => 4,
    "Hostile" => 5,
    "PassengerWanted" => 6,
    "Warrant" => 7,
    "Allied" => 8,
    "Thargoid" => 9
  }

  def handle_journal(:status, entry) do
    flags = entry["Flags"]

    %{
      mass_locked: mass_locked,
      low_fuel: low_fuel,
      overheating: overheating,
      in_danger: in_danger,
      being_interdicted: being_interdicted
    } = parse_flags(flags)

    mass_locked_metric_string = """
    # help stellartel_mass_locked signals if the ship is masslocked (0 = false, 1 = true)
    # type stellartel_mass_locked gauge
    stellartel_mass_locked{} #{mass_locked}
    """

    low_fuel_metric_string = """
    # help stellartel_low_fuel signals if the ship is low on fuel (0 = false, 1 = true)
    # type stellartel_low_fuel gauge
    stellartel_low_fuel{} #{low_fuel}
    """

    overheating_metric_string = """
    # help stellartel_overheating signals if the ship is overheating (0 = false, 1 = true)
    # type stellartel_overheating gauge
    stellartel_overheating{} #{overheating}
    """

    in_danger_metric_string = """
    # help stellartel_in_danger signals if the ship is in danger (0 = false, 1 = true)
    # type stellartel_in_danger gauge
    stellartel_in_danger{} #{in_danger}
    """

    being_interdicted_metric_string = """
    # help stellartel_being_interdicted signals if the ship is being interdicted (0 = false, 1 = true)
    # type stellartel_being_interdicted gauge
    stellartel_being_interdicted{} #{being_interdicted}
    """

    legal_state = entry["legalstate"]

    legal_state_metric_string = """
    # help stellartel_legal_state the legal status of the ship (1 = clean, 2 = illegalcargo, 3 = speeding, 4 = wanted, 5 = hostile, 6 = passengerwanted, 7 = warrant, 8 = allied, 9 = thargoid)
    # type stellartel_legal_state gauge
    stellartel_legal_state{} #{@legal_states[legal_state]}
    """

    # combine all metrics into a single body payload
    body = """
    #{mass_locked_metric_string}
    #{low_fuel_metric_string}
    #{overheating_metric_string}
    #{in_danger_metric_string}
    #{being_interdicted_metric_string}
    #{legal_state_metric_string}
    """

    url =
      :heighliner
      |> Application.fetch_env!(:prometheus_endpoint)

    case Req.post(url, body: body, headers: [{"content-type", "text/plain"}]) do
      {:ok, %Req.Response{status: 204, body: _response_body}} ->
        :ok

      {:ok, %Req.Response{status: status}} ->
        Logger.error("Failed to push status metrics: got #{status} back from endpoint")
        :internal_error

      {:error, exception} when is_exception(exception) ->
        Logger.error("Failed to push status metrics: #{Exception.message(exception)}")
        :internal_error
    end
  end

  def handle_journal(unknown_event_type, _event) do
    Logger.info("received an event that is not yet supported: #{unknown_event_type}")
    {:error, :event_type_not_supported}
  end

  defp parse_flags(flags) when is_integer(flags) do
    mass_locked =
      bsr(flags, 16)
      |> band(1)

    low_fuel =
      bsr(flags, 19)
      |> band(1)

    overheating =
      bsr(flags, 20)
      |> band(1)

    in_danger =
      bsr(flags, 22)
      |> band(1)

    being_interdicted =
      bsr(flags, 23)
      |> band(1)

    %{
      mass_locked: mass_locked,
      low_fuel: low_fuel,
      overheating: overheating,
      in_danger: in_danger,
      being_interdicted: being_interdicted
    }
  end
end
