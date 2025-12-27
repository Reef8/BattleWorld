defmodule BracketBattleWeb.DashboardLive do
  use BracketBattleWeb, :live_view

  alias BracketBattle.Accounts
  alias BracketBattle.Brackets
  alias BracketBattle.Tournaments

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user

    # Get user's brackets across all tournaments
    brackets = Brackets.get_user_brackets(user.id)

    # Get active tournament and user's participation
    active_tournament = Tournaments.get_active_tournament()

    {current_bracket, current_rank} = if active_tournament do
      bracket = Brackets.get_user_bracket(active_tournament.id, user.id)
      rank = if bracket && bracket.submitted_at do
        Brackets.get_user_rank(active_tournament.id, user.id)
      end
      {bracket, rank}
    else
      {nil, nil}
    end

    # Separate current from past tournaments
    past_brackets = Enum.filter(brackets, fn b ->
      b.tournament && b.tournament.status == "completed" && b.submitted_at
    end)

    # Calculate ranks for past tournaments
    past_with_ranks = Enum.map(past_brackets, fn bracket ->
      rank = Brackets.get_user_rank(bracket.tournament_id, user.id)
      Map.put(bracket, :final_rank, rank)
    end)

    # Get member since date
    member_since = Accounts.get_first_bracket_date(user.id)

    {:ok,
     assign(socket,
       page_title: "My Dashboard",
       user: user,
       display_name_input: user.display_name || "",
       active_tournament: active_tournament,
       current_bracket: current_bracket,
       current_rank: current_rank,
       past_brackets: past_with_ranks,
       member_since: member_since,
       editing_name: false
     )}
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
              <a href="/" class="text-gray-400 hover:text-white text-sm">&larr; Home</a>
              <h1 class="text-xl font-bold text-white">My Dashboard</h1>
            </div>
            <nav class="flex items-center space-x-4">
              <%= if @user.is_admin do %>
                <a href="/admin" class="text-purple-400 hover:text-purple-300 text-sm">
                  Admin
                </a>
              <% end %>
              <a href="/auth/signout" class="text-gray-400 hover:text-white text-sm">
                Sign Out
              </a>
            </nav>
          </div>
        </div>
      </header>

      <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <!-- Profile Card -->
          <div class="bg-gray-800 rounded-xl border border-gray-700 p-6">
            <h2 class="text-lg font-semibold text-white mb-4">Profile</h2>

            <!-- Avatar placeholder -->
            <div class="w-20 h-20 bg-purple-600 rounded-full flex items-center justify-center mb-4 mx-auto">
              <span class="text-3xl text-white font-bold">
                <%= String.first(@user.display_name || @user.email) |> String.upcase() %>
              </span>
            </div>

            <!-- Display Name -->
            <div class="mb-4">
              <label class="block text-sm text-gray-400 mb-1">Display Name</label>
              <%= if @editing_name do %>
                <form phx-submit="save_display_name" class="flex space-x-2">
                  <input
                    type="text"
                    name="display_name"
                    value={@display_name_input}
                    phx-change="update_name_input"
                    class="flex-1 bg-gray-700 border border-gray-600 text-white rounded px-3 py-2 text-sm"
                    placeholder="Enter display name"
                    maxlength="50"
                    autofocus
                  />
                  <button type="submit" class="bg-purple-600 hover:bg-purple-700 text-white px-3 py-2 rounded text-sm">
                    Save
                  </button>
                  <button type="button" phx-click="cancel_edit_name" class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-2 rounded text-sm">
                    Cancel
                  </button>
                </form>
              <% else %>
                <div class="flex items-center justify-between">
                  <span class="text-white">
                    <%= @user.display_name || "Not set" %>
                  </span>
                  <button phx-click="edit_name" class="text-purple-400 hover:text-purple-300 text-sm">
                    Edit
                  </button>
                </div>
              <% end %>
            </div>

            <!-- Email -->
            <div class="mb-4">
              <label class="block text-sm text-gray-400 mb-1">Email</label>
              <span class="text-white text-sm"><%= @user.email %></span>
            </div>

            <!-- Member Since -->
            <div>
              <label class="block text-sm text-gray-400 mb-1">Member Since</label>
              <span class="text-white text-sm">
                <%= if @member_since do %>
                  <%= Calendar.strftime(@member_since, "%B %Y") %>
                <% else %>
                  No tournaments yet
                <% end %>
              </span>
            </div>
          </div>

          <!-- Current Tournament Card -->
          <div class="lg:col-span-2 bg-gray-800 rounded-xl border border-gray-700 p-6">
            <h2 class="text-lg font-semibold text-white mb-4">Current Tournament</h2>

            <%= if @active_tournament do %>
              <div class="bg-gray-750 rounded-lg p-4 border border-gray-600">
                <div class="flex justify-between items-start mb-4">
                  <div>
                    <h3 class="text-xl font-bold text-white"><%= @active_tournament.name %></h3>
                    <p class="text-gray-400 text-sm">
                      <%= status_label(@active_tournament.status) %>
                      <%= if @active_tournament.status == "active" do %>
                        • Round <%= @active_tournament.current_round %>
                      <% end %>
                    </p>
                  </div>
                  <span class={"px-3 py-1 rounded-full text-sm font-medium #{status_color(@active_tournament.status)}"}>
                    <%= @active_tournament.status %>
                  </span>
                </div>

                <%= if @current_bracket do %>
                  <div class="grid grid-cols-3 gap-4 mb-4">
                    <div class="bg-gray-700 rounded-lg p-3 text-center">
                      <div class="text-2xl font-bold text-white">
                        <%= if @current_rank, do: "##{@current_rank}", else: "-" %>
                      </div>
                      <div class="text-gray-400 text-sm">Rank</div>
                    </div>
                    <div class="bg-gray-700 rounded-lg p-3 text-center">
                      <div class="text-2xl font-bold text-purple-400"><%= @current_bracket.total_score %></div>
                      <div class="text-gray-400 text-sm">Points</div>
                    </div>
                    <div class="bg-gray-700 rounded-lg p-3 text-center">
                      <div class="text-2xl font-bold text-green-400"><%= @current_bracket.correct_picks || 0 %></div>
                      <div class="text-gray-400 text-sm">Correct</div>
                    </div>
                  </div>

                  <div class="flex space-x-3">
                    <a href={"/tournament/#{@active_tournament.id}"} class="flex-1 bg-purple-600 hover:bg-purple-700 text-white px-4 py-2 rounded-lg text-center font-medium transition-colors">
                      View Tournament
                    </a>
                    <%= if !@current_bracket.submitted_at do %>
                      <a href={"/tournament/#{@active_tournament.id}/bracket"} class="flex-1 bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded-lg text-center font-medium transition-colors">
                        Edit Bracket
                      </a>
                    <% end %>
                  </div>
                <% else %>
                  <div class="text-center py-4">
                    <p class="text-gray-400 mb-4">You haven't created a bracket for this tournament yet.</p>
                    <a href={"/tournament/#{@active_tournament.id}/bracket"} class="inline-block bg-purple-600 hover:bg-purple-700 text-white px-6 py-2 rounded-lg font-medium transition-colors">
                      Create Bracket
                    </a>
                  </div>
                <% end %>
              </div>
            <% else %>
              <div class="text-center py-8 text-gray-400">
                <p>No active tournament right now.</p>
                <p class="text-sm mt-2">Check back soon for the next battle!</p>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Tournament History -->
        <div class="mt-6 bg-gray-800 rounded-xl border border-gray-700 p-6">
          <h2 class="text-lg font-semibold text-white mb-4">Tournament History</h2>

          <%= if Enum.empty?(@past_brackets) do %>
            <div class="text-center py-8 text-gray-400">
              <p>No completed tournaments yet.</p>
              <p class="text-sm mt-2">Your tournament history will appear here.</p>
            </div>
          <% else %>
            <div class="overflow-x-auto">
              <table class="w-full">
                <thead>
                  <tr class="text-left text-gray-400 text-sm border-b border-gray-700">
                    <th class="pb-3 font-medium">Tournament</th>
                    <th class="pb-3 font-medium text-center">Final Rank</th>
                    <th class="pb-3 font-medium text-center">Score</th>
                    <th class="pb-3 font-medium text-center">Correct Picks</th>
                    <th class="pb-3 font-medium text-right">Date</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for bracket <- @past_brackets do %>
                    <tr class="border-b border-gray-700/50 hover:bg-gray-750">
                      <td class="py-3">
                        <a href={"/tournament/#{bracket.tournament_id}"} class="text-white hover:text-purple-400">
                          <%= bracket.tournament.name %>
                        </a>
                      </td>
                      <td class="py-3 text-center">
                        <span class={"font-bold #{rank_color(bracket.final_rank)}"}>
                          #<%= bracket.final_rank %>
                        </span>
                      </td>
                      <td class="py-3 text-center text-purple-400 font-medium">
                        <%= bracket.total_score %> pts
                      </td>
                      <td class="py-3 text-center text-gray-300">
                        <%= bracket.correct_picks || 0 %>
                      </td>
                      <td class="py-3 text-right text-gray-400 text-sm">
                        <%= Calendar.strftime(bracket.tournament.completed_at || bracket.submitted_at, "%b %d, %Y") %>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          <% end %>
        </div>
      </main>
    </div>
    """
  end

  # Event Handlers

  @impl true
  def handle_event("edit_name", _, socket) do
    {:noreply, assign(socket, editing_name: true, display_name_input: socket.assigns.user.display_name || "")}
  end

  def handle_event("cancel_edit_name", _, socket) do
    {:noreply, assign(socket, editing_name: false)}
  end

  def handle_event("update_name_input", %{"display_name" => name}, socket) do
    {:noreply, assign(socket, display_name_input: name)}
  end

  def handle_event("save_display_name", %{"display_name" => name}, socket) do
    name = String.trim(name)
    name = if name == "", do: nil, else: name

    case Accounts.update_display_name(socket.assigns.user, name) do
      {:ok, updated_user} ->
        {:noreply,
         socket
         |> assign(user: updated_user, editing_name: false)
         |> put_flash(:info, "Display name updated!")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not update display name")}
    end
  end

  # Helpers

  defp status_label("registration"), do: "Registration Open"
  defp status_label("active"), do: "In Progress"
  defp status_label("completed"), do: "Completed"
  defp status_label(_), do: ""

  defp status_color("registration"), do: "bg-blue-600 text-blue-100"
  defp status_color("active"), do: "bg-green-600 text-green-100"
  defp status_color("completed"), do: "bg-purple-600 text-purple-100"
  defp status_color(_), do: "bg-gray-600 text-gray-200"

  defp rank_color(1), do: "text-yellow-400"
  defp rank_color(2), do: "text-gray-300"
  defp rank_color(3), do: "text-amber-600"
  defp rank_color(_), do: "text-white"
end
