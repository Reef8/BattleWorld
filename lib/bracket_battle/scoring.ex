defmodule BracketBattle.Scoring do
  @moduledoc """
  Context for bracket scoring using ESPN-style points.
  Default: Round 1: 10 points, Round 2: 20, Round 3: 40, Round 4: 80, Round 5: 160, Round 6: 320
  Supports custom scoring per tournament.
  """

  import Ecto.Query
  alias BracketBattle.Repo
  alias BracketBattle.Brackets.UserBracket
  alias BracketBattle.Tournaments
  alias BracketBattle.Tournaments.Tournament

  # Default ESPN-style scoring: doubles each round
  @default_points_per_round %{
    1 => 10,
    2 => 20,
    3 => 40,
    4 => 80,
    5 => 160,
    6 => 320,
    7 => 640
  }

  @doc "Get points for a specific round (uses default scoring)"
  def points_for_round(round), do: Map.get(@default_points_per_round, round, 0)

  @doc "Get points for a specific round in a tournament (supports custom scoring)"
  def points_for_round(%Tournament{} = tournament, round) do
    custom = Map.get(tournament.scoring_config || %{}, round) ||
             Map.get(tournament.scoring_config || %{}, to_string(round))

    if custom do
      custom
    else
      # Default: 10 * 2^(round-1)
      Map.get(@default_points_per_round, round, 10 * trunc(:math.pow(2, round - 1)))
    end
  end

  @doc "Get max possible score for a tournament"
  def max_possible_score(%Tournament{} = tournament) do
    bracket_size = tournament.bracket_size || 64
    total_rounds = Tournament.total_rounds(tournament)

    Enum.reduce(1..total_rounds, 0, fn round, acc ->
      matchups_in_round = div(bracket_size, trunc(:math.pow(2, round)))
      points = points_for_round(tournament, round)
      acc + (matchups_in_round * points)
    end)
  end

  @doc "Get max possible score (default 64-contestant tournament)"
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
    tournament = Tournaments.get_tournament!(bracket.tournament_id)
    total_rounds = Tournament.total_rounds(tournament)
    picks = bracket.picks || %{}

    scores = for round <- 1..total_rounds do
      round_positions = get_positions_for_round(tournament, round)
      points = points_for_round(tournament, round)

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
    possible = calculate_possible_score(tournament, picks, official_results)

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
    tournament = Tournaments.get_tournament!(tournament_id)
    matchups = Tournaments.get_all_matchups(tournament_id)

    matchups
    |> Enum.filter(& &1.winner_id)
    |> Map.new(fn m -> {matchup_to_position(m, tournament), m.winner_id} end)
  end

  defp matchup_to_position(%{round: round, position: pos}, tournament) do
    # Convert round/position to bracket position (1 to total_matchups)
    bracket_size = tournament.bracket_size || 64
    base = calculate_base_position(bracket_size, round)
    base + pos - 1
  end

  # Calculate base position for a round (sum of matchups in all previous rounds)
  defp calculate_base_position(bracket_size, round) do
    Enum.reduce(1..(round - 1), 1, fn r, acc ->
      acc + div(bracket_size, trunc(:math.pow(2, r)))
    end)
  end

  defp get_positions_for_round(%Tournament{bracket_size: bracket_size}, round) do
    base = calculate_base_position(bracket_size || 64, round)
    matchups = div(bracket_size || 64, trunc(:math.pow(2, round)))
    Enum.to_list(base..(base + matchups - 1))
  end

  defp calculate_possible_score(%Tournament{} = tournament, picks, official_results) do
    # Calculate maximum possible remaining score
    total_rounds = Tournament.total_rounds(tournament)

    decided_positions = Map.keys(official_results)
    max_decided_position = if Enum.empty?(decided_positions), do: 0, else: Enum.max(decided_positions)

    # Get eliminated contestants (losers from decided matchups)
    eliminated = get_eliminated_contestants(official_results)

    remaining_score = for round <- 1..total_rounds do
      positions = get_positions_for_round(tournament, round)
      points = points_for_round(tournament, round)

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
