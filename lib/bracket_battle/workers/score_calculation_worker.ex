defmodule BracketBattle.Workers.ScoreCalculationWorker do
  @moduledoc """
  Oban worker to recalculate scores for a tournament.
  Can be triggered manually or scheduled after matchup decisions.
  """

  use Oban.Worker, queue: :scoring, max_attempts: 3

  alias BracketBattle.Scoring
  alias BracketBattle.Tournaments

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"tournament_id" => tournament_id}}) do
    Logger.info("ScoreCalculationWorker: Recalculating scores for tournament #{tournament_id}")

    tournament = Tournaments.get_tournament(tournament_id)

    if tournament do
      Scoring.recalculate_all_scores(tournament_id)
      Logger.info("ScoreCalculationWorker: Completed score recalculation for #{tournament.name}")
      :ok
    else
      Logger.error("ScoreCalculationWorker: Tournament #{tournament_id} not found")
      {:error, :tournament_not_found}
    end
  end

  @doc """
  Enqueue a score calculation job for a tournament.
  """
  def enqueue(tournament_id) do
    %{tournament_id: tournament_id}
    |> __MODULE__.new()
    |> Oban.insert()
  end
end
