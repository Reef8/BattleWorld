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
      region = tournament.current_voting_region
      round = tournament.current_voting_round

      # Get matchups for current region/round only
      matchups = get_region_matchups(tournament, region, round)

      all_decided = Enum.all?(matchups, fn m -> m.status == "decided" end)
      any_ties = Enum.any?(matchups, fn m ->
        m.status == "voting" and voting_ended?(m)
      end)

      phase_name = if region, do: "#{region} Round #{round}", else: "Round #{round}"

      cond do
        all_decided ->
          # All matchups in current region/round decided - advance to next phase
          Logger.info("#{phase_name} complete for tournament #{tournament_id}")

          case Tournaments.advance_region(tournament) do
            {:ok, updated} ->
              next_phase = if updated.current_voting_region do
                "#{updated.current_voting_region} Round #{updated.current_voting_round}"
              else
                "Round #{updated.current_voting_round}"
              end
              Logger.info("Advanced to #{next_phase}")

            {:error, reason} ->
              Logger.error("Failed to advance region: #{inspect(reason)}")
          end

        any_ties ->
          # Some ties exist - admin needs to decide
          Logger.info("#{phase_name} has ties awaiting admin decision")

        true ->
          # Still waiting for voting to end
          :ok
      end
    end
  end

  defp get_region_matchups(tournament, region, round) do
    import Ecto.Query
    alias BracketBattle.Repo
    alias BracketBattle.Tournaments.Matchup

    query = if region do
      from(m in Matchup,
        where: m.tournament_id == ^tournament.id
          and m.round == ^round
          and m.region == ^region,
        preload: [:contestant_1, :contestant_2, :winner]
      )
    else
      from(m in Matchup,
        where: m.tournament_id == ^tournament.id
          and m.round == ^round
          and is_nil(m.region),
        preload: [:contestant_1, :contestant_2, :winner]
      )
    end

    Repo.all(query)
  end

  defp voting_ended?(matchup) do
    matchup.voting_ends_at &&
      DateTime.compare(DateTime.utc_now(), matchup.voting_ends_at) != :lt
  end
end
