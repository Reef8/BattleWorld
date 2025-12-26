defmodule BracketBattleWeb.BracketEditorLive do
  use BracketBattleWeb, :live_view

  alias BracketBattle.Accounts
  alias BracketBattle.Tournaments
  alias BracketBattle.Brackets

  # Position mapping for bracket
  # Round 1: positions 1-32 (8 per region: East 1-8, West 9-16, South 17-24, Midwest 25-32)
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

      # Build region data with seed lookups
      regions_data = build_regions_data(by_region)

      {:ok,
       assign(socket,
         page_title: "Fill Bracket - #{tournament.name}",
         current_user: user,
         tournament: tournament,
         bracket: bracket,
         picks: bracket.picks || %{},
         contestants_map: contestants_map,
         regions_data: regions_data,
         is_submitted: not is_nil(bracket.submitted_at),
         picks_count: count_picks(bracket.picks || %{})
       )}
    end
  end

  defp build_regions_data(by_region) do
    seed_pairs = [{1, 16}, {8, 9}, {5, 12}, {4, 13}, {6, 11}, {3, 14}, {7, 10}, {2, 15}]

    %{
      "East" => build_region_data(Map.get(by_region, "East", []), seed_pairs, 0),
      "West" => build_region_data(Map.get(by_region, "West", []), seed_pairs, 8),
      "South" => build_region_data(Map.get(by_region, "South", []), seed_pairs, 16),
      "Midwest" => build_region_data(Map.get(by_region, "Midwest", []), seed_pairs, 24)
    }
  end

  defp build_region_data(contestants, seed_pairs, offset) do
    by_seed = Map.new(contestants, fn c -> {c.seed, c} end)

    matchups = Enum.with_index(seed_pairs)
    |> Enum.map(fn {{seed_a, seed_b}, idx} ->
      %{
        position: offset + idx + 1,
        contestant_a: Map.get(by_seed, seed_a),
        contestant_b: Map.get(by_seed, seed_b)
      }
    end)

    %{matchups: matchups, offset: offset}
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
                ← Home
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

      <main class="px-4 py-6">
        <!-- Instructions -->
        <div class="mb-4 text-center">
          <h2 class="text-2xl font-bold text-white mb-2">Fill Your Bracket</h2>
          <p class="text-gray-400 text-sm">
            Click on a contestant to pick them as the winner. Your picks auto-save as you go.
          </p>
        </div>

        <!-- ESPN-Style Bracket Layout -->
        <div class="overflow-x-auto pb-4">
          <div class="min-w-[1400px]">
            <!-- Top Half: East (left) and West (right) -->
            <div class="flex">
              <!-- EAST REGION - flows left to right -->
              <div class="flex-1">
                <div class="text-center mb-3">
                  <span class="text-purple-400 font-bold text-lg uppercase tracking-wider">East</span>
                </div>
                <.region_bracket_left
                  region_data={@regions_data["East"]}
                  picks={@picks}
                  contestants_map={@contestants_map}
                  is_submitted={@is_submitted}
                  region="East"
                />
              </div>

              <!-- CENTER COLUMN - Final Four Top + Championship -->
              <div class="w-80 flex flex-col items-center justify-end px-4">
                <.final_four_slot
                  position={61}
                  label="Final Four"
                  source_a={57}
                  source_b={58}
                  placeholder_a="East Winner"
                  placeholder_b="West Winner"
                  picks={@picks}
                  contestants_map={@contestants_map}
                  is_submitted={@is_submitted}
                />
              </div>

              <!-- WEST REGION - flows right to left -->
              <div class="flex-1">
                <div class="text-center mb-3">
                  <span class="text-purple-400 font-bold text-lg uppercase tracking-wider">West</span>
                </div>
                <.region_bracket_right
                  region_data={@regions_data["West"]}
                  picks={@picks}
                  contestants_map={@contestants_map}
                  is_submitted={@is_submitted}
                  region="West"
                />
              </div>
            </div>

            <!-- Championship in Center -->
            <div class="flex justify-center my-6">
              <.championship_slot
                picks={@picks}
                contestants_map={@contestants_map}
                is_submitted={@is_submitted}
              />
            </div>

            <!-- Bottom Half: South (left) and Midwest (right) -->
            <div class="flex">
              <!-- SOUTH REGION - flows left to right -->
              <div class="flex-1">
                <div class="text-center mb-3">
                  <span class="text-purple-400 font-bold text-lg uppercase tracking-wider">South</span>
                </div>
                <.region_bracket_left
                  region_data={@regions_data["South"]}
                  picks={@picks}
                  contestants_map={@contestants_map}
                  is_submitted={@is_submitted}
                  region="South"
                />
              </div>

              <!-- CENTER COLUMN - Final Four Bottom -->
              <div class="w-80 flex flex-col items-center justify-start px-4">
                <.final_four_slot
                  position={62}
                  label="Final Four"
                  source_a={59}
                  source_b={60}
                  placeholder_a="South Winner"
                  placeholder_b="Midwest Winner"
                  picks={@picks}
                  contestants_map={@contestants_map}
                  is_submitted={@is_submitted}
                />
              </div>

              <!-- MIDWEST REGION - flows right to left -->
              <div class="flex-1">
                <div class="text-center mb-3">
                  <span class="text-purple-400 font-bold text-lg uppercase tracking-wider">Midwest</span>
                </div>
                <.region_bracket_right
                  region_data={@regions_data["Midwest"]}
                  picks={@picks}
                  contestants_map={@contestants_map}
                  is_submitted={@is_submitted}
                  region="Midwest"
                />
              </div>
            </div>
          </div>
        </div>
      </main>
    </div>
    """
  end

  # Left-side region bracket (East, South) - flows left to right
  defp region_bracket_left(assigns) do
    offset = assigns.region_data.offset

    # Calculate positions for later rounds
    r2_base = 32 + div(offset, 2)
    r3_base = 48 + div(offset, 4)
    r4_pos = 56 + div(offset, 8) + 1

    assigns = assigns
      |> assign(:r2_base, r2_base)
      |> assign(:r3_base, r3_base)
      |> assign(:r4_pos, r4_pos)
      |> assign(:offset, offset)

    ~H"""
    <div class="flex items-center">
      <!-- Round 1 (8 matchups) -->
      <div class="flex flex-col justify-around" style="min-height: 640px;">
        <%= for matchup <- @region_data.matchups do %>
          <div class="relative">
            <.pick_matchup_box
              position={matchup.position}
              contestant_a={matchup.contestant_a}
              contestant_b={matchup.contestant_b}
              picks={@picks}
              is_submitted={@is_submitted}
              size="small"
            />
            <div class="absolute right-0 top-1/2 w-3 h-px bg-gray-600 translate-x-full"></div>
          </div>
        <% end %>
      </div>

      <!-- Round 2 (4 matchups) -->
      <div class="flex flex-col justify-around ml-3" style="min-height: 640px;">
        <%= for idx <- 0..3 do %>
          <% position = @r2_base + idx + 1 %>
          <% source_a = @offset + idx * 2 + 1 %>
          <% source_b = @offset + idx * 2 + 2 %>
          <div class="relative">
            <div class="absolute left-0 top-1/2 w-3 h-px bg-gray-600 -translate-x-full"></div>
            <.pick_matchup_box_from_picks
              position={position}
              source_a={source_a}
              source_b={source_b}
              picks={@picks}
              contestants_map={@contestants_map}
              is_submitted={@is_submitted}
              size="small"
            />
            <div class="absolute right-0 top-1/2 w-3 h-px bg-gray-600 translate-x-full"></div>
          </div>
        <% end %>
      </div>

      <!-- Sweet 16 (2 matchups) -->
      <div class="flex flex-col justify-around ml-3" style="min-height: 640px;">
        <%= for idx <- 0..1 do %>
          <% position = @r3_base + idx + 1 %>
          <% source_a = @r2_base + idx * 2 + 1 %>
          <% source_b = @r2_base + idx * 2 + 2 %>
          <div class="relative">
            <div class="absolute left-0 top-1/2 w-3 h-px bg-gray-600 -translate-x-full"></div>
            <.pick_matchup_box_from_picks
              position={position}
              source_a={source_a}
              source_b={source_b}
              picks={@picks}
              contestants_map={@contestants_map}
              is_submitted={@is_submitted}
            />
            <div class="absolute right-0 top-1/2 w-3 h-px bg-gray-600 translate-x-full"></div>
          </div>
        <% end %>
      </div>

      <!-- Elite 8 (1 matchup) -->
      <div class="flex flex-col justify-center ml-3" style="min-height: 640px;">
        <div class="relative">
          <div class="absolute left-0 top-1/2 w-3 h-px bg-gray-600 -translate-x-full"></div>
          <.pick_matchup_box_from_picks
            position={@r4_pos}
            source_a={@r3_base + 1}
            source_b={@r3_base + 2}
            picks={@picks}
            contestants_map={@contestants_map}
            is_submitted={@is_submitted}
          />
          <div class="absolute right-0 top-1/2 w-3 h-px bg-gray-600 translate-x-full"></div>
        </div>
      </div>
    </div>
    """
  end

  # Right-side region bracket (West, Midwest) - flows right to left
  defp region_bracket_right(assigns) do
    offset = assigns.region_data.offset

    # Calculate positions for later rounds
    r2_base = 32 + div(offset, 2)
    r3_base = 48 + div(offset, 4)
    r4_pos = 56 + div(offset, 8) + 1

    assigns = assigns
      |> assign(:r2_base, r2_base)
      |> assign(:r3_base, r3_base)
      |> assign(:r4_pos, r4_pos)
      |> assign(:offset, offset)

    ~H"""
    <div class="flex items-center justify-end">
      <!-- Elite 8 (1 matchup) -->
      <div class="flex flex-col justify-center mr-3" style="min-height: 640px;">
        <div class="relative">
          <div class="absolute left-0 top-1/2 w-3 h-px bg-gray-600 -translate-x-full"></div>
          <.pick_matchup_box_from_picks
            position={@r4_pos}
            source_a={@r3_base + 1}
            source_b={@r3_base + 2}
            picks={@picks}
            contestants_map={@contestants_map}
            is_submitted={@is_submitted}
          />
          <div class="absolute right-0 top-1/2 w-3 h-px bg-gray-600 translate-x-full"></div>
        </div>
      </div>

      <!-- Sweet 16 (2 matchups) -->
      <div class="flex flex-col justify-around mr-3" style="min-height: 640px;">
        <%= for idx <- 0..1 do %>
          <% position = @r3_base + idx + 1 %>
          <% source_a = @r2_base + idx * 2 + 1 %>
          <% source_b = @r2_base + idx * 2 + 2 %>
          <div class="relative">
            <div class="absolute left-0 top-1/2 w-3 h-px bg-gray-600 -translate-x-full"></div>
            <.pick_matchup_box_from_picks
              position={position}
              source_a={source_a}
              source_b={source_b}
              picks={@picks}
              contestants_map={@contestants_map}
              is_submitted={@is_submitted}
            />
            <div class="absolute right-0 top-1/2 w-3 h-px bg-gray-600 translate-x-full"></div>
          </div>
        <% end %>
      </div>

      <!-- Round 2 (4 matchups) -->
      <div class="flex flex-col justify-around mr-3" style="min-height: 640px;">
        <%= for idx <- 0..3 do %>
          <% position = @r2_base + idx + 1 %>
          <% source_a = @offset + idx * 2 + 1 %>
          <% source_b = @offset + idx * 2 + 2 %>
          <div class="relative">
            <div class="absolute left-0 top-1/2 w-3 h-px bg-gray-600 -translate-x-full"></div>
            <.pick_matchup_box_from_picks
              position={position}
              source_a={source_a}
              source_b={source_b}
              picks={@picks}
              contestants_map={@contestants_map}
              is_submitted={@is_submitted}
              size="small"
            />
            <div class="absolute right-0 top-1/2 w-3 h-px bg-gray-600 translate-x-full"></div>
          </div>
        <% end %>
      </div>

      <!-- Round 1 (8 matchups) -->
      <div class="flex flex-col justify-around" style="min-height: 640px;">
        <%= for matchup <- @region_data.matchups do %>
          <div class="relative">
            <div class="absolute left-0 top-1/2 w-3 h-px bg-gray-600 -translate-x-full"></div>
            <.pick_matchup_box
              position={matchup.position}
              contestant_a={matchup.contestant_a}
              contestant_b={matchup.contestant_b}
              picks={@picks}
              is_submitted={@is_submitted}
              size="small"
            />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Matchup box for Round 1 where contestants are known
  defp pick_matchup_box(assigns) do
    assigns = Map.put_new(assigns, :size, "normal")
    current_pick = Map.get(assigns.picks, to_string(assigns.position))

    assigns = assign(assigns, :current_pick, current_pick)

    ~H"""
    <div class={[
      "bg-gray-800 border rounded overflow-hidden",
      @size == "small" && "w-36",
      @size == "normal" && "w-44",
      @current_pick && "border-purple-500",
      !@current_pick && "border-gray-700"
    ]}>
      <.pick_contestant_row
        contestant={@contestant_a}
        position={@position}
        is_picked={@current_pick == (@contestant_a && @contestant_a.id)}
        is_submitted={@is_submitted}
        has_border={true}
      />
      <.pick_contestant_row
        contestant={@contestant_b}
        position={@position}
        is_picked={@current_pick == (@contestant_b && @contestant_b.id)}
        is_submitted={@is_submitted}
        has_border={false}
      />
    </div>
    """
  end

  # Matchup box for later rounds where contestants come from picks
  defp pick_matchup_box_from_picks(assigns) do
    assigns = Map.put_new(assigns, :size, "normal")

    # Get contestants from previous picks
    pick_a = Map.get(assigns.picks, to_string(assigns.source_a))
    pick_b = Map.get(assigns.picks, to_string(assigns.source_b))

    contestant_a = if pick_a, do: Map.get(assigns.contestants_map, pick_a)
    contestant_b = if pick_b, do: Map.get(assigns.contestants_map, pick_b)

    current_pick = Map.get(assigns.picks, to_string(assigns.position))

    assigns = assigns
      |> assign(:contestant_a, contestant_a)
      |> assign(:contestant_b, contestant_b)
      |> assign(:current_pick, current_pick)

    ~H"""
    <div class={[
      "bg-gray-800 border rounded overflow-hidden",
      @size == "small" && "w-36",
      @size == "normal" && "w-44",
      @current_pick && "border-purple-500",
      !@current_pick && "border-gray-700"
    ]}>
      <.pick_contestant_row
        contestant={@contestant_a}
        position={@position}
        is_picked={@current_pick == (@contestant_a && @contestant_a.id)}
        is_submitted={@is_submitted}
        has_border={true}
      />
      <.pick_contestant_row
        contestant={@contestant_b}
        position={@position}
        is_picked={@current_pick == (@contestant_b && @contestant_b.id)}
        is_submitted={@is_submitted}
        has_border={false}
      />
    </div>
    """
  end

  # Individual contestant row (clickable)
  defp pick_contestant_row(assigns) do
    ~H"""
    <%= if @contestant do %>
      <button
        phx-click="pick"
        phx-value-position={@position}
        phx-value-contestant={@contestant.id}
        disabled={@is_submitted}
        class={[
          "w-full flex items-center px-2 py-1 transition-colors text-left",
          @has_border && "border-b border-gray-700",
          @is_picked && "bg-purple-600/40",
          !@is_picked && !@is_submitted && "hover:bg-gray-700",
          @is_submitted && "cursor-default"
        ]}
      >
        <span class={[
          "text-xs font-mono w-5",
          @is_picked && "text-purple-300",
          !@is_picked && "text-gray-500"
        ]}>
          <%= @contestant.seed %>
        </span>
        <span class={[
          "text-xs truncate flex-1",
          @is_picked && "text-white font-semibold",
          !@is_picked && "text-gray-300"
        ]}>
          <%= @contestant.name %>
        </span>
        <%= if @is_picked do %>
          <span class="text-purple-300 text-xs">✓</span>
        <% end %>
      </button>
    <% else %>
      <div class={[
        "flex items-center px-2 py-1",
        @has_border && "border-b border-gray-700"
      ]}>
        <span class="text-xs text-gray-600 italic">TBD</span>
      </div>
    <% end %>
    """
  end

  # Final Four slot
  defp final_four_slot(assigns) do
    pick_a = Map.get(assigns.picks, to_string(assigns.source_a))
    pick_b = Map.get(assigns.picks, to_string(assigns.source_b))

    contestant_a = if pick_a, do: Map.get(assigns.contestants_map, pick_a)
    contestant_b = if pick_b, do: Map.get(assigns.contestants_map, pick_b)

    current_pick = Map.get(assigns.picks, to_string(assigns.position))

    assigns = assigns
      |> assign(:contestant_a, contestant_a)
      |> assign(:contestant_b, contestant_b)
      |> assign(:current_pick, current_pick)

    ~H"""
    <div class="text-center">
      <div class="text-xs text-gray-500 mb-1"><%= @label %></div>
      <div class={[
        "bg-gray-800 border rounded overflow-hidden w-44",
        @current_pick && "border-purple-500",
        !@current_pick && "border-gray-700"
      ]}>
        <%= if @contestant_a do %>
          <button
            phx-click="pick"
            phx-value-position={@position}
            phx-value-contestant={@contestant_a.id}
            disabled={@is_submitted}
            class={[
              "w-full flex items-center px-2 py-1 transition-colors text-left border-b border-gray-700",
              @current_pick == @contestant_a.id && "bg-purple-600/40",
              @current_pick != @contestant_a.id && !@is_submitted && "hover:bg-gray-700"
            ]}
          >
            <span class="text-xs font-mono w-5 text-gray-500"><%= @contestant_a.seed %></span>
            <span class={["text-xs truncate flex-1", @current_pick == @contestant_a.id && "text-white font-semibold", @current_pick != @contestant_a.id && "text-gray-300"]}>
              <%= @contestant_a.name %>
            </span>
            <%= if @current_pick == @contestant_a.id do %><span class="text-purple-300 text-xs">✓</span><% end %>
          </button>
        <% else %>
          <div class="flex items-center px-2 py-1 border-b border-gray-700">
            <span class="text-xs text-gray-600 italic"><%= @placeholder_a %></span>
          </div>
        <% end %>

        <%= if @contestant_b do %>
          <button
            phx-click="pick"
            phx-value-position={@position}
            phx-value-contestant={@contestant_b.id}
            disabled={@is_submitted}
            class={[
              "w-full flex items-center px-2 py-1 transition-colors text-left",
              @current_pick == @contestant_b.id && "bg-purple-600/40",
              @current_pick != @contestant_b.id && !@is_submitted && "hover:bg-gray-700"
            ]}
          >
            <span class="text-xs font-mono w-5 text-gray-500"><%= @contestant_b.seed %></span>
            <span class={["text-xs truncate flex-1", @current_pick == @contestant_b.id && "text-white font-semibold", @current_pick != @contestant_b.id && "text-gray-300"]}>
              <%= @contestant_b.name %>
            </span>
            <%= if @current_pick == @contestant_b.id do %><span class="text-purple-300 text-xs">✓</span><% end %>
          </button>
        <% else %>
          <div class="flex items-center px-2 py-1">
            <span class="text-xs text-gray-600 italic"><%= @placeholder_b %></span>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Championship slot
  defp championship_slot(assigns) do
    # Championship contestants come from Final Four picks
    pick_a = Map.get(assigns.picks, "61")
    pick_b = Map.get(assigns.picks, "62")

    contestant_a = if pick_a, do: Map.get(assigns.contestants_map, pick_a)
    contestant_b = if pick_b, do: Map.get(assigns.contestants_map, pick_b)

    current_pick = Map.get(assigns.picks, "63")
    champion = if current_pick, do: Map.get(assigns.contestants_map, current_pick)

    assigns = assigns
      |> assign(:contestant_a, contestant_a)
      |> assign(:contestant_b, contestant_b)
      |> assign(:current_pick, current_pick)
      |> assign(:champion, champion)

    ~H"""
    <div class="text-center">
      <div class="text-xs text-yellow-500 font-bold mb-1 uppercase">Championship</div>
      <div class={[
        "bg-gray-800 border rounded overflow-hidden w-48",
        @current_pick && "border-yellow-500 ring-1 ring-yellow-500/50",
        !@current_pick && "border-gray-700"
      ]}>
        <%= if @contestant_a do %>
          <button
            phx-click="pick"
            phx-value-position={63}
            phx-value-contestant={@contestant_a.id}
            disabled={@is_submitted}
            class={[
              "w-full flex items-center px-2 py-1.5 transition-colors text-left border-b border-gray-700",
              @current_pick == @contestant_a.id && "bg-yellow-600/30",
              @current_pick != @contestant_a.id && !@is_submitted && "hover:bg-gray-700"
            ]}
          >
            <span class="text-xs font-mono w-5 text-gray-500"><%= @contestant_a.seed %></span>
            <span class={["text-sm truncate flex-1", @current_pick == @contestant_a.id && "text-yellow-400 font-bold", @current_pick != @contestant_a.id && "text-gray-300"]}>
              <%= @contestant_a.name %>
            </span>
            <%= if @current_pick == @contestant_a.id do %><span class="text-yellow-400 text-xs">👑</span><% end %>
          </button>
        <% else %>
          <div class="flex items-center px-2 py-1.5 border-b border-gray-700">
            <span class="text-xs text-gray-600 italic">Final Four Winner 1</span>
          </div>
        <% end %>

        <%= if @contestant_b do %>
          <button
            phx-click="pick"
            phx-value-position={63}
            phx-value-contestant={@contestant_b.id}
            disabled={@is_submitted}
            class={[
              "w-full flex items-center px-2 py-1.5 transition-colors text-left",
              @current_pick == @contestant_b.id && "bg-yellow-600/30",
              @current_pick != @contestant_b.id && !@is_submitted && "hover:bg-gray-700"
            ]}
          >
            <span class="text-xs font-mono w-5 text-gray-500"><%= @contestant_b.seed %></span>
            <span class={["text-sm truncate flex-1", @current_pick == @contestant_b.id && "text-yellow-400 font-bold", @current_pick != @contestant_b.id && "text-gray-300"]}>
              <%= @contestant_b.name %>
            </span>
            <%= if @current_pick == @contestant_b.id do %><span class="text-yellow-400 text-xs">👑</span><% end %>
          </button>
        <% else %>
          <div class="flex items-center px-2 py-1.5">
            <span class="text-xs text-gray-600 italic">Final Four Winner 2</span>
          </div>
        <% end %>
      </div>

      <!-- Champion display -->
      <%= if @champion do %>
        <div class="mt-3 bg-yellow-900/40 border border-yellow-600 rounded p-3">
          <div class="text-xs text-yellow-500 mb-1">Your Champion</div>
          <div class="text-yellow-400 font-bold text-lg">🏆 <%= @champion.name %></div>
        </div>
      <% end %>
    </div>
    """
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
