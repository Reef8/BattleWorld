defmodule BracketBattleWeb.Admin.MatchupsLive do
  use BracketBattleWeb, :live_view

  alias BracketBattle.Tournaments
  alias BracketBattle.Voting

  @impl true
  def mount(%{"id" => tournament_id}, _session, socket) do
    tournament = Tournaments.get_tournament!(tournament_id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(BracketBattle.PubSub, "tournament:#{tournament_id}")
      Phoenix.PubSub.subscribe(BracketBattle.PubSub, "tournament:#{tournament_id}:votes")
    end

    {:ok,
     socket
     |> assign(page_title: "Matchups - #{tournament.name}")
     |> assign(tournament: tournament)
     |> assign(selected_round: tournament.current_round)
     |> assign(expanded: MapSet.new())
     |> load_matchups()}
  end

  defp load_matchups(socket) do
    round = socket.assigns.selected_round
    expanded = socket.assigns.expanded

    matchups =
      if round > 0 do
        Tournaments.get_matchups_by_round(socket.assigns.tournament.id, round)
      else
        []
      end

    # Get vote counts and voter details for each matchup
    matchups_with_votes =
      Enum.map(matchups, fn matchup ->
        counts = Voting.get_vote_counts(matchup.id)

        votes = if MapSet.member?(expanded, matchup.id) do
          Voting.list_votes_for_matchup(matchup.id)
        else
          []
        end

        matchup
        |> Map.put(:vote_counts, counts)
        |> Map.put(:votes, votes)
      end)

    assign(socket, matchups: matchups_with_votes)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900">
      <!-- Header -->
      <header class="bg-gray-800 border-b border-gray-700">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between items-center h-16">
            <div class="flex items-center space-x-4">
              <.link navigate={"/admin/tournaments/#{@tournament.id}"} class="text-gray-400 hover:text-white text-sm">
                &larr; Back to Tournament
              </.link>
              <h1 class="text-xl font-bold text-white"><%= @page_title %></h1>
            </div>
            <div class="flex items-center space-x-2">
              <span class={"px-2 py-1 rounded text-xs font-medium #{status_color(@tournament.status)}"}>
                <%= @tournament.status %>
              </span>
            </div>
          </div>
        </div>
      </header>

      <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <%= if @tournament.status not in ["active", "completed"] do %>
          <div class="bg-gray-800 rounded-lg p-8 border border-gray-700 text-center">
            <p class="text-gray-400">
              Tournament hasn't started yet. Matchups will appear once the tournament begins.
            </p>
          </div>
        <% else %>
          <!-- Round Selector -->
          <div class="flex space-x-2 mb-6">
            <%= for round <- 1..6 do %>
              <button
                phx-click="select_round"
                phx-value-round={round}
                disabled={round > @tournament.current_round and @tournament.status != "completed"}
                class={"px-4 py-2 rounded text-sm font-medium transition-colors #{cond do
                  @selected_round == round -> "bg-purple-600 text-white"
                  round > @tournament.current_round and @tournament.status != "completed" -> "bg-gray-800 text-gray-600 cursor-not-allowed"
                  true -> "bg-gray-700 text-gray-300 hover:bg-gray-600"
                end}"}
              >
                <%= round_name(round) %>
              </button>
            <% end %>
          </div>

          <!-- Matchups Grid -->
          <%= if Enum.empty?(@matchups) do %>
            <div class="bg-gray-800 rounded-lg p-8 border border-gray-700 text-center">
              <p class="text-gray-400">No matchups for this round yet.</p>
            </div>
          <% else %>
            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
              <%= for matchup <- @matchups do %>
                <.matchup_card matchup={matchup} expanded={MapSet.member?(@expanded, matchup.id)} />
              <% end %>
            </div>
          <% end %>
        <% end %>
      </main>
    </div>
    """
  end

  defp matchup_card(assigns) do
    c1_votes = Map.get(assigns.matchup.vote_counts, assigns.matchup.contestant_1_id, 0)
    c2_votes = Map.get(assigns.matchup.vote_counts, assigns.matchup.contestant_2_id, 0)
    total_votes = c1_votes + c2_votes
    is_tie = c1_votes == c2_votes and total_votes > 0

    assigns =
      assigns
      |> assign(:c1_votes, c1_votes)
      |> assign(:c2_votes, c2_votes)
      |> assign(:total_votes, total_votes)
      |> assign(:is_tie, is_tie)

    ~H"""
    <div class={"bg-gray-800 rounded-lg border overflow-hidden #{matchup_border(@matchup.status, @is_tie)}"}>
      <!-- Header -->
      <div class="bg-gray-750 px-3 py-2 border-b border-gray-700 flex justify-between items-center">
        <span class="text-gray-400 text-xs">
          <%= if @matchup.region, do: @matchup.region, else: "Final Four+" %>
        </span>
        <span class={"text-xs font-medium #{status_badge(@matchup.status)}"}>
          <%= @matchup.status %>
        </span>
      </div>

      <!-- Contestants -->
      <div class="p-3 space-y-2">
        <!-- Contestant 1 -->
        <div class={"flex items-center justify-between p-2 rounded #{if @matchup.winner_id == @matchup.contestant_1_id, do: "bg-green-900/30 border border-green-700", else: "bg-gray-700/50"}"}>
          <div class="flex items-center space-x-2">
            <span class="text-gray-500 text-xs"><%= @matchup.contestant_1 && @matchup.contestant_1.seed %></span>
            <span class="text-white text-sm"><%= @matchup.contestant_1 && @matchup.contestant_1.name || "TBD" %></span>
          </div>
          <span class="text-gray-400 text-sm font-mono"><%= @c1_votes %></span>
        </div>

        <!-- Contestant 2 -->
        <div class={"flex items-center justify-between p-2 rounded #{if @matchup.winner_id == @matchup.contestant_2_id, do: "bg-green-900/30 border border-green-700", else: "bg-gray-700/50"}"}>
          <div class="flex items-center space-x-2">
            <span class="text-gray-500 text-xs"><%= @matchup.contestant_2 && @matchup.contestant_2.seed %></span>
            <span class="text-white text-sm"><%= @matchup.contestant_2 && @matchup.contestant_2.name || "TBD" %></span>
          </div>
          <span class="text-gray-400 text-sm font-mono"><%= @c2_votes %></span>
        </div>
      </div>

      <!-- Footer with Actions -->
      <div class="px-3 py-2 bg-gray-750 border-t border-gray-700">
        <%= cond do %>
          <% @matchup.status == "decided" -> %>
            <div class="flex items-center justify-between">
              <span class="text-green-400 text-xs">
                Winner: <%= @matchup.winner && @matchup.winner.name %>
              </span>
              <%= if @matchup.admin_decided do %>
                <span class="text-yellow-400 text-xs">(Admin decided)</span>
              <% end %>
            </div>

          <% @matchup.status == "voting" and @is_tie -> %>
            <div class="space-y-2">
              <div class="text-yellow-400 text-xs">Tie! Admin decision required:</div>
              <div class="flex space-x-2">
                <button
                  phx-click="decide"
                  phx-value-matchup={@matchup.id}
                  phx-value-winner={@matchup.contestant_1_id}
                  class="flex-1 bg-purple-600 hover:bg-purple-700 text-white text-xs py-1 rounded"
                >
                  <%= @matchup.contestant_1 && @matchup.contestant_1.name %>
                </button>
                <button
                  phx-click="decide"
                  phx-value-matchup={@matchup.id}
                  phx-value-winner={@matchup.contestant_2_id}
                  class="flex-1 bg-purple-600 hover:bg-purple-700 text-white text-xs py-1 rounded"
                >
                  <%= @matchup.contestant_2 && @matchup.contestant_2.name %>
                </button>
              </div>
            </div>

          <% @matchup.status == "voting" -> %>
            <div class="flex items-center justify-between">
              <span class="text-gray-400 text-xs">
                <%= @total_votes %> votes
              </span>
              <%= if @matchup.voting_ends_at do %>
                <span class="text-gray-500 text-xs">
                  Ends: <%= format_time(@matchup.voting_ends_at) %>
                </span>
              <% end %>
            </div>

          <% true -> %>
            <span class="text-gray-500 text-xs">Pending</span>
        <% end %>
      </div>

      <!-- Voters Toggle -->
      <%= if @total_votes > 0 do %>
        <div class="px-3 py-2 border-t border-gray-700">
          <button
            phx-click="toggle_voters"
            phx-value-matchup={@matchup.id}
            class="text-purple-400 hover:text-purple-300 text-xs flex items-center"
          >
            <%= if @expanded do %>
              <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 15l7-7 7 7" />
              </svg>
              Hide Voters
            <% else %>
              <svg class="w-3 h-3 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
              </svg>
              Show Voters (<%= @total_votes %>)
            <% end %>
          </button>

          <%= if @expanded and length(@matchup.votes) > 0 do %>
            <div class="mt-2 pt-2 border-t border-gray-600 max-h-48 overflow-y-auto">
              <%= for vote <- @matchup.votes do %>
                <div class="flex justify-between items-center text-xs py-1">
                  <span class="text-gray-300 truncate flex-1 mr-2">
                    <%= vote.user.display_name || vote.user.email %>
                  </span>
                  <span class={if vote.contestant_id == @matchup.contestant_1_id,
                    do: "text-blue-400 whitespace-nowrap", else: "text-green-400 whitespace-nowrap"}>
                    → <%= vote.contestant.name %>
                  </span>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("select_round", %{"round" => round}, socket) do
    {:noreply,
     socket
     |> assign(selected_round: String.to_integer(round))
     |> load_matchups()}
  end

  def handle_event("toggle_voters", %{"matchup" => matchup_id}, socket) do
    expanded = socket.assigns.expanded

    new_expanded = if MapSet.member?(expanded, matchup_id) do
      MapSet.delete(expanded, matchup_id)
    else
      MapSet.put(expanded, matchup_id)
    end

    {:noreply,
     socket
     |> assign(expanded: new_expanded)
     |> load_matchups()}
  end

  def handle_event("decide", %{"matchup" => matchup_id, "winner" => winner_id}, socket) do
    matchup = Tournaments.get_matchup!(matchup_id)

    case Tournaments.decide_matchup(matchup, winner_id, true) do
      {:ok, _} ->
        {:noreply,
         socket
         |> load_matchups()
         |> put_flash(:info, "Winner decided!")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to decide winner")}
    end
  end

  @impl true
  def handle_info({:vote_cast, %{matchup_id: _}}, socket) do
    {:noreply, load_matchups(socket)}
  end

  def handle_info({:matchup_updated, _}, socket) do
    {:noreply, load_matchups(socket)}
  end

  def handle_info({:tournament_updated, tournament}, socket) do
    {:noreply, assign(socket, tournament: tournament)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  defp round_name(1), do: "Round 1"
  defp round_name(2), do: "Round 2"
  defp round_name(3), do: "Sweet 16"
  defp round_name(4), do: "Elite 8"
  defp round_name(5), do: "Final 4"
  defp round_name(6), do: "Championship"

  defp status_color("draft"), do: "bg-gray-600 text-gray-200"
  defp status_color("registration"), do: "bg-blue-600 text-blue-100"
  defp status_color("active"), do: "bg-green-600 text-green-100"
  defp status_color("completed"), do: "bg-purple-600 text-purple-100"
  defp status_color(_), do: "bg-gray-600 text-gray-200"

  defp status_badge("pending"), do: "text-gray-400"
  defp status_badge("voting"), do: "text-blue-400"
  defp status_badge("decided"), do: "text-green-400"
  defp status_badge(_), do: "text-gray-400"

  defp matchup_border("decided", _), do: "border-green-700"
  defp matchup_border("voting", true), do: "border-yellow-500"
  defp matchup_border("voting", _), do: "border-blue-700"
  defp matchup_border(_, _), do: "border-gray-700"

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%b %d, %I:%M %p")
  end
end
