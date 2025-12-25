defmodule BracketBattle.Workers.CloseVotingWorker do
  @moduledoc """
  Oban worker that runs periodically to check for matchups where voting has ended
  and automatically tallies votes to determine winners.

  Runs every minute to check for expired voting periods.
  """

  use Oban.Worker, queue: :voting, max_attempts: 3

  alias BracketBattle.Voting
  alias BracketBattle.Tournaments
  alias BracketBattle.Scoring

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    # Find all matchups where voting has ended but winner not yet decided
    matchups = Voting.get_matchups_needing_tally()

    Logger.info("CloseVotingWorker: Found #{length(matchups)} matchups to tally")

    results = Enum.map(matchups, &tally_matchup/1)

    # Group by tournament for score recalculation
    tournaments_to_update =
      matchups
      |> Enum.map(& &1.tournament_id)
      |> Enum.uniq()

    # Recalculate scores for affected tournaments
    Enum.each(tournaments_to_update, fn tournament_id ->
      Scoring.recalculate_all_scores(tournament_id)

      # Check if round is complete and can advance
      check_round_completion(tournament_id)
    end)

    # Check for ties that need admin attention
    ties = Enum.filter(results, &match?({:tie, _, _, _}, &1))

    if length(ties) > 0 do
      Logger.warning("CloseVotingWorker: #{length(ties)} matchups ended in ties - admin decision required")
    end

    :ok
  end

  defp tally_matchup(matchup) do
    Logger.info("Tallying matchup #{matchup.id} (#{matchup.tournament.name})")

    case Voting.tally_matchup(matchup) do
      {:ok, updated_matchup} ->
        Logger.info("Winner decided: #{updated_matchup.winner_id}")
        {:ok, updated_matchup}

      {:tie, matchup_id, c1_votes, c2_votes} ->
        Logger.warning("Tie in matchup #{matchup_id}: #{c1_votes} vs #{c2_votes}")
        {:tie, matchup_id, c1_votes, c2_votes}

      {:error, reason} ->
        Logger.error("Failed to tally matchup #{matchup.id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp check_round_completion(tournament_id) do
    tournament = Tournaments.get_tournament!(tournament_id)

    # Only check active tournaments
    if tournament.status == "active" do
      # Check if all matchups in current round are decided
      matchups = Tournaments.get_matchups_by_round(tournament_id, tournament.current_round)

      all_decided = Enum.all?(matchups, fn m -> m.status == "decided" end)
      any_ties = Enum.any?(matchups, fn m ->
        m.status == "voting" and voting_ended?(m)
      end)

      cond do
        all_decided ->
          # All matchups decided - can auto-advance to next round
          Logger.info("Round #{tournament.current_round} complete for tournament #{tournament_id}")

          case Tournaments.advance_round(tournament) do
            {:ok, updated} ->
              Logger.info("Advanced to round #{updated.current_round}")

            {:error, reason} ->
              Logger.error("Failed to advance round: #{inspect(reason)}")
          end

        any_ties ->
          # Some ties exist - admin needs to decide
          Logger.info("Round #{tournament.current_round} has ties awaiting admin decision")

        true ->
          # Still waiting for voting to end
          :ok
      end
    end
  end

  defp voting_ended?(matchup) do
    matchup.voting_ends_at &&
      DateTime.compare(DateTime.utc_now(), matchup.voting_ends_at) != :lt
  end
end
