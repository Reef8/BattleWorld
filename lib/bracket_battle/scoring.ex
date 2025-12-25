defmodule BracketBattle.Scoring do
  @moduledoc """
  Context for bracket scoring using ESPN-style points.
  Round 1: 10 points, Round 2: 20, Round 3: 40, Round 4: 80, Round 5: 160, Round 6: 320
  """

  import Ecto.Query
  alias BracketBattle.Repo
  alias BracketBattle.Brackets.UserBracket
  alias BracketBattle.Tournaments

  # ESPN-style scoring: 10, 20, 40, 80, 160, 320
  @points_per_round %{
    1 => 10,
    2 => 20,
    3 => 40,
    4 => 80,
    5 => 160,
    6 => 320
  }

  @doc "Get points for a specific round"
  def points_for_round(round), do: Map.get(@points_per_round, round, 0)

  @doc "Get max possible score"
  def max_possible_score do
    # 32*10 + 16*20 + 8*40 + 4*80 + 2*160 + 1*320 = 1920
    320 + 320 + 320 + 320 + 320 + 320
  end

  @doc "Recalculate scores for all brackets in tournament"
  def recalculate_all_scores(tournament_id) do
    official_results = get_official_results(tournament_id)
    brackets = list_submitted_brackets(tournament_id)

    Enum.each(brackets, fn bracket ->
      calculate_and_update_score(bracket, official_results)
    end)

    broadcast_leaderboard_update(tournament_id)
  end

  @doc "Calculate score for single bracket"
  def calculate_and_update_score(%UserBracket{} = bracket, official_results) do
    picks = bracket.picks || %{}

    scores = for round <- 1..6 do
      round_positions = get_positions_for_round(round)
      points = @points_per_round[round]

      correct = Enum.count(round_positions, fn pos ->
        pick = Map.get(picks, to_string(pos))
        result = Map.get(official_results, pos)
        pick && result && pick == result
      end)

      {round, correct * points, correct}
    end

    round_scores = Map.new(scores, fn {r, pts, _} -> {:"round_#{r}_score", pts} end)
    total_score = Enum.sum(Enum.map(scores, fn {_, pts, _} -> pts end))
    correct_picks = Enum.sum(Enum.map(scores, fn {_, _, c} -> c end))
    possible = calculate_possible_score(picks, official_results)

    bracket
    |> UserBracket.score_changeset(
      Map.merge(round_scores, %{
        total_score: total_score,
        correct_picks: correct_picks,
        possible_score: possible
      })
    )
    |> Repo.update!()
  end

  @doc "Finalize scores when tournament completes"
  def finalize_scores(tournament_id) do
    recalculate_all_scores(tournament_id)
  end

  # ============================================================================
  # PRIVATE HELPERS
  # ============================================================================

  defp get_official_results(tournament_id) do
    matchups = Tournaments.get_all_matchups(tournament_id)

    matchups
    |> Enum.filter(& &1.winner_id)
    |> Map.new(fn m -> {matchup_to_position(m), m.winner_id} end)
  end

  defp matchup_to_position(%{round: round, position: pos}) do
    # Convert round/position to bracket position (1-63)
    base = case round do
      1 -> 0
      2 -> 32
      3 -> 48
      4 -> 56
      5 -> 60
      6 -> 62
    end
    base + pos
  end

  defp get_positions_for_round(round) do
    case round do
      1 -> Enum.to_list(1..32)
      2 -> Enum.to_list(33..48)
      3 -> Enum.to_list(49..56)
      4 -> Enum.to_list(57..60)
      5 -> Enum.to_list(61..62)
      6 -> [63]
    end
  end

  defp calculate_possible_score(picks, official_results) do
    # Calculate maximum possible remaining score
    # Start with current score, then add max points for undecided matchups
    # where the picked contestant is still alive

    decided_positions = Map.keys(official_results)
    max_decided_position = if Enum.empty?(decided_positions), do: 0, else: Enum.max(decided_positions)

    # Get eliminated contestants (losers from decided matchups)
    eliminated = get_eliminated_contestants(official_results)

    remaining_score = for round <- 1..6 do
      positions = get_positions_for_round(round)
      points = @points_per_round[round]

      viable_count = Enum.count(positions, fn pos ->
        pick = Map.get(picks, to_string(pos))

        cond do
          # Position already decided - count if correct
          pos <= max_decided_position ->
            Map.get(official_results, pos) == pick

          # Future position - check if pick is still alive
          pick && not MapSet.member?(eliminated, pick) ->
            true

          true ->
            false
        end
      end)

      viable_count * points
    end

    Enum.sum(remaining_score)
  end

  defp get_eliminated_contestants(_official_results) do
    # Build set of eliminated contestants by finding matchups where
    # the official result doesn't match a contestant
    # This is simplified - we just track who won, so eliminated = everyone who didn't win
    # when they should have

    # For now, return empty set since we track via matchup winners
    # In a full implementation, we'd track which contestants lost
    MapSet.new()
  end

  defp list_submitted_brackets(tournament_id) do
    from(b in UserBracket,
      where: b.tournament_id == ^tournament_id and not is_nil(b.submitted_at)
    )
    |> Repo.all()
  end

  defp broadcast_leaderboard_update(tournament_id) do
    Phoenix.PubSub.broadcast(
      BracketBattle.PubSub,
      "tournament:#{tournament_id}:leaderboard",
      {:leaderboard_updated, tournament_id}
    )
  end
end
