defmodule BracketBattleWeb.BracketEditorLive do
  use BracketBattleWeb, :live_view

  alias BracketBattle.Accounts
  alias BracketBattle.Tournaments
  alias BracketBattle.Brackets

  @regions ["East", "West", "South", "Midwest"]

  # Matchup position mapping
  # Round 1: positions 1-32 (8 per region)
  # Round 2: positions 33-48 (4 per region)
  # Sweet 16: positions 49-56 (2 per region)
  # Elite 8: positions 57-60 (1 per region)
  # Final Four: positions 61-62
  # Championship: position 63

  @impl true
  def mount(%{"id" => tournament_id}, session, socket) do
    user = if user_id = session["user_id"] do
      Accounts.get_user(user_id)
    end

    if is_nil(user) do
      {:ok, push_navigate(socket, to: "/auth/signin")}
    else
      tournament = Tournaments.get_tournament!(tournament_id)
      contestants = Tournaments.list_contestants(tournament_id)

      # Get or create user's bracket
      {:ok, bracket} = Brackets.get_or_create_bracket(tournament_id, user.id)

      # Build contestant lookup map
      contestants_map = Map.new(contestants, fn c -> {c.id, c} end)

      # Group contestants by region for Round 1
      by_region = Enum.group_by(contestants, & &1.region)

      {:ok,
       assign(socket,
         page_title: "Fill Bracket - #{tournament.name}",
         current_user: user,
         tournament: tournament,
         bracket: bracket,
         picks: bracket.picks || %{},
         contestants_map: contestants_map,
         by_region: by_region,
         regions: @regions,
         is_submitted: not is_nil(bracket.submitted_at),
         picks_count: count_picks(bracket.picks || %{})
       )}
    end
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
              <a href="/" class="text-gray-400 hover:text-white text-sm">
                &larr; Home
              </a>
              <h1 class="text-xl font-bold text-white"><%= @tournament.name %></h1>
            </div>
            <div class="flex items-center space-x-4">
              <div class="text-gray-400 text-sm">
                <span class="text-white font-medium"><%= @picks_count %></span>/63 picks
              </div>
              <%= if @is_submitted do %>
                <span class="bg-green-600 text-white px-3 py-1 rounded text-sm">
                  Submitted
                </span>
              <% else %>
                <button
                  phx-click="submit_bracket"
                  disabled={@picks_count != 63}
                  class={"px-4 py-2 rounded text-sm font-medium transition-colors #{if @picks_count == 63, do: "bg-green-600 hover:bg-green-700 text-white", else: "bg-gray-700 text-gray-500 cursor-not-allowed"}"}
                >
                  Submit Bracket
                </button>
              <% end %>
            </div>
          </div>
        </div>
      </header>

      <%= if @is_submitted do %>
        <div class="bg-green-900/20 border-b border-green-700 px-4 py-3">
          <div class="max-w-7xl mx-auto text-center text-green-400 text-sm">
            Your bracket has been submitted! You can view it below but cannot make changes.
          </div>
        </div>
      <% end %>

      <%= if @tournament.status != "registration" do %>
        <div class="bg-yellow-900/20 border-b border-yellow-700 px-4 py-3">
          <div class="max-w-7xl mx-auto text-center text-yellow-400 text-sm">
            Registration is closed. Brackets can no longer be submitted.
          </div>
        </div>
      <% end %>

      <main class="max-w-7xl mx-auto px-4 py-6">
        <!-- Instructions -->
        <div class="mb-6 text-center">
          <p class="text-gray-400 text-sm">
            Click on a contestant to pick them as the winner. Your picks auto-save as you go.
          </p>
        </div>

        <!-- Bracket Grid -->
        <div class="overflow-x-auto">
          <div class="min-w-[1200px]">
            <!-- Regional brackets (2x2 grid) -->
            <div class="grid grid-cols-2 gap-8 mb-8">
              <!-- Left side: East and South -->
              <div class="space-y-8">
                <.region_bracket
                  region="East"
                  contestants={Map.get(@by_region, "East", [])}
                  picks={@picks}
                  contestants_map={@contestants_map}
                  is_submitted={@is_submitted}
                  region_offset={0}
                />
                <.region_bracket
                  region="South"
                  contestants={Map.get(@by_region, "South", [])}
                  picks={@picks}
                  contestants_map={@contestants_map}
                  is_submitted={@is_submitted}
                  region_offset={16}
                />
              </div>

              <!-- Right side: West and Midwest -->
              <div class="space-y-8">
                <.region_bracket
                  region="West"
                  contestants={Map.get(@by_region, "West", [])}
                  picks={@picks}
                  contestants_map={@contestants_map}
                  is_submitted={@is_submitted}
                  region_offset={8}
                />
                <.region_bracket
                  region="Midwest"
                  contestants={Map.get(@by_region, "Midwest", [])}
                  picks={@picks}
                  contestants_map={@contestants_map}
                  is_submitted={@is_submitted}
                  region_offset={24}
                />
              </div>
            </div>

            <!-- Final Four and Championship -->
            <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
              <h3 class="text-lg font-bold text-white text-center mb-6">Final Four & Championship</h3>
              <.final_four
                picks={@picks}
                contestants_map={@contestants_map}
                is_submitted={@is_submitted}
              />
            </div>
          </div>
        </div>
      </main>
    </div>
    """
  end

  # Regional bracket component
  defp region_bracket(assigns) do
    # Get seed pairs for Round 1 (NCAA style)
    seed_pairs = [{1, 16}, {8, 9}, {5, 12}, {4, 13}, {6, 11}, {3, 14}, {7, 10}, {2, 15}]

    contestants_by_seed = Map.new(assigns.contestants, fn c -> {c.seed, c} end)

    assigns =
      assigns
      |> assign(:seed_pairs, seed_pairs)
      |> assign(:contestants_by_seed, contestants_by_seed)

    ~H"""
    <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
      <h3 class="text-lg font-bold text-white mb-4"><%= @region %> Region</h3>

      <div class="flex gap-4">
        <!-- Round 1 -->
        <div class="space-y-2">
          <div class="text-xs text-gray-500 text-center mb-2">Round 1</div>
          <%= for {{seed_a, seed_b}, idx} <- Enum.with_index(@seed_pairs) do %>
            <% position = @region_offset + idx + 1 %>
            <.matchup_slot
              position={position}
              contestant_a={Map.get(@contestants_by_seed, seed_a)}
              contestant_b={Map.get(@contestants_by_seed, seed_b)}
              picks={@picks}
              contestants_map={@contestants_map}
              is_submitted={@is_submitted}
            />
          <% end %>
        </div>

        <!-- Round 2 -->
        <div class="space-y-2 pt-6">
          <div class="text-xs text-gray-500 text-center mb-2">Round 2</div>
          <%= for idx <- 0..3 do %>
            <% position = 32 + div(@region_offset, 2) + idx + 1 %>
            <.pick_slot
              position={position}
              picks={@picks}
              contestants_map={@contestants_map}
              is_submitted={@is_submitted}
              source_positions={[@region_offset + idx * 2 + 1, @region_offset + idx * 2 + 2]}
            />
          <% end %>
        </div>

        <!-- Sweet 16 -->
        <div class="space-y-2 pt-12">
          <div class="text-xs text-gray-500 text-center mb-2">Sweet 16</div>
          <%= for idx <- 0..1 do %>
            <% position = 48 + div(@region_offset, 4) + idx + 1 %>
            <.pick_slot
              position={position}
              picks={@picks}
              contestants_map={@contestants_map}
              is_submitted={@is_submitted}
              source_positions={[32 + div(@region_offset, 2) + idx * 2 + 1, 32 + div(@region_offset, 2) + idx * 2 + 2]}
            />
          <% end %>
        </div>

        <!-- Elite 8 -->
        <div class="space-y-2 pt-20">
          <div class="text-xs text-gray-500 text-center mb-2">Elite 8</div>
          <% position = 56 + div(@region_offset, 8) + 1 %>
          <.pick_slot
            position={position}
            picks={@picks}
            contestants_map={@contestants_map}
            is_submitted={@is_submitted}
            source_positions={[48 + div(@region_offset, 4) + 1, 48 + div(@region_offset, 4) + 2]}
          />
        </div>
      </div>
    </div>
    """
  end

  # Round 1 matchup slot with two known contestants
  defp matchup_slot(assigns) do
    ~H"""
    <div class="bg-gray-700/50 rounded p-1 space-y-1">
      <%= if @contestant_a do %>
        <.contestant_button
          contestant={@contestant_a}
          position={@position}
          picks={@picks}
          is_submitted={@is_submitted}
        />
      <% else %>
        <div class="h-6 px-2 py-1 text-xs text-red-500">Missing contestant</div>
      <% end %>
      <%= if @contestant_b do %>
        <.contestant_button
          contestant={@contestant_b}
          position={@position}
          picks={@picks}
          is_submitted={@is_submitted}
        />
      <% else %>
        <div class="h-6 px-2 py-1 text-xs text-red-500">Missing contestant</div>
      <% end %>
    </div>
    """
  end

  # Pick slot for rounds 2+ where contestants come from previous picks
  defp pick_slot(assigns) do
    # Get the two possible contestants from source positions
    source_a = Map.get(assigns.picks, to_string(Enum.at(assigns.source_positions, 0)))
    source_b = Map.get(assigns.picks, to_string(Enum.at(assigns.source_positions, 1)))

    contestant_a = if source_a, do: Map.get(assigns.contestants_map, source_a)
    contestant_b = if source_b, do: Map.get(assigns.contestants_map, source_b)

    assigns =
      assigns
      |> assign(:contestant_a, contestant_a)
      |> assign(:contestant_b, contestant_b)

    ~H"""
    <div class="bg-gray-700/50 rounded p-1 space-y-1 min-h-[60px]">
      <%= if @contestant_a do %>
        <.contestant_button
          contestant={@contestant_a}
          position={@position}
          picks={@picks}
          is_submitted={@is_submitted}
        />
      <% else %>
        <div class="h-6 px-2 py-1 text-xs text-gray-600 italic">TBD</div>
      <% end %>
      <%= if @contestant_b do %>
        <.contestant_button
          contestant={@contestant_b}
          position={@position}
          picks={@picks}
          is_submitted={@is_submitted}
        />
      <% else %>
        <div class="h-6 px-2 py-1 text-xs text-gray-600 italic">TBD</div>
      <% end %>
    </div>
    """
  end

  # Individual contestant button
  defp contestant_button(assigns) do
    is_picked = Map.get(assigns.picks, to_string(assigns.position)) == assigns.contestant.id

    assigns = assign(assigns, :is_picked, is_picked)

    ~H"""
    <button
      phx-click="pick"
      phx-value-position={@position}
      phx-value-contestant={@contestant.id}
      disabled={@is_submitted}
      class={"w-full text-left px-2 py-1 rounded text-xs transition-colors #{if @is_picked, do: "bg-purple-600 text-white", else: "bg-gray-600 hover:bg-gray-500 text-gray-200"} #{if @is_submitted, do: "cursor-default"}"}
    >
      <span class="text-gray-400 mr-1"><%= @contestant.seed %>.</span>
      <span class="truncate"><%= @contestant.name %></span>
    </button>
    """
  end

  # Final Four and Championship
  defp final_four(assigns) do
    # Final Four: positions 61-62
    # Championship: position 63

    # Elite 8 winners feed into Final Four
    # Position 61: winners of positions 57 (East) and 58 (West)
    # Position 62: winners of positions 59 (South) and 60 (Midwest)

    ff1_a = get_pick_contestant(assigns.picks, assigns.contestants_map, "57")
    ff1_b = get_pick_contestant(assigns.picks, assigns.contestants_map, "58")
    ff2_a = get_pick_contestant(assigns.picks, assigns.contestants_map, "59")
    ff2_b = get_pick_contestant(assigns.picks, assigns.contestants_map, "60")

    champ_a = get_pick_contestant(assigns.picks, assigns.contestants_map, "61")
    champ_b = get_pick_contestant(assigns.picks, assigns.contestants_map, "62")

    assigns =
      assigns
      |> assign(:ff1_a, ff1_a)
      |> assign(:ff1_b, ff1_b)
      |> assign(:ff2_a, ff2_a)
      |> assign(:ff2_b, ff2_b)
      |> assign(:champ_a, champ_a)
      |> assign(:champ_b, champ_b)

    ~H"""
    <div class="flex justify-center items-center gap-8">
      <!-- Final Four Game 1 (East vs West) -->
      <div class="text-center">
        <div class="text-xs text-gray-500 mb-2">Final Four</div>
        <div class="bg-gray-700/50 rounded p-2 space-y-1 w-40">
          <%= if @ff1_a do %>
            <.contestant_button contestant={@ff1_a} position={61} picks={@picks} is_submitted={@is_submitted} />
          <% else %>
            <div class="h-6 px-2 py-1 text-xs text-gray-600 italic">East Winner</div>
          <% end %>
          <%= if @ff1_b do %>
            <.contestant_button contestant={@ff1_b} position={61} picks={@picks} is_submitted={@is_submitted} />
          <% else %>
            <div class="h-6 px-2 py-1 text-xs text-gray-600 italic">West Winner</div>
          <% end %>
        </div>
      </div>

      <!-- Championship -->
      <div class="text-center">
        <div class="text-xs text-gray-500 mb-2">Championship</div>
        <div class="bg-purple-900/30 border border-purple-700 rounded p-2 space-y-1 w-44">
          <%= if @champ_a do %>
            <.contestant_button contestant={@champ_a} position={63} picks={@picks} is_submitted={@is_submitted} />
          <% else %>
            <div class="h-6 px-2 py-1 text-xs text-gray-600 italic">TBD</div>
          <% end %>
          <%= if @champ_b do %>
            <.contestant_button contestant={@champ_b} position={63} picks={@picks} is_submitted={@is_submitted} />
          <% else %>
            <div class="h-6 px-2 py-1 text-xs text-gray-600 italic">TBD</div>
          <% end %>
        </div>

        <!-- Champion display -->
        <div class="mt-4">
          <div class="text-xs text-gray-500 mb-1">Champion</div>
          <div class="bg-yellow-900/30 border border-yellow-600 rounded p-2 w-44">
            <%= if champion = get_pick_contestant(@picks, @contestants_map, "63") do %>
              <div class="text-yellow-400 font-bold text-sm"><%= champion.name %></div>
            <% else %>
              <div class="text-gray-600 italic text-sm">Pick your champion!</div>
            <% end %>
          </div>
        </div>
      </div>

      <!-- Final Four Game 2 (South vs Midwest) -->
      <div class="text-center">
        <div class="text-xs text-gray-500 mb-2">Final Four</div>
        <div class="bg-gray-700/50 rounded p-2 space-y-1 w-40">
          <%= if @ff2_a do %>
            <.contestant_button contestant={@ff2_a} position={62} picks={@picks} is_submitted={@is_submitted} />
          <% else %>
            <div class="h-6 px-2 py-1 text-xs text-gray-600 italic">South Winner</div>
          <% end %>
          <%= if @ff2_b do %>
            <.contestant_button contestant={@ff2_b} position={62} picks={@picks} is_submitted={@is_submitted} />
          <% else %>
            <div class="h-6 px-2 py-1 text-xs text-gray-600 italic">Midwest Winner</div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp get_pick_contestant(picks, contestants_map, position) do
    case Map.get(picks, position) do
      nil -> nil
      contestant_id -> Map.get(contestants_map, contestant_id)
    end
  end

  @impl true
  def handle_event("pick", %{"position" => position, "contestant" => contestant_id}, socket) do
    if socket.assigns.is_submitted do
      {:noreply, socket}
    else
      position = String.to_integer(position)
      picks = socket.assigns.picks

      # Clear downstream picks when changing an earlier round pick
      picks = clear_downstream_picks(picks, position, contestant_id)

      # Set the new pick
      picks = Map.put(picks, to_string(position), contestant_id)

      # Save to database
      {:ok, bracket} = Brackets.update_picks(socket.assigns.bracket, picks)

      {:noreply,
       assign(socket,
         bracket: bracket,
         picks: picks,
         picks_count: count_picks(picks)
       )}
    end
  end

  def handle_event("submit_bracket", _, socket) do
    if socket.assigns.is_submitted or socket.assigns.picks_count != 63 do
      {:noreply, socket}
    else
      case Brackets.submit_bracket(socket.assigns.bracket) do
        {:ok, bracket} ->
          {:noreply,
           socket
           |> assign(bracket: bracket, is_submitted: true)
           |> put_flash(:info, "Bracket submitted successfully!")}

        {:error, :registration_closed} ->
          {:noreply, put_flash(socket, :error, "Registration has closed")}

        {:error, :incomplete_bracket} ->
          {:noreply, put_flash(socket, :error, "Please complete all 63 picks")}
      end
    end
  end

  # Clear picks that depend on a changed pick
  defp clear_downstream_picks(picks, changed_position, new_contestant_id) do
    old_contestant_id = Map.get(picks, to_string(changed_position))

    # If pick didn't change, no need to clear
    if old_contestant_id == new_contestant_id do
      picks
    else
      # Find all positions that feed from this position and clear them if they had the old contestant
      downstream_positions = get_downstream_positions(changed_position)

      Enum.reduce(downstream_positions, picks, fn pos, acc ->
        if Map.get(acc, to_string(pos)) == old_contestant_id do
          # This downstream pick had the contestant we're removing, clear it
          clear_downstream_picks(Map.delete(acc, to_string(pos)), pos, nil)
        else
          acc
        end
      end)
    end
  end

  # Get positions that are fed by a given position
  defp get_downstream_positions(position) when position >= 1 and position <= 32 do
    # Round 1 feeds Round 2
    r2_pos = 32 + div(position - 1, 2) + 1
    [r2_pos | get_downstream_positions(r2_pos)]
  end

  defp get_downstream_positions(position) when position >= 33 and position <= 48 do
    # Round 2 feeds Sweet 16
    r3_pos = 48 + div(position - 33, 2) + 1
    [r3_pos | get_downstream_positions(r3_pos)]
  end

  defp get_downstream_positions(position) when position >= 49 and position <= 56 do
    # Sweet 16 feeds Elite 8
    r4_pos = 56 + div(position - 49, 2) + 1
    [r4_pos | get_downstream_positions(r4_pos)]
  end

  defp get_downstream_positions(position) when position >= 57 and position <= 60 do
    # Elite 8 feeds Final Four
    # 57 (East) + 58 (West) -> 61
    # 59 (South) + 60 (Midwest) -> 62
    ff_pos = if position <= 58, do: 61, else: 62
    [ff_pos | get_downstream_positions(ff_pos)]
  end

  defp get_downstream_positions(position) when position in [61, 62] do
    # Final Four feeds Championship
    [63]
  end

  defp get_downstream_positions(_), do: []

  defp count_picks(picks) do
    picks
    |> Map.values()
    |> Enum.count(&(&1 != nil))
  end
end
