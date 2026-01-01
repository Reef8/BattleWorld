defmodule BracketBattleWeb.Admin.AdvanceVotingLive do
  use BracketBattleWeb, :live_view

  alias BracketBattle.Tournaments

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    tournament = Tournaments.get_tournament!(id)
    IO.inspect({tournament.id, tournament.status, tournament.current_round, tournament.current_voting_region}, label: "ADVANCE: Tournament state")

    result = Tournaments.end_round_early(tournament)
    IO.inspect(result, label: "ADVANCE: Result")

    case result do
      {:ok, {:advanced, _updated}} ->
        {:ok,
         socket
         |> put_flash(:info, "Advanced to next voting period!")
         |> push_navigate(to: "/admin")}

      {:ok, {:ties_pending, tie_ids}} ->
        {:ok,
         socket
         |> put_flash(:error, "#{length(tie_ids)} matchup(s) are tied. Decide them first.")
         |> push_navigate(to: "/admin/tournaments/#{id}/matchups")}

      {:error, reason} ->
        {:ok,
         socket
         |> put_flash(:error, "Failed to advance: #{inspect(reason)}")
         |> push_navigate(to: "/admin")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900 flex items-center justify-center">
      <div class="text-white text-lg">Advancing voting period...</div>
    </div>
    """
  end
end
