defmodule BracketBattleWeb.Admin.TournamentLive do
  use BracketBattleWeb, :live_view

  alias BracketBattle.Tournaments
  alias BracketBattle.Tournaments.Tournament

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, all_tournaments: Tournaments.list_tournaments())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Tournaments")
    |> assign(:tournament, nil)
    |> assign(:form, nil)
  end

  defp apply_action(socket, :new, _params) do
    changeset = Tournament.changeset(%Tournament{}, %{})

    socket
    |> assign(:page_title, "New Tournament")
    |> assign(:tournament, %Tournament{})
    |> assign(:form, to_form(changeset))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    tournament = Tournaments.get_tournament!(id)
    changeset = Tournament.changeset(tournament, %{})

    socket
    |> assign(:page_title, "Edit: #{tournament.name}")
    |> assign(:tournament, tournament)
    |> assign(:form, to_form(changeset))
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
              <.link navigate="/admin" class="text-gray-400 hover:text-white text-sm">
                &larr; Dashboard
              </.link>
              <h1 class="text-xl font-bold text-white"><%= @page_title %></h1>
            </div>
          </div>
        </div>
      </header>

      <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <%= if @live_action == :index do %>
          <.tournament_list tournaments={@all_tournaments} />
        <% else %>
          <.tournament_form form={@form} tournament={@tournament} action={@live_action} />
        <% end %>
      </main>
    </div>
    """
  end

  defp tournament_list(assigns) do
    ~H"""
    <div>
      <div class="flex justify-between items-center mb-6">
        <h2 class="text-lg font-semibold text-white">All Tournaments</h2>
        <.link
          navigate="/admin/tournaments/new"
          class="bg-purple-600 hover:bg-purple-700 text-white px-4 py-2 rounded text-sm"
        >
          + New Tournament
        </.link>
      </div>

      <%= if Enum.empty?(@tournaments) do %>
        <div class="bg-gray-800 rounded-lg p-8 border border-gray-700 text-center">
          <p class="text-gray-400 mb-4">No tournaments yet. Create your first one!</p>
          <.link
            navigate="/admin/tournaments/new"
            class="inline-block bg-purple-600 hover:bg-purple-700 text-white px-6 py-2 rounded"
          >
            Create Tournament
          </.link>
        </div>
      <% else %>
        <div class="space-y-4">
          <%= for tournament <- @tournaments do %>
            <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
              <div class="flex justify-between items-start">
                <div>
                  <h3 class="text-xl font-bold text-white"><%= tournament.name %></h3>
                  <p class="text-gray-400 mt-1"><%= tournament.description || "No description" %></p>
                  <div class="flex items-center space-x-4 mt-3">
                    <span class={"px-2 py-1 rounded text-xs font-medium #{status_color(tournament.status)}"}>
                      <%= tournament.status %>
                    </span>
                    <span class="text-gray-500 text-sm">
                      Created <%= Calendar.strftime(tournament.inserted_at, "%b %d, %Y") %>
                    </span>
                  </div>
                </div>
                <div class="flex space-x-2">
                  <.link
                    navigate={"/admin/tournaments/#{tournament.id}/contestants"}
                    class="bg-gray-700 hover:bg-gray-600 text-white px-3 py-2 rounded text-sm"
                  >
                    Contestants
                  </.link>
                  <.link
                    navigate={"/admin/tournaments/#{tournament.id}"}
                    class="bg-purple-600 hover:bg-purple-700 text-white px-3 py-2 rounded text-sm"
                  >
                    Edit
                  </.link>
                  <button
                    phx-click="delete"
                    phx-value-id={tournament.id}
                    data-confirm="Are you sure you want to delete this tournament? This cannot be undone."
                    class="bg-red-600 hover:bg-red-700 text-white px-3 py-2 rounded text-sm"
                  >
                    Delete
                  </button>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp tournament_form(assigns) do
    ~H"""
    <div class="max-w-2xl">
      <.form for={@form} phx-submit="save" class="space-y-6">
        <div>
          <label class="block text-sm font-medium text-gray-300 mb-2">Tournament Name</label>
          <.input
            field={@form[:name]}
            type="text"
            placeholder="e.g., Marvel Showdown 2025"
            class="w-full bg-gray-800 border-gray-600 text-white rounded-lg px-4 py-2 focus:ring-purple-500 focus:border-purple-500"
          />
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-300 mb-2">Description</label>
          <.input
            field={@form[:description]}
            type="textarea"
            rows="3"
            placeholder="What's this tournament about?"
            class="w-full bg-gray-800 border-gray-600 text-white rounded-lg px-4 py-2 focus:ring-purple-500 focus:border-purple-500"
          />
        </div>

        <div>
          <label class="block text-sm font-medium text-gray-300 mb-2">Registration Deadline</label>
          <.input
            field={@form[:registration_deadline]}
            type="datetime-local"
            class="w-full bg-gray-800 border-gray-600 text-white rounded-lg px-4 py-2 focus:ring-purple-500 focus:border-purple-500"
          />
          <p class="text-gray-500 text-sm mt-1">When should bracket submissions close?</p>
        </div>

        <%= if @tournament.id do %>
          <div>
            <label class="block text-sm font-medium text-gray-300 mb-2">Status</label>
            <.input
              field={@form[:status]}
              type="select"
              options={[
                {"Draft", "draft"},
                {"Registration Open", "registration"},
                {"Active", "active"},
                {"Completed", "completed"}
              ]}
              class="w-full bg-gray-800 border-gray-600 text-white rounded-lg px-4 py-2 focus:ring-purple-500 focus:border-purple-500"
            />
          </div>
        <% end %>

        <div class="flex space-x-4">
          <button
            type="submit"
            class="bg-purple-600 hover:bg-purple-700 text-white px-6 py-2 rounded-lg font-medium"
          >
            <%= if @action == :new, do: "Create Tournament", else: "Update Tournament" %>
          </button>
          <.link
            navigate="/admin/tournaments"
            class="bg-gray-700 hover:bg-gray-600 text-white px-6 py-2 rounded-lg font-medium"
          >
            Cancel
          </.link>
        </div>
      </.form>

      <%= if @tournament.id do %>
        <div class="mt-8 pt-8 border-t border-gray-700">
          <h3 class="text-lg font-semibold text-white mb-4">Quick Links</h3>
          <div class="flex space-x-4">
            <.link
              navigate={"/admin/tournaments/#{@tournament.id}/contestants"}
              class="bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded text-sm"
            >
              Manage Contestants (<%= length(@tournament.contestants) %>/64)
            </.link>
            <.link
              navigate={"/admin/tournaments/#{@tournament.id}/matchups"}
              class="bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded text-sm"
            >
              View Matchups
            </.link>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def handle_event("save", %{"tournament" => params}, socket) do
    save_tournament(socket, socket.assigns.live_action, params)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    tournament = Tournaments.get_tournament!(id)

    case Tournaments.delete_tournament(tournament) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tournament deleted")
         |> assign(:all_tournaments, Tournaments.list_tournaments())}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete tournament")}
    end
  end

  defp save_tournament(socket, :new, params) do
    case Tournaments.create_tournament(params, socket.assigns.current_user) do
      {:ok, tournament} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tournament created! Now add 64 contestants.")
         |> push_navigate(to: "/admin/tournaments/#{tournament.id}/contestants")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_tournament(socket, :edit, params) do
    case Tournaments.update_tournament(socket.assigns.tournament, params) do
      {:ok, tournament} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tournament updated")
         |> assign(:tournament, tournament)
         |> assign(:form, to_form(Tournament.changeset(tournament, %{})))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp status_color("draft"), do: "bg-gray-600 text-gray-200"
  defp status_color("registration"), do: "bg-blue-600 text-blue-100"
  defp status_color("active"), do: "bg-green-600 text-green-100"
  defp status_color("completed"), do: "bg-purple-600 text-purple-100"
  defp status_color(_), do: "bg-gray-600 text-gray-200"
end
