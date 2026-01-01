defmodule BracketBattleWeb.Admin.TournamentController do
  use BracketBattleWeb, :controller

  alias BracketBattle.Tournaments

  def end_round(conn, %{"id" => id}) do
    tournament = Tournaments.get_tournament!(id)
    IO.inspect({tournament.id, tournament.status, tournament.current_voting_region, tournament.current_round}, label: "END_ROUND: Tournament")

    result = Tournaments.end_round_early(tournament)
    IO.inspect(result, label: "END_ROUND: Result")

    case result do
      {:ok, {:advanced, _updated}} ->
        conn
        |> put_flash(:info, "Round ended and advanced to next round!")
        |> redirect(to: "/admin")

      {:ok, {:ties_pending, tie_ids}} ->
        conn
        |> put_flash(:error, "#{length(tie_ids)} matchup(s) are tied. Decide them on the matchups page first.")
        |> redirect(to: "/admin/tournaments/#{id}/matchups")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to end round: #{inspect(reason)}")
        |> redirect(to: "/admin")
    end
  end
end
