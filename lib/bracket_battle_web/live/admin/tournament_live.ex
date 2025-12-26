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
    tournament = %Tournament{
      bracket_size: 64,
      region_count: 4,
      region_names: Tournament.default_regions()
    }
    changeset = Tournament.changeset(tournament, %{})

    socket
    |> assign(:page_title, "New Tournament")
    |> assign(:tournament, tournament)
    |> assign(:form, to_form(changeset))
    |> assign(:show_round_names, false)
    |> assign(:bracket_size, 64)
    |> assign(:region_count, 4)
    |> assign(:region_names, Tournament.default_regions())
    |> assign(:round_names, %{})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    tournament = Tournaments.get_tournament!(id)
    changeset = Tournament.changeset(tournament, %{})

    socket
    |> assign(:page_title, "Edit: #{tournament.name}")
    |> assign(:tournament, tournament)
    |> assign(:form, to_form(changeset))
    |> assign(:show_round_names, false)
    |> assign(:bracket_size, tournament.bracket_size || 64)
    |> assign(:region_count, tournament.region_count || 4)
    |> assign(:region_names, tournament.region_names || Tournament.default_regions())
    |> assign(:round_names, tournament.round_names || %{})
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
          <.tournament_form
            form={@form}
            tournament={@tournament}
            action={@live_action}
            bracket_size={@bracket_size}
            region_count={@region_count}
            region_names={@region_names}
            round_names={@round_names}
            show_round_names={@show_round_names}
          />
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
    total_rounds = trunc(:math.log2(assigns.bracket_size))
    contestants_per_region = div(assigns.bracket_size, assigns.region_count)
    assigns = assign(assigns, :total_rounds, total_rounds)
    assigns = assign(assigns, :contestants_per_region, contestants_per_region)

    ~H"""
    <div class="max-w-2xl">
      <.form for={@form} phx-submit="save" phx-change="validate" class="space-y-6">
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

        <!-- Tournament Configuration -->
        <%= if !@tournament.id || @tournament.status == "draft" do %>
          <div class="border-t border-gray-700 pt-6 mt-6">
            <h3 class="text-lg font-semibold text-white mb-4">Tournament Configuration</h3>

            <div class="grid grid-cols-2 gap-4 mb-4">
              <div>
                <label class="block text-sm font-medium text-gray-300 mb-2">Bracket Size</label>
                <select
                  name="tournament[bracket_size]"
                  phx-change="update_config"
                  class="w-full bg-gray-800 border-gray-600 text-white rounded-lg px-4 py-2"
                >
                  <%= for size <- [8, 16, 32, 64, 128] do %>
                    <option value={size} selected={@bracket_size == size}>
                      <%= size %> contestants
                    </option>
                  <% end %>
                </select>
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-300 mb-2">Number of Regions</label>
                <select
                  name="tournament[region_count]"
                  phx-change="update_config"
                  class="w-full bg-gray-800 border-gray-600 text-white rounded-lg px-4 py-2"
                >
                  <%= for count <- valid_region_counts(@bracket_size) do %>
                    <option value={count} selected={@region_count == count}>
                      <%= count %> regions (<%= div(@bracket_size, count) %> per region)
                    </option>
                  <% end %>
                </select>
              </div>
            </div>

            <p class="text-gray-500 text-sm mb-4">
              <%= @bracket_size %> contestants / <%= @region_count %> regions = <%= @contestants_per_region %> per region, <%= @total_rounds %> rounds
            </p>

            <!-- Region Names -->
            <div class="mb-4">
              <label class="block text-sm font-medium text-gray-300 mb-2">Region Names</label>
              <div class="grid grid-cols-2 gap-2">
                <%= for i <- 0..(@region_count - 1) do %>
                  <input
                    type="text"
                    name={"tournament[region_names][#{i}]"}
                    value={Enum.at(@region_names, i, "Region #{i + 1}")}
                    placeholder={"Region #{i + 1}"}
                    class="bg-gray-800 border-gray-600 text-white rounded px-3 py-2 text-sm"
                  />
                <% end %>
              </div>
            </div>

            <!-- Custom Round Names (Collapsible) -->
            <div class="mb-4">
              <button
                type="button"
                phx-click="toggle_round_names"
                class="text-purple-400 hover:text-purple-300 text-sm flex items-center"
              >
                <svg class={"w-4 h-4 mr-1 transition-transform #{if @show_round_names, do: "rotate-90"}"} fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                </svg>
                Custom Round Names
              </button>

              <%= if @show_round_names do %>
                <div class="mt-3 space-y-2 pl-5">
                  <%= for round <- 1..@total_rounds do %>
                    <div class="flex items-center space-x-2">
                      <span class="text-gray-400 text-sm w-20">Round <%= round %>:</span>
                      <input
                        type="text"
                        name={"tournament[round_names][#{round}]"}
                        value={Map.get(@round_names, round) || Map.get(@round_names, to_string(round), "")}
                        placeholder={default_round_name(round, @total_rounds)}
                        class="flex-1 bg-gray-800 border-gray-600 text-white rounded px-3 py-2 text-sm"
                      />
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        <% else %>
          <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
            <p class="text-gray-400 text-sm">
              Configuration locked: <%= @bracket_size %> contestants, <%= @region_count %> regions
            </p>
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
              Manage Contestants (<%= length(@tournament.contestants) %>/<%= @bracket_size %>)
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
    # Process region_names from indexed map to list
    params = process_region_names(params)
    # Process round_names similarly
    params = process_round_names(params)

    save_tournament(socket, socket.assigns.live_action, params)
  end

  def handle_event("validate", %{"tournament" => params}, socket) do
    params = process_region_names(params)
    params = process_round_names(params)

    changeset =
      socket.assigns.tournament
      |> Tournament.changeset(params)
      |> Map.put(:action, :validate)

    # Update region_names and round_names assigns to preserve what user typed
    region_names = params["region_names"] || socket.assigns.region_names
    round_names = params["round_names"] || socket.assigns.round_names

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:region_names, region_names)
     |> assign(:round_names, round_names)}
  end

  def handle_event("update_config", %{"tournament" => params}, socket) do
    bracket_size = String.to_integer(params["bracket_size"] || "64")
    region_count = String.to_integer(params["region_count"] || "4")

    # Ensure region_count is valid for bracket_size
    valid_counts = valid_region_counts(bracket_size)
    region_count = if region_count in valid_counts, do: region_count, else: hd(valid_counts)

    # Adjust region names if count changed
    current_names = socket.assigns.region_names
    region_names = adjust_region_names(current_names, region_count)

    {:noreply,
     socket
     |> assign(:bracket_size, bracket_size)
     |> assign(:region_count, region_count)
     |> assign(:region_names, region_names)}
  end

  def handle_event("toggle_round_names", _, socket) do
    {:noreply, assign(socket, :show_round_names, !socket.assigns.show_round_names)}
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

  defp process_region_names(%{"region_names" => names} = params) when is_map(names) do
    # Convert indexed map to list, filtering out Phoenix's _unused_* keys
    list = names
    |> Enum.reject(fn {k, _} -> String.starts_with?(k, "_") end)
    |> Enum.sort_by(fn {k, _} -> String.to_integer(k) end)
    |> Enum.map(fn {_, v} -> v end)

    Map.put(params, "region_names", list)
  end
  defp process_region_names(params), do: params

  defp process_round_names(%{"round_names" => names} = params) when is_map(names) do
    # Filter out empty values and Phoenix's _unused_* keys, convert keys to integers
    cleaned = names
    |> Enum.reject(fn {k, v} -> v == "" || String.starts_with?(k, "_") end)
    |> Map.new(fn {k, v} -> {String.to_integer(k), v} end)

    Map.put(params, "round_names", cleaned)
  end
  defp process_round_names(params), do: params

  defp adjust_region_names(current, count) when length(current) >= count do
    Enum.take(current, count)
  end
  defp adjust_region_names(current, count) do
    # Add default names for new regions
    current ++ Enum.map((length(current) + 1)..count, &"Region #{&1}")
  end

  defp save_tournament(socket, :new, params) do
    case Tournaments.create_tournament(params, socket.assigns.current_user) do
      {:ok, tournament} ->
        {:noreply,
         socket
         |> put_flash(:info, "Tournament created! Now add #{tournament.bracket_size} contestants.")
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

  # Get valid region counts for a bracket size (must divide evenly)
  defp valid_region_counts(bracket_size) do
    Enum.filter(2..8, fn count ->
      rem(bracket_size, count) == 0 && div(bracket_size, count) >= 2
    end)
  end

  # Generate default round names based on total rounds
  defp default_round_name(round, total_rounds) do
    cond do
      round == total_rounds -> "Championship"
      round == total_rounds - 1 -> "Final Four"
      round == total_rounds - 2 -> "Elite 8"
      round == total_rounds - 3 -> "Sweet 16"
      true -> "Round #{round}"
    end
  end
end
