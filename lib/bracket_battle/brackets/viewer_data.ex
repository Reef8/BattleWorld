defmodule BracketBattle.Brackets.ViewerData do
  @moduledoc """
  Transforms tournament data to brackets-viewer.js format.

  The brackets-viewer library expects data in a specific format:
  - participants: list of %{id, name, tournament_id}
  - stages: list of %{id, tournament_id, name, type, number, settings}
  - matches: list of %{id, stage_id, group_id, round_id, number, opponent1, opponent2, status}
  """

  alias BracketBattle.Tournaments.Tournament

  @doc """
  Converts tournament data to brackets-viewer format.

  ## Parameters
  - tournament: The tournament struct
  - matchups: List of matchup structs with contestants preloaded
  - contestants: List of contestant structs

  ## Returns
  A map with :stages, :matches, :participants, :matchGames keys
  """
  def to_viewer_format(tournament, matchups, contestants) do
    %{
      stages: build_stages(tournament),
      matches: build_matches(tournament, matchups),
      participants: build_participants(contestants),
      matchGames: []
    }
  end

  @doc """
  Builds viewer data for a user's bracket picks (predictions).
  Shows the user's picks as the "winners" even before matches are decided.
  """
  def to_viewer_format_with_picks(tournament, matchups, contestants, picks) do
    %{
      stages: build_stages(tournament),
      matches: build_matches_with_picks(tournament, matchups, picks),
      participants: build_participants(contestants),
      matchGames: []
    }
  end

  # Build stages - for single elimination we just need one stage
  defp build_stages(tournament) do
    total_rounds = Tournament.total_rounds(tournament)

    [
      %{
        id: tournament.id,
        tournament_id: tournament.id,
        name: tournament.name,
        type: "single_elimination",
        number: 1,
        settings: %{
          size: tournament.bracket_size,
          grandFinal: nil,
          matchesChildCount: 0
        }
      }
    ]
  end

  # Build participants from contestants
  defp build_participants(contestants) do
    Enum.map(contestants, fn c ->
      %{
        id: c.id,
        name: c.name,
        tournament_id: c.tournament_id
      }
    end)
  end

  # Build matches from matchups - actual tournament state
  defp build_matches(tournament, matchups) do
    total_rounds = Tournament.total_rounds(tournament)

    matchups
    |> Enum.sort_by(fn m -> {m.round, m.position} end)
    |> Enum.map(fn matchup ->
      build_match(tournament, matchup, total_rounds)
    end)
  end

  # Build matches with user picks overlaid
  defp build_matches_with_picks(tournament, matchups, picks) do
    total_rounds = Tournament.total_rounds(tournament)

    matchups
    |> Enum.sort_by(fn m -> {m.round, m.position} end)
    |> Enum.map(fn matchup ->
      build_match_with_pick(tournament, matchup, picks, total_rounds)
    end)
  end

  defp build_match(tournament, matchup, total_rounds) do
    # Round IDs in brackets-viewer are 1-indexed per stage
    # Group ID is 0 for single elimination (no groups)
    round_id = matchup.round
    group_id = 0

    # Match number within the round (1-indexed)
    match_number = matchup.position

    %{
      id: matchup.id,
      stage_id: tournament.id,
      group_id: group_id,
      round_id: round_id,
      number: match_number,
      child_count: 0,
      opponent1: build_opponent(matchup.contestant_1, matchup.winner_id),
      opponent2: build_opponent(matchup.contestant_2, matchup.winner_id),
      status: match_status(matchup)
    }
  end

  defp build_match_with_pick(tournament, matchup, picks, total_rounds) do
    round_id = matchup.round
    group_id = 0
    match_number = matchup.position

    # Get the user's pick for this matchup position
    pick_key = to_string(matchup.position)
    picked_contestant_id = Map.get(picks, pick_key)

    %{
      id: matchup.id,
      stage_id: tournament.id,
      group_id: group_id,
      round_id: round_id,
      number: match_number,
      child_count: 0,
      opponent1: build_opponent_with_pick(matchup.contestant_1, picked_contestant_id),
      opponent2: build_opponent_with_pick(matchup.contestant_2, picked_contestant_id),
      status: pick_match_status(matchup, picked_contestant_id)
    }
  end

  defp build_opponent(nil, _winner_id), do: nil

  defp build_opponent(contestant, winner_id) do
    result =
      cond do
        winner_id == nil -> nil
        winner_id == contestant.id -> "win"
        true -> "loss"
      end

    %{
      id: contestant.id,
      score: nil,
      result: result
    }
  end

  defp build_opponent_with_pick(nil, _picked_id), do: nil

  defp build_opponent_with_pick(contestant, picked_id) do
    result =
      if picked_id && picked_id == contestant.id do
        "win"
      else
        nil
      end

    %{
      id: contestant.id,
      score: nil,
      result: result
    }
  end

  # Map our status to brackets-viewer status
  # brackets-viewer statuses: 0=Locked, 1=Waiting, 2=Ready, 3=Running, 4=Completed, 5=Archived
  defp match_status(matchup) do
    case matchup.status do
      "pending" ->
        if matchup.contestant_1_id && matchup.contestant_2_id, do: 2, else: 1

      "voting" ->
        3

      "decided" ->
        4

      _ ->
        1
    end
  end

  defp pick_match_status(matchup, picked_id) do
    cond do
      # If user made a pick, show as completed
      picked_id != nil -> 4
      # If both contestants are set, ready to pick
      matchup.contestant_1_id && matchup.contestant_2_id -> 2
      # Otherwise waiting for contestants
      true -> 1
    end
  end
end
