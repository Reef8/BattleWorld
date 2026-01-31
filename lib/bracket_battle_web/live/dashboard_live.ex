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
       editing_name: false,
       show_mobile_menu: false,
       instructions_expanded: false
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900">
      <!-- Header -->
      <header class="bg-gray-800 border-b border-gray-700 sticky top-0 z-10">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between items-center h-16">
            <div class="flex items-center space-x-4">
              <a href="/" class="text-gray-400 hover:text-white text-sm">&larr; Home</a>
              <h1 class="text-xl font-bold text-white">My Dashboard</h1>
            </div>

            <!-- Desktop nav -->
            <nav class="hidden md:flex items-center space-x-4">
              <%= if @user.is_admin do %>
                <a href="/admin" class="text-blue-400 hover:text-blue-300 text-sm">
                  Admin
                </a>
              <% end %>
              <a href="/auth/signout" class="text-gray-400 hover:text-white text-sm">
                Sign Out
              </a>
            </nav>

            <!-- Mobile hamburger button -->
            <button
              phx-click="toggle_mobile_menu"
              class="md:hidden p-2 text-gray-400 hover:text-white"
              aria-label="Toggle menu"
            >
              <%= if @show_mobile_menu do %>
                <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              <% else %>
                <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16" />
                </svg>
              <% end %>
            </button>
          </div>
        </div>

        <!-- Mobile menu -->
        <%= if @show_mobile_menu do %>
          <div class="md:hidden border-t border-gray-700 bg-gray-800">
            <div class="px-4 py-3 space-y-2">
              <%= if @user.is_admin do %>
                <a href="/admin" class="block py-2 text-blue-400 hover:text-blue-300">
                  Admin
                </a>
              <% end %>
              <a href="/auth/signout" class="block py-2 text-gray-400 hover:text-white">
                Sign Out
              </a>
            </div>
          </div>
        <% end %>
      </header>

      <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- How It Works Card -->
        <div class="mb-6 bg-gray-800 rounded-xl border border-gray-700">
          <button
            phx-click="toggle_instructions"
            class="w-full flex justify-between items-center p-4 text-left"
          >
            <h2 class="text-lg font-semibold text-white">How It Works</h2>
            <svg class={["w-5 h-5 text-gray-400 transition-transform", @instructions_expanded && "rotate-180"]} fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
            </svg>
          </button>

          <%= if @instructions_expanded do %>
            <div class="px-4 pb-4 border-t border-gray-700 pt-4">
              <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                <!-- Step 1: Fill Out Bracket -->
                <div class="bg-gray-750 rounded-lg p-4 border border-gray-600">
                  <div class="flex items-center mb-2">
                    <span class="w-6 h-6 bg-blue-600 rounded-full flex items-center justify-center text-white text-sm font-bold mr-2">1</span>
                    <h3 class="text-white font-medium">Fill Out Your Bracket</h3>
                  </div>
                  <p class="text-gray-400 text-sm">
                    Pick winners for every matchup before registration closes. Click on a contestant to select them as the winner. Your picks auto-save as you go.
                  </p>
                </div>

                <!-- Step 2: Submit -->
                <div class="bg-gray-750 rounded-lg p-4 border border-gray-600">
                  <div class="flex items-center mb-2">
                    <span class="w-6 h-6 bg-blue-600 rounded-full flex items-center justify-center text-white text-sm font-bold mr-2">2</span>
                    <h3 class="text-white font-medium">Submit Your Bracket</h3>
                  </div>
                  <p class="text-gray-400 text-sm">
                    Once you've made all your picks, submit your bracket to lock it in. After submitting, your bracket cannot be edited.
                  </p>
                </div>

                <!-- Step 3: Voting -->
                <div class="bg-gray-750 rounded-lg p-4 border border-gray-600">
                  <div class="flex items-center mb-2">
                    <span class="w-6 h-6 bg-blue-600 rounded-full flex items-center justify-center text-white text-sm font-bold mr-2">3</span>
                    <h3 class="text-white font-medium">Vote Each Round</h3>
                  </div>
                  <p class="text-gray-400 text-sm">
                    When the tournament starts, vote on active matchups. Each voting period covers one region's matchups for the current round. The contestant with the most votes advances.
                  </p>
                </div>

                <!-- Step 4: Points -->
                <div class="bg-gray-750 rounded-lg p-4 border border-gray-600">
                  <div class="flex items-center mb-2">
                    <span class="w-6 h-6 bg-blue-600 rounded-full flex items-center justify-center text-white text-sm font-bold mr-2">4</span>
                    <h3 class="text-white font-medium">Earn Points</h3>
                  </div>
                  <p class="text-gray-400 text-sm">
                    Score points when your bracket predictions match the voting results. Later rounds are worth more points - picking the champion correctly is huge!
                  </p>
                </div>

                <!-- Step 5: Leaderboard -->
                <div class="bg-gray-750 rounded-lg p-4 border border-gray-600">
                  <div class="flex items-center mb-2">
                    <span class="w-6 h-6 bg-blue-600 rounded-full flex items-center justify-center text-white text-sm font-bold mr-2">5</span>
                    <h3 class="text-white font-medium">Climb the Leaderboard</h3>
                  </div>
                  <p class="text-gray-400 text-sm">
                    Check the Leaderboard tab to see your rank. Ties are broken by most correct picks, then earliest submission time.
                  </p>
                </div>

                <!-- Tournament Tabs -->
                <div class="bg-gray-750 rounded-lg p-4 border border-gray-600">
                  <div class="flex items-center mb-2">
                    <svg class="w-6 h-6 text-blue-400 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h7" />
                    </svg>
                    <h3 class="text-white font-medium">Tournament Tabs</h3>
                  </div>
                  <p class="text-gray-400 text-sm">
                    <span class="text-blue-400">Bracket:</span> Live results &bull;
                    <span class="text-blue-400">Vote:</span> Cast votes &bull;
                    <span class="text-blue-400">My Bracket:</span> Your picks &bull;
                    <span class="text-blue-400">Leaderboard:</span> Rankings
                  </p>
                </div>
              </div>
            </div>
          <% end %>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <!-- Profile Card -->
          <div class="bg-gray-800 rounded-xl border border-gray-700 p-6">
            <h2 class="text-lg font-semibold text-white mb-4">Profile</h2>

            <!-- Avatar placeholder -->
            <div class="w-20 h-20 bg-blue-600 rounded-full flex items-center justify-center mb-4 mx-auto">
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
                  <button type="submit" class="bg-blue-600 hover:bg-blue-700 text-white px-3 py-2 rounded text-sm">
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
                  <button phx-click="edit_name" class="text-blue-400 hover:text-blue-300 text-sm">
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
                  <div class="grid grid-cols-3 gap-2 sm:gap-4 mb-4">
                    <div class="bg-gray-700 rounded-lg p-2 sm:p-3 text-center">
                      <div class="text-lg sm:text-2xl font-bold text-white">
                        <%= if @current_rank, do: "##{@current_rank}", else: "-" %>
                      </div>
                      <div class="text-gray-400 text-xs sm:text-sm">Rank</div>
                    </div>
                    <div class="bg-gray-700 rounded-lg p-2 sm:p-3 text-center">
                      <div class="text-lg sm:text-2xl font-bold text-blue-400"><%= @current_bracket.total_score %></div>
                      <div class="text-gray-400 text-xs sm:text-sm">Points</div>
                    </div>
                    <div class="bg-gray-700 rounded-lg p-2 sm:p-3 text-center">
                      <div class="text-lg sm:text-2xl font-bold text-green-400"><%= @current_bracket.correct_picks || 0 %></div>
                      <div class="text-gray-400 text-xs sm:text-sm">Correct</div>
                    </div>
                  </div>

                  <div class="flex flex-col sm:flex-row gap-2 sm:gap-3">
                    <a href={"/tournament/#{@active_tournament.id}"} class="flex-1 bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg text-center font-medium transition-colors">
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
                    <a href={"/tournament/#{@active_tournament.id}/bracket"} class="inline-block bg-blue-600 hover:bg-blue-700 text-white px-6 py-2 rounded-lg font-medium transition-colors">
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
              <table class="w-full min-w-[400px]">
                <thead>
                  <tr class="text-left text-gray-400 text-xs sm:text-sm border-b border-gray-700">
                    <th class="pb-2 sm:pb-3 pr-2 font-medium">Tournament</th>
                    <th class="pb-2 sm:pb-3 px-2 font-medium text-center">Rank</th>
                    <th class="pb-2 sm:pb-3 px-2 font-medium text-center">Score</th>
                    <th class="pb-2 sm:pb-3 px-2 font-medium text-center hidden sm:table-cell">Correct</th>
                    <th class="pb-2 sm:pb-3 pl-2 font-medium text-right">Date</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for bracket <- @past_brackets do %>
                    <tr class="border-b border-gray-700/50 hover:bg-gray-750">
                      <td class="py-2 sm:py-3 pr-2">
                        <a href={"/tournament/#{bracket.tournament_id}"} class="text-white hover:text-blue-400 text-sm sm:text-base">
                          <%= bracket.tournament.name %>
                        </a>
                      </td>
                      <td class="py-2 sm:py-3 px-2 text-center">
                        <span class={"font-bold text-sm sm:text-base #{rank_color(bracket.final_rank)}"}>
                          #<%= bracket.final_rank %>
                        </span>
                      </td>
                      <td class="py-2 sm:py-3 px-2 text-center text-blue-400 font-medium text-sm sm:text-base">
                        <%= bracket.total_score %>
                      </td>
                      <td class="py-2 sm:py-3 px-2 text-center text-gray-300 text-sm sm:text-base hidden sm:table-cell">
                        <%= bracket.correct_picks || 0 %>
                      </td>
                      <td class="py-2 sm:py-3 pl-2 text-right text-gray-400 text-xs sm:text-sm">
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
  def handle_event("toggle_mobile_menu", _, socket) do
    {:noreply, assign(socket, show_mobile_menu: !socket.assigns.show_mobile_menu)}
  end

  def handle_event("toggle_instructions", _, socket) do
    {:noreply, assign(socket, instructions_expanded: !socket.assigns.instructions_expanded)}
  end

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
  defp status_color("completed"), do: "bg-blue-600 text-blue-100"
  defp status_color(_), do: "bg-gray-600 text-gray-200"

  defp rank_color(1), do: "text-yellow-400"
  defp rank_color(2), do: "text-gray-300"
  defp rank_color(3), do: "text-amber-600"
  defp rank_color(_), do: "text-white"
end
