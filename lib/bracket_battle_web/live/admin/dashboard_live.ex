defmodule BracketBattleWeb.Admin.DashboardLive do
  use BracketBattleWeb, :live_view

  alias BracketBattle.Tournaments
  alias BracketBattle.Brackets

  @impl true
  def mount(_params, _session, socket) do
    tournament = Tournaments.get_active_tournament()
    all_tournaments = Tournaments.list_tournaments()

    stats = if tournament do
      %{
        contestants: Tournaments.count_contestants(tournament.id),
        brackets: Brackets.count_submitted_brackets(tournament.id),
        current_round: tournament.current_round,
        status: tournament.status
      }
    else
      nil
    end

    brackets = if tournament do
      Brackets.list_submitted_brackets(tournament.id)
    else
      []
    end

    {:ok,
     assign(socket,
       page_title: "Admin Dashboard",
       tournament: tournament,
       all_tournaments: all_tournaments,
       stats: stats,
       brackets: brackets
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900">
      <!-- Admin Header -->
      <header class="bg-gray-800 border-b border-gray-700">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between items-center h-16">
            <div class="flex items-center space-x-4">
              <a href="/" class="text-gray-400 hover:text-white text-sm">
                &larr; Back to Site
              </a>
              <h1 class="text-xl font-bold text-white">Admin Dashboard</h1>
            </div>
            <nav class="flex items-center space-x-4">
              <.link navigate="/admin/tournaments" class="text-gray-400 hover:text-white text-sm">
                Tournaments
              </.link>
              <span class="text-gray-600">|</span>
              <span class="text-purple-400 text-sm">
                <%= @current_user.email %>
              </span>
            </nav>
          </div>
        </div>
      </header>

      <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Quick Stats -->
        <%= if @stats do %>
          <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-8">
            <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
              <div class="text-gray-400 text-sm">Status</div>
              <div class="text-xl font-bold text-white capitalize"><%= @stats.status %></div>
            </div>
            <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
              <div class="text-gray-400 text-sm">Contestants</div>
              <div class="text-xl font-bold text-white"><%= @stats.contestants %>/64</div>
            </div>
            <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
              <div class="text-gray-400 text-sm">Brackets Submitted</div>
              <div class="text-xl font-bold text-white"><%= @stats.brackets %></div>
            </div>
            <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
              <div class="text-gray-400 text-sm">Current Round</div>
              <div class="text-xl font-bold text-white">
                <%= if @stats.current_round > 0, do: @stats.current_round, else: "Not Started" %>
              </div>
            </div>
          </div>
        <% end %>

        <!-- Active Tournament -->
        <div class="mb-8">
          <h2 class="text-lg font-semibold text-white mb-4">Active Tournament</h2>
          <%= if @tournament do %>
            <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
              <div class="flex justify-between items-start">
                <div>
                  <h3 class="text-xl font-bold text-white"><%= @tournament.name %></h3>
                  <p class="text-gray-400 mt-1"><%= @tournament.description %></p>
                  <p class="text-gray-500 text-sm mt-2">
                    Created by <%= @tournament.created_by.email %>
                  </p>
                </div>
                <div class="flex space-x-2">
                  <.link
                    navigate={"/admin/tournaments/#{@tournament.id}/contestants"}
                    class="bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded text-sm"
                  >
                    Contestants
                  </.link>
                  <.link
                    navigate={"/admin/tournaments/#{@tournament.id}/matchups"}
                    class="bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded text-sm"
                  >
                    Matchups
                  </.link>
                  <.link
                    navigate={"/admin/tournaments/#{@tournament.id}"}
                    class="bg-purple-600 hover:bg-purple-700 text-white px-4 py-2 rounded text-sm"
                  >
                    Manage
                  </.link>
                </div>
              </div>

              <!-- State Actions -->
              <div class="mt-6 pt-4 border-t border-gray-700">
                <div class="flex items-center space-x-4">
                  <span class="text-gray-400 text-sm">Actions:</span>
                  <%= case @tournament.status do %>
                    <% "draft" -> %>
                      <button
                        phx-click="open_registration"
                        phx-value-id={@tournament.id}
                        class="bg-green-600 hover:bg-green-700 text-white px-4 py-2 rounded text-sm disabled:opacity-50"
                        disabled={@stats.contestants != 64}
                      >
                        Open Registration
                        <%= if @stats.contestants != 64 do %>
                          (<%= @stats.contestants %>/64 contestants)
                        <% end %>
                      </button>
                    <% "registration" -> %>
                      <button
                        phx-click="start_tournament"
                        phx-value-id={@tournament.id}
                        class="bg-green-600 hover:bg-green-700 text-white px-4 py-2 rounded text-sm"
                      >
                        Start Tournament
                      </button>
                    <% "active" -> %>
                      <button
                        phx-click="end_round_early"
                        phx-value-id={@tournament.id}
                        class="bg-orange-600 hover:bg-orange-700 text-white px-4 py-2 rounded text-sm"
                      >
                        End Round Early
                      </button>
                      <button
                        phx-click="advance_round"
                        phx-value-id={@tournament.id}
                        class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded text-sm"
                      >
                        Advance to Round <%= @tournament.current_round + 1 %>
                      </button>
                    <% "completed" -> %>
                      <span class="text-green-400 text-sm">Tournament Complete</span>
                  <% end %>
                </div>
              </div>
            </div>
          <% else %>
            <div class="bg-gray-800 rounded-lg p-6 border border-gray-700 text-center">
              <p class="text-gray-400 mb-4">No active tournament</p>
              <.link
                navigate="/admin/tournaments/new"
                class="inline-block bg-purple-600 hover:bg-purple-700 text-white px-6 py-2 rounded"
              >
                Create Tournament
              </.link>
            </div>
          <% end %>
        </div>

        <!-- Submitted Brackets -->
        <%= if @tournament do %>
          <div class="mb-8">
            <h2 class="text-lg font-semibold text-white mb-4">
              Submitted Brackets (<%= length(@brackets) %>)
            </h2>
            <%= if Enum.empty?(@brackets) do %>
              <div class="bg-gray-800 rounded-lg p-6 border border-gray-700 text-center">
                <p class="text-gray-400">No brackets submitted yet.</p>
              </div>
            <% else %>
              <div class="bg-gray-800 rounded-lg border border-gray-700 overflow-hidden">
                <table class="w-full">
                  <thead class="bg-gray-750">
                    <tr class="border-b border-gray-700">
                      <th class="text-left text-gray-400 text-sm font-medium px-4 py-3">User</th>
                      <th class="text-left text-gray-400 text-sm font-medium px-4 py-3">Submitted</th>
                      <th class="text-right text-gray-400 text-sm font-medium px-4 py-3">Score</th>
                    </tr>
                  </thead>
                  <tbody>
                    <%= for bracket <- @brackets do %>
                      <tr class="border-b border-gray-700 last:border-0 hover:bg-gray-750">
                        <td class="px-4 py-3 text-white">
                          <%= bracket.user.display_name || bracket.user.email %>
                        </td>
                        <td class="px-4 py-3 text-gray-400 text-sm">
                          <%= Calendar.strftime(bracket.submitted_at, "%b %d, %I:%M %p") %>
                        </td>
                        <td class="px-4 py-3 text-right">
                          <span class="text-purple-400 font-medium"><%= bracket.total_score %> pts</span>
                          <span class="text-gray-500 text-sm ml-2">(<%= bracket.correct_picks %> correct)</span>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            <% end %>
          </div>
        <% end %>

        <!-- All Tournaments -->
        <div>
          <div class="flex justify-between items-center mb-4">
            <h2 class="text-lg font-semibold text-white">All Tournaments</h2>
            <.link
              navigate="/admin/tournaments/new"
              class="bg-purple-600 hover:bg-purple-700 text-white px-4 py-2 rounded text-sm"
            >
              + New Tournament
            </.link>
          </div>

          <%= if Enum.empty?(@all_tournaments) do %>
            <p class="text-gray-500">No tournaments yet.</p>
          <% else %>
            <div class="bg-gray-800 rounded-lg border border-gray-700 overflow-hidden">
              <table class="w-full">
                <thead class="bg-gray-750">
                  <tr class="border-b border-gray-700">
                    <th class="text-left text-gray-400 text-sm font-medium px-4 py-3">Name</th>
                    <th class="text-left text-gray-400 text-sm font-medium px-4 py-3">Status</th>
                    <th class="text-left text-gray-400 text-sm font-medium px-4 py-3">Created</th>
                    <th class="text-right text-gray-400 text-sm font-medium px-4 py-3">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <%= for tournament <- @all_tournaments do %>
                    <tr class="border-b border-gray-700 last:border-0">
                      <td class="px-4 py-3 text-white"><%= tournament.name %></td>
                      <td class="px-4 py-3">
                        <span class={"px-2 py-1 rounded text-xs font-medium #{status_color(tournament.status)}"}>
                          <%= tournament.status %>
                        </span>
                      </td>
                      <td class="px-4 py-3 text-gray-400 text-sm">
                        <%= Calendar.strftime(tournament.inserted_at, "%b %d, %Y") %>
                      </td>
                      <td class="px-4 py-3 text-right">
                        <.link
                          navigate={"/admin/tournaments/#{tournament.id}"}
                          class="text-purple-400 hover:text-purple-300 text-sm"
                        >
                          Edit
                        </.link>
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

  @impl true
  def handle_event("open_registration", %{"id" => id}, socket) do
    tournament = Tournaments.get_tournament!(id)

    case Tournaments.open_registration(tournament) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Registration is now open!")
         |> assign(tournament: updated, stats: update_stats(updated))}

      {:error, :incomplete_contestants} ->
        {:noreply, put_flash(socket, :error, "Need exactly 64 contestants to open registration")}
    end
  end

  def handle_event("start_tournament", %{"id" => id}, socket) do
    tournament = Tournaments.get_tournament!(id)

    case Tournaments.start_tournament(tournament) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tournament started! Round 1 voting is now open.")
         |> assign(tournament: updated, stats: update_stats(updated))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to start: #{inspect(reason)}")}
    end
  end

  def handle_event("advance_round", %{"id" => id}, socket) do
    tournament = Tournaments.get_tournament!(id)

    case Tournaments.advance_round(tournament) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Advanced to round #{updated.current_round}!")
         |> assign(tournament: updated, stats: update_stats(updated))}

      {:error, :matchups_pending} ->
        {:noreply, put_flash(socket, :error, "Some matchups are still pending. Decide ties first.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to advance: #{inspect(reason)}")}
    end
  end

  def handle_event("end_round_early", %{"id" => id}, socket) do
    tournament = Tournaments.get_tournament!(id)

    case Tournaments.end_round_early(tournament) do
      {:ok, {:advanced, updated}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Round ended! Advanced to round #{updated.current_round}.")
         |> assign(tournament: updated, stats: update_stats(updated))}

      {:ok, {:ties_pending, tie_ids}} ->
        {:noreply,
         socket
         |> put_flash(:warning, "#{length(tie_ids)} matchup(s) are tied. Please break ties in Matchups page first.")
         |> assign(tournament: Tournaments.get_tournament!(id), stats: update_stats(tournament))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  defp update_stats(tournament) do
    %{
      contestants: Tournaments.count_contestants(tournament.id),
      brackets: Brackets.count_submitted_brackets(tournament.id),
      current_round: tournament.current_round,
      status: tournament.status
    }
  end

  defp status_color("draft"), do: "bg-gray-600 text-gray-200"
  defp status_color("registration"), do: "bg-blue-600 text-blue-100"
  defp status_color("active"), do: "bg-green-600 text-green-100"
  defp status_color("completed"), do: "bg-purple-600 text-purple-100"
  defp status_color(_), do: "bg-gray-600 text-gray-200"
end
