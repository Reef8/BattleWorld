defmodule BracketBattleWeb.BracketEditorLive do
  use BracketBattleWeb, :live_view

  alias BracketBattle.Accounts
  alias BracketBattle.Tournaments
  alias BracketBattle.Tournaments.Tournament
  alias BracketBattle.Brackets

  # Position mapping for bracket (dynamically calculated based on bracket_size)
  # For 64-contestant bracket with 4 regions:
  # Round 1: positions 1-32 (8 per region)
  # Round 2: positions 33-48 (4 per region)
  # Sweet 16: positions 49-56 (2 per region)
  # Elite 8: positions 57-60 (1 per region)
  # Final Four: positions 61-62
  # Championship: position 63
  #
  # Position bases are calculated dynamically in calculate_round_bases/1

  @impl true
  def mount(%{"id" => tournament_id}, session, socket) do
    user = if user_id = session["user_id"] do
      Accounts.get_user(user_id)
    end

    if is_nil(user) do
      {:ok, push_navigate(socket, to: "/auth/signin")}
    else
      case Tournaments.get_tournament(tournament_id) do
        nil ->
          {:ok,
           socket
           |> put_flash(:error, "Tournament not found")
           |> push_navigate(to: "/")}

        tournament ->
          mount_bracket_editor(socket, tournament, user, tournament_id)
      end
    end
  end

  defp mount_bracket_editor(socket, tournament, user, tournament_id) do
    contestants = Tournaments.list_contestants(tournament_id)

    # Get or create user's bracket
    {:ok, bracket} = Brackets.get_or_create_bracket(tournament_id, user.id)

    # Build contestant lookup map
    contestants_map = Map.new(contestants, fn c -> {c.id, c} end)

    # Group contestants by region for Round 1
    by_region = Enum.group_by(contestants, & &1.region)

    # Build region data with seed lookups using tournament config
    regions_data = build_regions_data(by_region, tournament)

    # Calculate round position bases for dynamic bracket handling
    bracket_config = calculate_round_bases(tournament)

    # Schedule countdown tick if there's a deadline
    if connected?(socket) && tournament.registration_deadline do
      :timer.send_interval(1000, self(), :tick_countdown)
    end

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
       picks_count: count_picks(bracket.picks || %{}),
       bracket_config: bracket_config,
       total_matchups: (tournament.bracket_size || 64) - 1,
       time_remaining: calculate_time_remaining(tournament.registration_deadline)
     )}
  end

  defp build_regions_data(by_region, tournament) do
    # Use tournament's configured regions and seeding
    region_names = tournament.region_names || ["East", "West", "South", "Midwest"]
    contestants_per_region = Tournament.contestants_per_region(tournament)
    seed_pairs = Tournaments.seeding_pattern(contestants_per_region)
    matchups_per_region = div(contestants_per_region, 2)

    # Build data for each region with correct offsets
    region_names
    |> Enum.with_index()
    |> Enum.map(fn {region_name, idx} ->
      offset = idx * matchups_per_region
      {region_name, build_region_data(Map.get(by_region, region_name, []), seed_pairs, offset)}
    end)
    |> Map.new()
  end

  # Calculate position bases for each round dynamically based on tournament config
  defp calculate_round_bases(tournament) do
    bracket_size = tournament.bracket_size || 64
    region_count = tournament.region_count || 4
    contestants_per_region = div(bracket_size, region_count)
    total_rounds = Tournament.total_rounds(tournament)
    regional_rounds = trunc(:math.log2(contestants_per_region))

    # Calculate cumulative positions for each round
    # Round 1 base = 0 (positions start at 1)
    # Round N base = sum of all matchups in rounds 1 to N-1
    round_bases = Enum.reduce(1..total_rounds, %{1 => 0}, fn round, acc ->
      if round == 1 do
        acc
      else
        # Previous round's base + matchups in previous round
        prev_base = Map.get(acc, round - 1, 0)
        prev_matchups = div(bracket_size, trunc(:math.pow(2, round - 1)))
        Map.put(acc, round, prev_base + prev_matchups)
      end
    end)

    %{
      round_bases: round_bases,
      bracket_size: bracket_size,
      region_count: region_count,
      contestants_per_region: contestants_per_region,
      total_rounds: total_rounds,
      regional_rounds: regional_rounds,
      matchups_per_region_r1: div(contestants_per_region, 2)
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
              <%= if @time_remaining && !@is_submitted do %>
                <div class={["text-sm", @time_remaining.expired && "text-red-400", !@time_remaining.expired && "text-yellow-400"]}>
                  <%= if @time_remaining.expired do %>
                    <span class="font-medium">Deadline passed</span>
                  <% else %>
                    <span class="text-gray-400">Deadline:</span>
                    <span class="font-medium">
                      <%= if @time_remaining.days > 0 do %><%= @time_remaining.days %>d <% end %><%= String.pad_leading(to_string(@time_remaining.hours), 2, "0") %>:<%= String.pad_leading(to_string(@time_remaining.minutes), 2, "0") %>:<%= String.pad_leading(to_string(@time_remaining.seconds), 2, "0") %>
                    </span>
                  <% end %>
                </div>
              <% end %>
              <div class="text-gray-400 text-sm">
                <span class="text-white font-medium"><%= @picks_count %></span>/<%= @total_matchups %> picks
              </div>
              <%= if @is_submitted do %>
                <span class="bg-green-600 text-white px-3 py-1 rounded text-sm">
                  Submitted
                </span>
              <% else %>
                <button
                  phx-click="submit_bracket"
                  disabled={@picks_count != @total_matchups}
                  class={"px-4 py-2 rounded text-sm font-medium transition-colors #{if @picks_count == @total_matchups, do: "bg-green-600 hover:bg-green-700 text-white", else: "bg-gray-700 text-gray-500 cursor-not-allowed"}"}
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

        <!-- Bracket Layout -->
        <% region_names = @tournament.region_names || ["East", "West", "South", "Midwest"] %>

        <!-- Calculate regional winner positions dynamically for Final Four connections -->
        <% bracket_size = @tournament.bracket_size || 64 %>
        <% region_count = @tournament.region_count || 4 %>
        <% contestants_per_region = div(bracket_size, region_count) %>
        <% regional_rounds = trunc(:math.log2(contestants_per_region)) %>

        <!-- Calculate where regional winners are (last round before Final Four) -->
        <%
          # For 64-bracket: regional_rounds=4, winner is in round 4 (Elite 8)
          # For 32-bracket: regional_rounds=3, winner is in round 3
          # Each round halves the matchups, so we sum them up

          # Calculate base position for the regional winner round
          r1_matchups = div(bracket_size, 2)
          r2_matchups = div(bracket_size, 4)
          r3_matchups = div(bracket_size, 8)

          # For 32-bracket: regional winner is at R3 (positions 25-28)
          # For 64-bracket: regional winner is at R4/Elite 8 (positions 57-60)
          regional_winner_base = case regional_rounds do
            3 -> r1_matchups + r2_matchups  # 32-bracket: R3 winners
            4 -> r1_matchups + r2_matchups + r3_matchups  # 64-bracket: R4 winners
            _ -> r1_matchups + r2_matchups + r3_matchups  # Default to 64-bracket logic
          end

          # Regional winner positions (1 per region)
          regional_winner_1 = regional_winner_base + 1
          regional_winner_2 = regional_winner_base + 2
          regional_winner_3 = regional_winner_base + 3
          regional_winner_4 = regional_winner_base + 4

          # Final Four positions come right after regional winners
          ff_base = regional_winner_base + region_count
          ff1_pos = ff_base + 1
          ff2_pos = ff_base + 2
        %>

        <!-- ESPN-Style Bracket Layout - Horizontal scroll on all devices -->
        <div class="overflow-x-auto pb-4">
          <div class="min-w-[1400px]">

            <!-- Top Half: First region (left) and Second region (right) -->
            <div class="flex justify-between">
              <!-- FIRST REGION - flows left to right -->
              <div class="flex-1">
                <div class="text-center mb-3">
                  <span class="text-blue-400 font-bold text-lg uppercase tracking-wider"><%= Enum.at(region_names, 0) %></span>
                </div>
                <.region_bracket_left
                  region_data={@regions_data[Enum.at(region_names, 0)]}
                  picks={@picks}
                  contestants_map={@contestants_map}
                  is_submitted={@is_submitted}
                  region={Enum.at(region_names, 0)}
                  tournament={@tournament}
                  position="top"
                />
              </div>

              <!-- SECOND REGION - flows right to left -->
              <div class="flex-1">
                <div class="text-center mb-3">
                  <span class="text-blue-400 font-bold text-lg uppercase tracking-wider"><%= Enum.at(region_names, 1) %></span>
                </div>
                <.region_bracket_right
                  region_data={@regions_data[Enum.at(region_names, 1)]}
                  picks={@picks}
                  contestants_map={@contestants_map}
                  is_submitted={@is_submitted}
                  region={Enum.at(region_names, 1)}
                  tournament={@tournament}
                  position="top"
                />
              </div>
            </div>

            <!-- Center Section: Final Four + Championship (horizontal) - matches region layout -->
            <div class="flex justify-between items-start my-6">
              <!-- Left spacer with Final Four 1 (East vs South - left-side regions) -->
              <div class="flex-1 flex justify-end">
                <div class="w-48">
                <.final_four_slot
                  position={ff1_pos}
                  label={Tournaments.get_round_name(@tournament, Tournament.total_rounds(@tournament) - 1)}
                  source_a={regional_winner_1}
                  source_b={regional_winner_3}
                  placeholder_a={"#{Enum.at(region_names, 0)} Winner"}
                  placeholder_b={"#{Enum.at(region_names, 2)} Winner"}
                  picks={@picks}
                  contestants_map={@contestants_map}
                  is_submitted={@is_submitted}
                />
                </div>
              </div>

              <!-- Championship (center) -->
              <div class="w-56 mx-4">
              <.championship_slot
                picks={@picks}
                contestants_map={@contestants_map}
                is_submitted={@is_submitted}
                tournament={@tournament}
              />
              </div>

              <!-- Right spacer with Final Four 2 (West vs Midwest - right-side regions) -->
              <div class="flex-1 flex justify-start">
                <%= if region_count >= 4 do %>
                  <div class="w-48">
                  <.final_four_slot
                    position={ff2_pos}
                    label={Tournaments.get_round_name(@tournament, Tournament.total_rounds(@tournament) - 1)}
                    source_a={regional_winner_2}
                    source_b={regional_winner_4}
                    placeholder_a={"#{Enum.at(region_names, 1)} Winner"}
                    placeholder_b={"#{Enum.at(region_names, 3)} Winner"}
                    picks={@picks}
                    contestants_map={@contestants_map}
                    is_submitted={@is_submitted}
                  />
                  </div>
                <% end %>
              </div>
            </div>

            <%= if region_count >= 4 do %>
              <!-- Bottom Half: Third region (left) and Fourth region (right) -->
              <div class="flex justify-between">
                <!-- THIRD REGION - flows left to right -->
                <div class="flex-1">
                  <div class="text-center mb-3">
                    <span class="text-blue-400 font-bold text-lg uppercase tracking-wider"><%= Enum.at(region_names, 2) %></span>
                  </div>
                  <.region_bracket_left
                    region_data={@regions_data[Enum.at(region_names, 2)]}
                    picks={@picks}
                    contestants_map={@contestants_map}
                    is_submitted={@is_submitted}
                    region={Enum.at(region_names, 2)}
                    tournament={@tournament}
                    position="bottom"
                  />
                </div>

                <!-- FOURTH REGION - flows right to left -->
                <div class="flex-1">
                  <div class="text-center mb-3">
                    <span class="text-blue-400 font-bold text-lg uppercase tracking-wider"><%= Enum.at(region_names, 3) %></span>
                  </div>
                  <.region_bracket_right
                    region_data={@regions_data[Enum.at(region_names, 3)]}
                    picks={@picks}
                    contestants_map={@contestants_map}
                    is_submitted={@is_submitted}
                    region={Enum.at(region_names, 3)}
                    tournament={@tournament}
                    position="bottom"
                  />
                </div>
              </div>
            <% end %>
          </div>
        </div>
      </main>
    </div>
    """
  end

  # Left-side region bracket (East, South) - flows left to right
  defp region_bracket_left(assigns) do
    offset = assigns.region_data.offset
    tournament = assigns.tournament

    # Get tournament configuration
    bracket_size = tournament.bracket_size || 64
    region_count = tournament.region_count || 4
    contestants_per_region = div(bracket_size, region_count)
    matchups_per_region_r1 = div(contestants_per_region, 2)
    regional_rounds = trunc(:math.log2(contestants_per_region))

    # Calculate base positions for each round dynamically
    # Round 1: positions 1 to (bracket_size/2)
    # Round 2: positions (bracket_size/2 + 1) to (bracket_size/2 + bracket_size/4)
    # etc.
    r1_total = div(bracket_size, 2)
    r2_total = div(bracket_size, 4)
    r3_total = div(bracket_size, 8)

    # Round bases (0-indexed for calculation, positions are 1-indexed)
    r2_base_global = r1_total
    r3_base_global = r1_total + r2_total
    r4_base_global = r1_total + r2_total + r3_total

    # Region-specific offsets within each round
    # Region 0 offset = 0, Region 1 offset = matchups_per_region_in_round, etc.
    region_index = div(offset, matchups_per_region_r1)

    r2_matchups_per_region = div(matchups_per_region_r1, 2)
    r3_matchups_per_region = div(r2_matchups_per_region, 2)
    r4_matchups_per_region = div(r3_matchups_per_region, 2)

    r2_base = r2_base_global + region_index * r2_matchups_per_region
    r3_base = r3_base_global + region_index * r3_matchups_per_region
    r4_pos = r4_base_global + region_index * max(r4_matchups_per_region, 1) + 1

    # Calculate container height based on matchups in round 1
    # 32-bracket: 4 matchups * 80px = 320px
    # 64-bracket: 8 matchups * 80px = 640px
    container_height = matchups_per_region_r1 * 80

    # Get position (top or bottom) - bottom regions need final round aligned to top
    position = Map.get(assigns, :position, "top")

    assigns = assigns
      |> assign(:r2_base, r2_base)
      |> assign(:r3_base, r3_base)
      |> assign(:r4_pos, r4_pos)
      |> assign(:offset, offset)
      |> assign(:r2_matchups_per_region, r2_matchups_per_region)
      |> assign(:r3_matchups_per_region, r3_matchups_per_region)
      |> assign(:regional_rounds, regional_rounds)
      |> assign(:container_height, container_height)
      |> assign(:matchups_per_region_r1, matchups_per_region_r1)
      |> assign(:position, position)

    ~H"""
    <div class="flex items-center">
      <!-- Round 1 matchups -->
      <div class="flex flex-col justify-around" style={"min-height: #{@container_height}px;"}>
        <%= for {matchup, idx} <- Enum.with_index(@region_data.matchups) do %>
          <div class="relative">
            <.pick_matchup_box
              position={matchup.position}
              contestant_a={matchup.contestant_a}
              contestant_b={matchup.contestant_b}
              picks={@picks}
              is_submitted={@is_submitted}
              size="small"
            />
            <!-- Horizontal line to connector -->
            <div class="absolute right-0 top-1/2 w-4 h-px bg-gray-600 translate-x-full"></div>
            <!-- Vertical connector: pairs connect (0-1, 2-3, etc.) -->
            <% r1_connector = div(@container_height, @matchups_per_region_r1 * 2) %>
            <%= if rem(idx, 2) == 0 do %>
              <div class="absolute right-0 top-1/2 w-px bg-gray-600 translate-x-[calc(100%+16px)]" style={"height: #{r1_connector}px;"}></div>
            <% else %>
              <div class="absolute right-0 bottom-1/2 w-px bg-gray-600 translate-x-[calc(100%+16px)]" style={"height: #{r1_connector}px;"}></div>
            <% end %>
          </div>
        <% end %>
      </div>

      <!-- Connector column R1->R2 -->
      <div class="w-4"></div>

      <!-- Round 2 matchups (dynamic count) -->
      <%= if @r2_matchups_per_region > 0 do %>
        <div class="flex flex-col justify-around" style={"min-height: #{@container_height}px;"}>
          <%= for idx <- 0..(@r2_matchups_per_region - 1) do %>
            <% position = @r2_base + idx + 1 %>
            <% source_a = @offset + idx * 2 + 1 %>
            <% source_b = @offset + idx * 2 + 2 %>
            <div class="relative">
              <.pick_matchup_box_from_picks
                position={position}
                source_a={source_a}
                source_b={source_b}
                picks={@picks}
                contestants_map={@contestants_map}
                is_submitted={@is_submitted}
                size="small"
              />
              <!-- Horizontal line to next connector -->
              <div class="absolute right-0 top-1/2 w-4 h-px bg-gray-600 translate-x-full"></div>
              <!-- Vertical connector for pairs -->
              <% r2_connector = div(@container_height, @r2_matchups_per_region * 2) %>
              <%= if rem(idx, 2) == 0 do %>
                <div class="absolute right-0 top-1/2 w-px bg-gray-600 translate-x-[calc(100%+16px)]" style={"height: #{r2_connector}px;"}></div>
              <% else %>
                <div class="absolute right-0 bottom-1/2 w-px bg-gray-600 translate-x-[calc(100%+16px)]" style={"height: #{r2_connector}px;"}></div>
              <% end %>
            </div>
          <% end %>
        </div>

        <!-- Connector column R2->R3 -->
        <div class="w-4"></div>
      <% end %>

      <!-- Round 3 matchups (dynamic count) -->
      <%= if @r3_matchups_per_region > 0 do %>
        <div class="flex flex-col justify-around" style={"min-height: #{@container_height}px;"}>
          <%= for idx <- 0..(@r3_matchups_per_region - 1) do %>
            <% position = @r3_base + idx + 1 %>
            <% source_a = @r2_base + idx * 2 + 1 %>
            <% source_b = @r2_base + idx * 2 + 2 %>
            <div class="relative">
              <.pick_matchup_box_from_picks
                position={position}
                source_a={source_a}
                source_b={source_b}
                picks={@picks}
                contestants_map={@contestants_map}
                is_submitted={@is_submitted}
              />
              <!-- Only draw connectors if there's another round (Elite 8) -->
              <%= if @regional_rounds >= 4 do %>
                <!-- Horizontal line to next connector -->
                <div class="absolute right-0 top-1/2 w-4 h-px bg-gray-600 translate-x-full"></div>
                <!-- Vertical connector for pair -->
                <% r3_connector = div(@container_height, @r3_matchups_per_region * 2) %>
                <%= if rem(idx, 2) == 0 do %>
                  <div class="absolute right-0 top-1/2 w-px bg-gray-600 translate-x-[calc(100%+16px)]" style={"height: #{r3_connector}px;"}></div>
                <% else %>
                  <div class="absolute right-0 bottom-1/2 w-px bg-gray-600 translate-x-[calc(100%+16px)]" style={"height: #{r3_connector}px;"}></div>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </div>

        <!-- Connector column R3->R4 (only if there's an Elite 8 round) -->
        <%= if @regional_rounds >= 4 do %>
          <div class="w-4"></div>
        <% end %>
      <% end %>

      <!-- Elite 8 (region winner matchup) -->
      <%= if @regional_rounds >= 4 do %>
        <div class="flex flex-col justify-center" style={"min-height: #{@container_height}px;"}>
          <div class="relative">
            <.pick_matchup_box_from_picks
              position={@r4_pos}
              source_a={@r3_base + 1}
              source_b={@r3_base + 2}
              picks={@picks}
              contestants_map={@contestants_map}
              is_submitted={@is_submitted}
            />
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Right-side region bracket (West, Midwest) - flows right to left
  defp region_bracket_right(assigns) do
    offset = assigns.region_data.offset
    tournament = assigns.tournament

    # Get tournament configuration
    bracket_size = tournament.bracket_size || 64
    region_count = tournament.region_count || 4
    contestants_per_region = div(bracket_size, region_count)
    matchups_per_region_r1 = div(contestants_per_region, 2)
    regional_rounds = trunc(:math.log2(contestants_per_region))

    # Calculate base positions for each round dynamically
    r1_total = div(bracket_size, 2)
    r2_total = div(bracket_size, 4)
    r3_total = div(bracket_size, 8)

    # Round bases (0-indexed for calculation, positions are 1-indexed)
    r2_base_global = r1_total
    r3_base_global = r1_total + r2_total
    r4_base_global = r1_total + r2_total + r3_total

    # Region-specific offsets within each round
    region_index = div(offset, matchups_per_region_r1)

    r2_matchups_per_region = div(matchups_per_region_r1, 2)
    r3_matchups_per_region = div(r2_matchups_per_region, 2)
    r4_matchups_per_region = div(r3_matchups_per_region, 2)

    r2_base = r2_base_global + region_index * r2_matchups_per_region
    r3_base = r3_base_global + region_index * r3_matchups_per_region
    r4_pos = r4_base_global + region_index * max(r4_matchups_per_region, 1) + 1

    # Calculate container height based on matchups in round 1
    container_height = matchups_per_region_r1 * 80

    # Get position (top or bottom) - bottom regions need final round aligned to top
    position = Map.get(assigns, :position, "top")

    assigns = assigns
      |> assign(:r2_base, r2_base)
      |> assign(:r3_base, r3_base)
      |> assign(:r4_pos, r4_pos)
      |> assign(:offset, offset)
      |> assign(:r2_matchups_per_region, r2_matchups_per_region)
      |> assign(:r3_matchups_per_region, r3_matchups_per_region)
      |> assign(:regional_rounds, regional_rounds)
      |> assign(:container_height, container_height)
      |> assign(:matchups_per_region_r1, matchups_per_region_r1)
      |> assign(:position, position)

    ~H"""
    <div class="flex items-center justify-end">
      <!-- Elite 8 (region winner matchup) -->
      <%= if @regional_rounds >= 4 do %>
        <div class="flex flex-col justify-center" style={"min-height: #{@container_height}px;"}>
          <div class="relative">
            <.pick_matchup_box_from_picks
              position={@r4_pos}
              source_a={@r3_base + 1}
              source_b={@r3_base + 2}
              picks={@picks}
              contestants_map={@contestants_map}
              is_submitted={@is_submitted}
            />
            <!-- Horizontal connector to R3 vertical line -->
            <div class="absolute right-0 top-1/2 w-4 h-px bg-gray-600 translate-x-full"></div>
          </div>
        </div>

        <!-- Spacer between Elite 8 and R3 -->
        <div class="w-4"></div>
      <% end %>

      <!-- Round 3 matchups (dynamic count) -->
      <%= if @r3_matchups_per_region > 0 do %>

        <div class="flex flex-col justify-around" style={"min-height: #{@container_height}px;"}>
          <%= for idx <- 0..(@r3_matchups_per_region - 1) do %>
            <% position = @r3_base + idx + 1 %>
            <% source_a = @r2_base + idx * 2 + 1 %>
            <% source_b = @r2_base + idx * 2 + 2 %>
            <div class="relative">
              <!-- Only draw connectors if there's another round (Elite 8) -->
              <%= if @regional_rounds >= 4 do %>
                <!-- Horizontal line to next connector (toward Elite 8) -->
                <div class="absolute left-0 top-1/2 w-4 h-px bg-gray-600 -translate-x-full"></div>
                <!-- Vertical connector for pair -->
                <% r3_connector = div(@container_height, @r3_matchups_per_region * 2) %>
                <%= if rem(idx, 2) == 0 do %>
                  <div class="absolute left-0 top-1/2 w-px bg-gray-600 -translate-x-[16px]" style={"height: #{r3_connector}px;"}></div>
                <% else %>
                  <div class="absolute left-0 bottom-1/2 w-px bg-gray-600 -translate-x-[16px]" style={"height: #{r3_connector}px;"}></div>
                <% end %>
              <% end %>
              <.pick_matchup_box_from_picks
                position={position}
                source_a={source_a}
                source_b={source_b}
                picks={@picks}
                contestants_map={@contestants_map}
                is_submitted={@is_submitted}
              />
            </div>
          <% end %>
        </div>

        <!-- Connector column R3<-R2 -->
        <div class="w-4"></div>
      <% end %>

      <!-- Round 2 matchups (dynamic count) -->
      <%= if @r2_matchups_per_region > 0 do %>
        <div class="flex flex-col justify-around" style={"min-height: #{@container_height}px;"}>
          <%= for idx <- 0..(@r2_matchups_per_region - 1) do %>
            <% position = @r2_base + idx + 1 %>
            <% source_a = @offset + idx * 2 + 1 %>
            <% source_b = @offset + idx * 2 + 2 %>
            <div class="relative">
              <!-- Horizontal line to next connector (toward Sweet 16) -->
              <div class="absolute left-0 top-1/2 w-4 h-px bg-gray-600 -translate-x-full"></div>
              <!-- Vertical connector for pairs -->
              <% r2_connector = div(@container_height, @r2_matchups_per_region * 2) %>
              <%= if rem(idx, 2) == 0 do %>
                <div class="absolute left-0 top-1/2 w-px bg-gray-600 -translate-x-[16px]" style={"height: #{r2_connector}px;"}></div>
              <% else %>
                <div class="absolute left-0 bottom-1/2 w-px bg-gray-600 -translate-x-[16px]" style={"height: #{r2_connector}px;"}></div>
              <% end %>
              <.pick_matchup_box_from_picks
                position={position}
                source_a={source_a}
                source_b={source_b}
                picks={@picks}
                contestants_map={@contestants_map}
                is_submitted={@is_submitted}
                size="small"
              />
            </div>
          <% end %>
        </div>

        <!-- Connector column R2<-R1 -->
        <div class="w-4"></div>
      <% end %>

      <!-- Round 1 matchups -->
      <div class="flex flex-col justify-around" style={"min-height: #{@container_height}px;"}>
        <%= for {matchup, idx} <- Enum.with_index(@region_data.matchups) do %>
          <div class="relative">
            <!-- Horizontal line to connector (toward Round 2) -->
            <div class="absolute left-0 top-1/2 w-4 h-px bg-gray-600 -translate-x-full"></div>
            <!-- Vertical connector: pairs connect (0-1, 2-3, etc.) -->
            <% r1_connector = div(@container_height, @matchups_per_region_r1 * 2) %>
            <%= if rem(idx, 2) == 0 do %>
              <div class="absolute left-0 top-1/2 w-px bg-gray-600 -translate-x-[16px]" style={"height: #{r1_connector}px;"}></div>
            <% else %>
              <div class="absolute left-0 bottom-1/2 w-px bg-gray-600 -translate-x-[16px]" style={"height: #{r1_connector}px;"}></div>
            <% end %>
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
      @current_pick && "border-blue-500",
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
      @current_pick && "border-blue-500",
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
          @is_picked && "bg-blue-600/40",
          !@is_picked && !@is_submitted && "hover:bg-gray-700",
          @is_submitted && "cursor-default"
        ]}
      >
        <span class={[
          "text-xs font-mono w-5",
          @is_picked && "text-blue-300",
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
          <span class="text-blue-300 text-xs">✓</span>
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
        "bg-gray-800 border rounded overflow-hidden w-full",
        @current_pick && "border-blue-500",
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
              @current_pick == @contestant_a.id && "bg-blue-600/40",
              @current_pick != @contestant_a.id && !@is_submitted && "hover:bg-gray-700"
            ]}
          >
            <span class="text-xs font-mono w-5 text-gray-500"><%= @contestant_a.seed %></span>
            <span class={["text-xs truncate flex-1", @current_pick == @contestant_a.id && "text-white font-semibold", @current_pick != @contestant_a.id && "text-gray-300"]}>
              <%= @contestant_a.name %>
            </span>
            <%= if @current_pick == @contestant_a.id do %><span class="text-blue-300 text-xs">✓</span><% end %>
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
              @current_pick == @contestant_b.id && "bg-blue-600/40",
              @current_pick != @contestant_b.id && !@is_submitted && "hover:bg-gray-700"
            ]}
          >
            <span class="text-xs font-mono w-5 text-gray-500"><%= @contestant_b.seed %></span>
            <span class={["text-xs truncate flex-1", @current_pick == @contestant_b.id && "text-white font-semibold", @current_pick != @contestant_b.id && "text-gray-300"]}>
              <%= @contestant_b.name %>
            </span>
            <%= if @current_pick == @contestant_b.id do %><span class="text-blue-300 text-xs">✓</span><% end %>
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
    # Calculate positions dynamically based on tournament config
    tournament = assigns.tournament
    bracket_size = tournament.bracket_size || 64
    region_count = tournament.region_count || 4
    contestants_per_region = div(bracket_size, region_count)
    regional_rounds = trunc(:math.log2(contestants_per_region))

    # Calculate regional winner base (same logic as render template)
    r1_matchups = div(bracket_size, 2)
    r2_matchups = div(bracket_size, 4)
    r3_matchups = div(bracket_size, 8)

    regional_winner_base = case regional_rounds do
      3 -> r1_matchups + r2_matchups  # 32-bracket: R3 winners at 25-28
      4 -> r1_matchups + r2_matchups + r3_matchups  # 64-bracket: R4 winners at 57-60
      _ -> r1_matchups + r2_matchups + r3_matchups
    end

    # Final Four positions come right after regional winners
    ff_base = regional_winner_base + region_count
    ff1_pos = ff_base + 1
    ff2_pos = ff_base + 2
    # Championship is after Final Four
    championship_pos = ff_base + 3

    # Championship contestants come from Final Four picks
    pick_a = Map.get(assigns.picks, to_string(ff1_pos))
    pick_b = Map.get(assigns.picks, to_string(ff2_pos))

    contestant_a = if pick_a, do: Map.get(assigns.contestants_map, pick_a)
    contestant_b = if pick_b, do: Map.get(assigns.contestants_map, pick_b)

    current_pick = Map.get(assigns.picks, to_string(championship_pos))
    champion = if current_pick, do: Map.get(assigns.contestants_map, current_pick)

    assigns = assigns
      |> assign(:contestant_a, contestant_a)
      |> assign(:contestant_b, contestant_b)
      |> assign(:current_pick, current_pick)
      |> assign(:champion, champion)
      |> assign(:championship_pos, championship_pos)

    ~H"""
    <div class="text-center">
      <div class="text-xs text-yellow-500 font-bold mb-1 uppercase">Championship</div>
      <div class={[
        "bg-gray-800 border rounded overflow-hidden w-full",
        @current_pick && "border-yellow-500 ring-1 ring-yellow-500/50",
        !@current_pick && "border-gray-700"
      ]}>
        <%= if @contestant_a do %>
          <button
            phx-click="pick"
            phx-value-position={@championship_pos}
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
            phx-value-position={@championship_pos}
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
      bracket_config = socket.assigns.bracket_config

      # Clear downstream picks when changing an earlier round pick
      picks = clear_downstream_picks(picks, position, contestant_id, bracket_config)

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
    required_picks = socket.assigns.total_matchups

    if socket.assigns.is_submitted or socket.assigns.picks_count != required_picks do
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

        {:error, :deadline_passed} ->
          {:noreply, put_flash(socket, :error, "The registration deadline has passed")}

        {:error, :incomplete_bracket} ->
          {:noreply, put_flash(socket, :error, "Please complete all #{required_picks} picks")}
      end
    end
  end

  # Clear picks that depend on a changed pick
  defp clear_downstream_picks(picks, changed_position, new_contestant_id, bracket_config) do
    old_contestant_id = Map.get(picks, to_string(changed_position))

    # If pick didn't change, no need to clear
    if old_contestant_id == new_contestant_id do
      picks
    else
      # Find all positions that feed from this position and clear them if they had the old contestant
      downstream_positions = get_downstream_positions(changed_position, bracket_config)

      Enum.reduce(downstream_positions, picks, fn pos, acc ->
        if Map.get(acc, to_string(pos)) == old_contestant_id do
          # This downstream pick had the contestant we're removing, clear it
          clear_downstream_picks(Map.delete(acc, to_string(pos)), pos, nil, bracket_config)
        else
          acc
        end
      end)
    end
  end

  # Get positions that are fed by a given position (dynamic based on bracket config)
  defp get_downstream_positions(position, bracket_config) do
    bracket_size = bracket_config.bracket_size
    total_matchups = bracket_size - 1

    # Calculate round boundaries dynamically
    round_boundaries = calculate_round_boundaries(bracket_size)

    # Find which round this position belongs to
    current_round = find_round_for_position(position, round_boundaries)

    if current_round == nil do
      []
    else
      # Get the next round's base position
      next_round = current_round + 1
      next_round_base = Map.get(round_boundaries, next_round)

      if next_round_base == nil do
        # This is the last round (championship), no downstream
        []
      else
        current_round_base = Map.get(round_boundaries, current_round)
        # Position within current round (0-indexed)
        pos_in_round = position - current_round_base - 1
        # Each pair of matchups feeds one matchup in next round
        next_pos = next_round_base + div(pos_in_round, 2) + 1

        if next_pos <= total_matchups do
          [next_pos | get_downstream_positions(next_pos, bracket_config)]
        else
          []
        end
      end
    end
  end

  # Calculate round boundary positions (round number -> base position)
  defp calculate_round_boundaries(bracket_size) do
    total_rounds = trunc(:math.log2(bracket_size))

    Enum.reduce(1..total_rounds, {%{}, 0}, fn round, {acc, cumulative} ->
      matchups_in_round = div(bracket_size, trunc(:math.pow(2, round)))
      {Map.put(acc, round, cumulative), cumulative + matchups_in_round}
    end)
    |> elem(0)
  end

  # Find which round a position belongs to
  defp find_round_for_position(position, round_boundaries) do
    # Sort rounds and find which range the position falls into
    sorted_rounds = round_boundaries |> Map.to_list() |> Enum.sort_by(&elem(&1, 0))

    Enum.find_value(Enum.with_index(sorted_rounds), fn {{round, base}, idx} ->
      next_base = case Enum.at(sorted_rounds, idx + 1) do
        {_, next_b} -> next_b
        nil -> :infinity
      end

      if position > base and position <= next_base do
        round
      else
        nil
      end
    end)
  end

  defp count_picks(picks) do
    picks
    |> Map.values()
    |> Enum.count(&(&1 != nil))
  end

  # Handle countdown tick
  @impl true
  def handle_info(:tick_countdown, socket) do
    time_remaining = calculate_time_remaining(socket.assigns.tournament.registration_deadline)
    {:noreply, assign(socket, time_remaining: time_remaining)}
  end

  defp calculate_time_remaining(nil), do: nil
  defp calculate_time_remaining(deadline) do
    now = DateTime.utc_now()
    case DateTime.compare(deadline, now) do
      :gt ->
        diff = DateTime.diff(deadline, now, :second)
        days = div(diff, 86400)
        hours = div(rem(diff, 86400), 3600)
        minutes = div(rem(diff, 3600), 60)
        seconds = rem(diff, 60)
        %{days: days, hours: hours, minutes: minutes, seconds: seconds, expired: false}
      _ ->
        %{days: 0, hours: 0, minutes: 0, seconds: 0, expired: true}
    end
  end
end
