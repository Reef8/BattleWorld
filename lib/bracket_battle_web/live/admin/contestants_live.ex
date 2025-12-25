defmodule BracketBattleWeb.Admin.ContestantsLive do
  use BracketBattleWeb, :live_view

  alias BracketBattle.Tournaments
  alias BracketBattle.Tournaments.Contestant

  @impl true
  def mount(%{"id" => tournament_id}, _session, socket) do
    tournament = Tournaments.get_tournament!(tournament_id)
    contestants = Tournaments.list_contestants(tournament_id)

    # Group by region for display
    by_region = Enum.group_by(contestants, & &1.region)

    {:ok,
     assign(socket,
       page_title: "Contestants - #{tournament.name}",
       tournament: tournament,
       contestants: contestants,
       by_region: by_region,
       regions: Contestant.regions(),
       show_form: false,
       show_bulk: false,
       editing: nil,
       form: nil,
       bulk_text: "",
       bulk_region: "East"
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
              <.link navigate={"/admin/tournaments/#{@tournament.id}"} class="text-gray-400 hover:text-white text-sm">
                &larr; Back to Tournament
              </.link>
              <h1 class="text-xl font-bold text-white"><%= @page_title %></h1>
            </div>
            <div class="flex items-center space-x-2">
              <span class={"px-2 py-1 rounded text-xs font-medium #{status_color(@tournament.status)}"}>
                <%= @tournament.status %>
              </span>
              <span class="text-gray-400 text-sm">
                <%= length(@contestants) %>/64 contestants
              </span>
            </div>
          </div>
        </div>
      </header>

      <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Progress Bar -->
        <div class="mb-6">
          <div class="flex justify-between text-sm text-gray-400 mb-1">
            <span>Contestants Added</span>
            <span><%= length(@contestants) %> / 64</span>
          </div>
          <div class="w-full bg-gray-700 rounded-full h-2">
            <div
              class="bg-purple-600 h-2 rounded-full transition-all"
              style={"width: #{length(@contestants) / 64 * 100}%"}
            ></div>
          </div>
        </div>

        <!-- Actions -->
        <%= if @tournament.status == "draft" do %>
          <div class="flex space-x-4 mb-6">
            <button
              phx-click="show_form"
              class="bg-purple-600 hover:bg-purple-700 text-white px-4 py-2 rounded text-sm"
            >
              + Add Contestant
            </button>
            <button
              phx-click="show_bulk"
              class="bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded text-sm"
            >
              Bulk Import (16 at once)
            </button>
          </div>
        <% else %>
          <div class="mb-6 p-4 bg-yellow-900/20 border border-yellow-700 rounded-lg">
            <p class="text-yellow-400 text-sm">
              Tournament is no longer in draft mode. Contestants cannot be modified.
            </p>
          </div>
        <% end %>

        <!-- Add Form -->
        <%= if @show_form do %>
          <div class="mb-6 bg-gray-800 rounded-lg p-6 border border-gray-700">
            <h3 class="text-lg font-semibold text-white mb-4">
              <%= if @editing, do: "Edit Contestant", else: "Add Contestant" %>
            </h3>
            <.form for={@form} phx-submit="save_contestant" class="space-y-4">
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-sm font-medium text-gray-300 mb-1">Name</label>
                  <.input
                    field={@form[:name]}
                    type="text"
                    placeholder="e.g., Spider-Man"
                    class="w-full bg-gray-700 border-gray-600 text-white rounded px-3 py-2"
                  />
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-300 mb-1">Region</label>
                  <.input
                    field={@form[:region]}
                    type="select"
                    options={@regions}
                    class="w-full bg-gray-700 border-gray-600 text-white rounded px-3 py-2"
                  />
                </div>
              </div>
              <div class="grid grid-cols-2 gap-4">
                <div>
                  <label class="block text-sm font-medium text-gray-300 mb-1">Seed (1-16)</label>
                  <.input
                    field={@form[:seed]}
                    type="number"
                    min="1"
                    max="16"
                    class="w-full bg-gray-700 border-gray-600 text-white rounded px-3 py-2"
                  />
                </div>
                <div>
                  <label class="block text-sm font-medium text-gray-300 mb-1">Image URL (optional)</label>
                  <.input
                    field={@form[:image_url]}
                    type="text"
                    placeholder="https://..."
                    class="w-full bg-gray-700 border-gray-600 text-white rounded px-3 py-2"
                  />
                </div>
              </div>
              <div class="flex space-x-2">
                <button type="submit" class="bg-purple-600 hover:bg-purple-700 text-white px-4 py-2 rounded text-sm">
                  <%= if @editing, do: "Update", else: "Add" %>
                </button>
                <button type="button" phx-click="cancel_form" class="bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded text-sm">
                  Cancel
                </button>
              </div>
            </.form>
          </div>
        <% end %>

        <!-- Bulk Import -->
        <%= if @show_bulk do %>
          <div class="mb-6 bg-gray-800 rounded-lg p-6 border border-gray-700">
            <h3 class="text-lg font-semibold text-white mb-2">Bulk Import - <%= @bulk_region %> Region</h3>
            <p class="text-gray-400 text-sm mb-4">
              Paste 16 names (one per line). They will be assigned seeds 1-16 in order.
            </p>

            <div class="flex space-x-2 mb-4">
              <%= for region <- @regions do %>
                <button
                  phx-click="set_bulk_region"
                  phx-value-region={region}
                  class={"px-3 py-1 rounded text-sm #{if @bulk_region == region, do: "bg-purple-600 text-white", else: "bg-gray-700 text-gray-300 hover:bg-gray-600"}"}
                >
                  <%= region %> (<%= length(Map.get(@by_region, region, [])) %>/16)
                </button>
              <% end %>
            </div>

            <form phx-submit="bulk_import">
              <textarea
                name="names"
                rows="16"
                placeholder="Spider-Man&#10;Iron Man&#10;Thor&#10;..."
                class="w-full bg-gray-700 border-gray-600 text-white rounded px-3 py-2 font-mono text-sm"
              ><%= @bulk_text %></textarea>

              <div class="flex space-x-2 mt-4">
                <button type="submit" class="bg-purple-600 hover:bg-purple-700 text-white px-4 py-2 rounded text-sm">
                  Import 16 to <%= @bulk_region %>
                </button>
                <button type="button" phx-click="cancel_bulk" class="bg-gray-700 hover:bg-gray-600 text-white px-4 py-2 rounded text-sm">
                  Cancel
                </button>
              </div>
            </form>
          </div>
        <% end %>

        <!-- Contestants by Region -->
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
          <%= for region <- @regions do %>
            <div class="bg-gray-800 rounded-lg border border-gray-700 overflow-hidden">
              <div class="bg-gray-750 px-4 py-3 border-b border-gray-700">
                <div class="flex justify-between items-center">
                  <h3 class="font-semibold text-white"><%= region %></h3>
                  <span class="text-gray-400 text-sm">
                    <%= length(Map.get(@by_region, region, [])) %>/16
                  </span>
                </div>
              </div>
              <div class="p-2">
                <%= if region_contestants = Map.get(@by_region, region, []) do %>
                  <%= for contestant <- Enum.sort_by(region_contestants, & &1.seed) do %>
                    <div class="flex items-center justify-between p-2 hover:bg-gray-700 rounded">
                      <div class="flex items-center space-x-2">
                        <span class="text-gray-500 text-sm w-6"><%= contestant.seed %>.</span>
                        <span class="text-white text-sm"><%= contestant.name %></span>
                      </div>
                      <%= if @tournament.status == "draft" do %>
                        <div class="flex space-x-1">
                          <button
                            phx-click="edit"
                            phx-value-id={contestant.id}
                            class="text-gray-400 hover:text-white text-xs"
                          >
                            Edit
                          </button>
                          <button
                            phx-click="delete"
                            phx-value-id={contestant.id}
                            class="text-red-400 hover:text-red-300 text-xs"
                          >
                            X
                          </button>
                        </div>
                      <% end %>
                    </div>
                  <% end %>

                  <%= for seed <- 1..16, not Enum.any?(region_contestants, & &1.seed == seed) do %>
                    <div class="flex items-center p-2 text-gray-600">
                      <span class="text-sm w-6"><%= seed %>.</span>
                      <span class="text-sm italic">Empty</span>
                    </div>
                  <% end %>
                <% end %>
              </div>
            </div>
          <% end %>
        </div>
      </main>
    </div>
    """
  end

  @impl true
  def handle_event("show_form", _, socket) do
    changeset = Contestant.changeset(%Contestant{}, %{region: "East", seed: next_available_seed(socket.assigns.by_region, "East")})
    {:noreply, assign(socket, show_form: true, show_bulk: false, form: to_form(changeset), editing: nil)}
  end

  def handle_event("cancel_form", _, socket) do
    {:noreply, assign(socket, show_form: false, form: nil, editing: nil)}
  end

  def handle_event("show_bulk", _, socket) do
    {:noreply, assign(socket, show_bulk: true, show_form: false)}
  end

  def handle_event("cancel_bulk", _, socket) do
    {:noreply, assign(socket, show_bulk: false, bulk_text: "")}
  end

  def handle_event("set_bulk_region", %{"region" => region}, socket) do
    {:noreply, assign(socket, bulk_region: region)}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    contestant = Tournaments.get_contestant!(id)
    changeset = Contestant.changeset(contestant, %{})
    {:noreply, assign(socket, show_form: true, show_bulk: false, form: to_form(changeset), editing: contestant)}
  end

  def handle_event("save_contestant", %{"contestant" => params}, socket) do
    if socket.assigns.editing do
      case Tournaments.update_contestant(socket.assigns.editing, params) do
        {:ok, _} ->
          {:noreply, refresh_contestants(socket) |> assign(show_form: false, editing: nil)}

        {:error, changeset} ->
          {:noreply, assign(socket, form: to_form(changeset))}
      end
    else
      case Tournaments.add_contestant(socket.assigns.tournament, params) do
        {:ok, _} ->
          {:noreply, refresh_contestants(socket) |> put_flash(:info, "Contestant added")}

        {:error, changeset} ->
          {:noreply, assign(socket, form: to_form(changeset))}
      end
    end
  end

  def handle_event("bulk_import", %{"names" => names_text}, socket) do
    region = socket.assigns.bulk_region
    tournament = socket.assigns.tournament

    names =
      names_text
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&(&1 != ""))
      |> Enum.take(16)

    if length(names) != 16 do
      {:noreply, put_flash(socket, :error, "Please provide exactly 16 names (got #{length(names)})")}
    else
      # Check if region already has contestants
      existing = Map.get(socket.assigns.by_region, region, [])

      if length(existing) > 0 do
        {:noreply, put_flash(socket, :error, "#{region} region already has contestants. Delete them first.")}
      else
        # Import all 16
        results =
          names
          |> Enum.with_index(1)
          |> Enum.map(fn {name, seed} ->
            Tournaments.add_contestant(tournament, %{name: name, seed: seed, region: region})
          end)

        errors = Enum.filter(results, &match?({:error, _}, &1))

        if length(errors) > 0 do
          {:noreply,
           socket
           |> refresh_contestants()
           |> put_flash(:error, "#{length(errors)} contestants failed to import")}
        else
          {:noreply,
           socket
           |> refresh_contestants()
           |> assign(show_bulk: false, bulk_text: "")
           |> put_flash(:info, "Imported 16 contestants to #{region}")}
        end
      end
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    contestant = Tournaments.get_contestant!(id)

    case Tournaments.delete_contestant(contestant) do
      {:ok, _} ->
        {:noreply, refresh_contestants(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete")}
    end
  end

  defp refresh_contestants(socket) do
    contestants = Tournaments.list_contestants(socket.assigns.tournament.id)
    by_region = Enum.group_by(contestants, & &1.region)
    assign(socket, contestants: contestants, by_region: by_region)
  end

  defp next_available_seed(by_region, region) do
    existing = Map.get(by_region, region, []) |> Enum.map(& &1.seed)
    Enum.find(1..16, fn s -> s not in existing end) || 1
  end

  defp status_color("draft"), do: "bg-gray-600 text-gray-200"
  defp status_color("registration"), do: "bg-blue-600 text-blue-100"
  defp status_color("active"), do: "bg-green-600 text-green-100"
  defp status_color("completed"), do: "bg-purple-600 text-purple-100"
  defp status_color(_), do: "bg-gray-600 text-gray-200"
end
