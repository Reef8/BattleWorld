defmodule BracketBattleWeb.TournamentLive do
  @moduledoc """
  Main tournament page showing the live bracket, voting section, and chat.
  """
  use BracketBattleWeb, :live_view

  alias BracketBattle.Accounts
  alias BracketBattle.Tournaments
  alias BracketBattle.Brackets
  alias BracketBattle.Voting
  alias BracketBattle.Chat

  @impl true
  def mount(%{"id" => tournament_id}, session, socket) do
    user = if user_id = session["user_id"] do
      Accounts.get_user(user_id)
    end

    case Tournaments.get_tournament(tournament_id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Tournament not found")
         |> push_navigate(to: "/")}

      tournament ->
        mount_tournament(socket, tournament, user, tournament_id)
    end
  end

  defp mount_tournament(socket, tournament, user, tournament_id) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(BracketBattle.PubSub, "tournament:#{tournament_id}")
      Phoenix.PubSub.subscribe(BracketBattle.PubSub, "tournament:#{tournament_id}:votes")
      Phoenix.PubSub.subscribe(BracketBattle.PubSub, "tournament:#{tournament_id}:chat")
      Phoenix.PubSub.subscribe(BracketBattle.PubSub, "tournament:#{tournament_id}:leaderboard")

      # Start countdown timer
      if tournament.status == "active" do
        :timer.send_interval(1000, self(), :tick)
      end
    end

    # Get user's bracket if they have one
    user_bracket = if user, do: Brackets.get_user_bracket(tournament_id, user.id)
    has_bracket = user_bracket && user_bracket.submitted_at

    # Get active matchups for voting
    active_matchups = if tournament.status == "active" do
      Tournaments.get_active_matchups(tournament_id)
      |> load_vote_counts()
      |> load_user_votes(user)
    else
      []
    end

    # Get all matchups for bracket display
    all_matchups = Tournaments.get_all_matchups(tournament_id)

    # Build contestants map for My Bracket tab
    contestants = Tournaments.list_contestants(tournament_id)
    contestants_map = Map.new(contestants, fn c -> {c.id, c} end)

    # Get recent chat messages
    messages = Chat.get_messages(tournament_id, limit: 50)

    # Get leaderboard
    leaderboard = Brackets.get_leaderboard(tournament_id, limit: 50)

    # Build pending_votes from existing user votes (using string keys for consistency)
    # Use Map.get to safely handle anonymous users where user_vote key doesn't exist
    pending_votes = active_matchups
      |> Enum.filter(fn m -> Map.get(m, :user_vote) end)
      |> Enum.map(fn m -> {to_string(m.id), to_string(m.user_vote.contestant_id)} end)
      |> Enum.into(%{})

    {:ok,
     assign(socket,
       page_title: tournament.name,
       current_user: user,
       tournament: tournament,
       user_bracket: user_bracket,
       has_bracket: has_bracket,
       active_matchups: active_matchups,
       all_matchups: all_matchups,
       contestants_map: contestants_map,
       messages: messages,
       leaderboard: leaderboard,
       message_input: "",
       tab: "bracket",
       pending_votes: pending_votes,
       submitted: false,
       # Round completion reveal state
       show_round_reveal: false,
       round_completed: nil,
       completed_round_name: nil,
       # Tournament complete popup state
       show_tournament_complete: false,
       user_final_rank: nil,
       user_final_score: nil,
       # Mobile menu
       show_mobile_menu: false
     )}
  end

  defp load_vote_counts(matchups) do
    Enum.map(matchups, fn matchup ->
      counts = Voting.get_vote_counts(matchup.id)
      Map.put(matchup, :vote_counts, counts)
    end)
  end

  defp load_user_votes(matchups, nil), do: matchups
  defp load_user_votes(matchups, user) do
    Enum.map(matchups, fn matchup ->
      vote = Voting.get_user_vote(matchup.id, user.id)
      Map.put(matchup, :user_vote, vote)
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <!-- Round Completion Reveal Banner -->
    <%= if @show_round_reveal do %>
      <.round_reveal_banner round_name={@completed_round_name} />
    <% end %>

    <!-- Tournament Complete Popup -->
    <%= if @show_tournament_complete do %>
      <.tournament_complete_popup rank={@user_final_rank} score={@user_final_score} />
    <% end %>

    <div class="min-h-screen bg-gray-900">
      <!-- Header -->
      <header class="bg-gray-800 border-b border-gray-700 sticky top-0 z-10">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between items-center h-16">
            <div class="flex items-center space-x-2 md:space-x-4 min-w-0">
              <a href="/" class="text-gray-400 hover:text-white text-sm shrink-0">&larr; Home</a>
              <h1 class="text-lg md:text-xl font-bold text-white truncate"><%= @tournament.name %></h1>
              <span class={"hidden sm:inline-block px-2 py-1 rounded text-xs font-medium shrink-0 #{status_color(@tournament.status)}"}>
                <%= status_label(@tournament.status) %>
              </span>
            </div>

            <!-- Desktop nav -->
            <div class="hidden md:flex items-center space-x-4">
              <%= if @current_user do %>
                <%= if @tournament.status == "registration" do %>
                  <a href={"/tournament/#{@tournament.id}/bracket"} class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded text-sm">
                    <%= if @has_bracket, do: "View Bracket", else: "Fill Bracket" %>
                  </a>
                <% end %>
                <span class="text-gray-400 text-sm"><%= @current_user.display_name || @current_user.email %></span>
              <% else %>
                <a href="/auth/signin" class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded text-sm">
                  Sign In
                </a>
              <% end %>
            </div>

            <!-- Mobile hamburger button -->
            <button
              phx-click="toggle_mobile_menu"
              class="md:hidden p-2 text-gray-400 hover:text-white shrink-0"
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
              <%= if @current_user do %>
                <%= if @tournament.status == "registration" do %>
                  <a href={"/tournament/#{@tournament.id}/bracket"} class="block py-2 text-blue-400 hover:text-blue-300">
                    <%= if @has_bracket, do: "View Bracket", else: "Fill Bracket" %>
                  </a>
                <% end %>
                <div class="py-2 text-gray-400 text-sm">
                  <%= @current_user.display_name || @current_user.email %>
                </div>
                <a href="/dashboard" class="block py-2 text-gray-400 hover:text-white">
                  My Dashboard
                </a>
                <a href="/auth/signout" class="block py-2 text-gray-400 hover:text-white">
                  Sign Out
                </a>
              <% else %>
                <a href="/auth/signin" class="block py-2 text-blue-400 hover:text-blue-300">
                  Sign In
                </a>
              <% end %>
            </div>
          </div>
        <% end %>
      </header>

      <!-- Tab Navigation -->
      <div class="bg-gray-800 border-b border-gray-700 overflow-x-auto">
        <div class="max-w-7xl mx-auto px-4">
          <nav class="flex space-x-1 sm:space-x-4 min-w-max">
            <button
              phx-click="switch_tab"
              phx-value-tab="bracket"
              class={"px-3 sm:px-4 py-3 min-h-[44px] text-sm font-medium border-b-2 transition-colors whitespace-nowrap #{if @tab == "bracket", do: "border-blue-500 text-white", else: "border-transparent text-gray-400 hover:text-white"}"}
            >
              Bracket
            </button>
            <%= if @tournament.status == "active" do %>
              <button
                phx-click="switch_tab"
                phx-value-tab="voting"
                class={"px-3 sm:px-4 py-3 min-h-[44px] text-sm font-medium border-b-2 transition-colors whitespace-nowrap #{if @tab == "voting", do: "border-blue-500 text-white", else: "border-transparent text-gray-400 hover:text-white"}"}
              >
                Vote
                <%= if length(@active_matchups) > 0 and map_size(@pending_votes) < length(@active_matchups) do %>
                  <span class="ml-1 bg-blue-600 text-white text-xs px-2 py-0.5 rounded-full">
                    <%= length(@active_matchups) - map_size(@pending_votes) %>
                  </span>
                <% end %>
              </button>
            <% end %>
            <button
              phx-click="switch_tab"
              phx-value-tab="leaderboard"
              class={"px-3 sm:px-4 py-3 min-h-[44px] text-sm font-medium border-b-2 transition-colors whitespace-nowrap #{if @tab == "leaderboard", do: "border-blue-500 text-white", else: "border-transparent text-gray-400 hover:text-white"}"}
            >
              Leaderboard
            </button>
            <button
              phx-click="switch_tab"
              phx-value-tab="chat"
              class={"px-3 sm:px-4 py-3 min-h-[44px] text-sm font-medium border-b-2 transition-colors whitespace-nowrap #{if @tab == "chat", do: "border-blue-500 text-white", else: "border-transparent text-gray-400 hover:text-white"}"}
            >
              Chat
            </button>
            <%= if @has_bracket do %>
              <button
                phx-click="switch_tab"
                phx-value-tab="my_bracket"
                class={"px-3 sm:px-4 py-3 min-h-[44px] text-sm font-medium border-b-2 transition-colors whitespace-nowrap #{if @tab == "my_bracket", do: "border-blue-500 text-white", else: "border-transparent text-gray-400 hover:text-white"}"}
              >
                My Bracket
              </button>
            <% end %>
          </nav>
        </div>
      </div>

      <main class="max-w-7xl mx-auto px-4 py-6">
        <%= case @tab do %>
          <% "bracket" -> %>
            <.bracket_tab matchups={@all_matchups} tournament={@tournament} user_bracket={@user_bracket} />
          <% "voting" -> %>
            <.voting_tab
              matchups={@active_matchups}
              current_user={@current_user}
              has_bracket={@has_bracket}
              tournament={@tournament}
              pending_votes={@pending_votes}
              submitted={@submitted}
            />
          <% "leaderboard" -> %>
            <.leaderboard_tab tournament={@tournament} leaderboard={@leaderboard} />
          <% "chat" -> %>
            <.chat_tab
              messages={@messages}
              current_user={@current_user}
              message_input={@message_input}
              tournament={@tournament}
            />
          <% "my_bracket" -> %>
            <.my_bracket_tab
              user_bracket={@user_bracket}
              tournament={@tournament}
              contestants_map={@contestants_map}
              matchups={@all_matchups}
            />
        <% end %>
      </main>
    </div>
    """
  end

  # Bracket Tab - ESPN-style bracket with 4 regions converging to Final Four
  defp bracket_tab(assigns) do
    # For tournaments in registration/draft, show message instead of empty bracket
    if assigns.tournament.status in ["draft", "registration"] do
      assigns = assign(assigns, :status, assigns.tournament.status)
      ~H"""
      <div class="text-center py-12">
        <div class="text-6xl mb-4">🏆</div>
        <h2 class="text-2xl font-bold text-white mb-2">Bracket Coming Soon</h2>
        <p class="text-gray-400 mb-6">
          <%= if @status == "registration" do %>
            The bracket will be revealed when the tournament starts.
            <br/>Fill out your predictions now before it begins!
          <% else %>
            The tournament is still being set up.
          <% end %>
        </p>
        <%= if @status == "registration" do %>
          <a href={"/tournament/#{@tournament.id}/bracket"}
             class="inline-block bg-blue-600 hover:bg-blue-700 text-white px-6 py-3 rounded-lg font-medium transition-colors">
            Fill Out Your Bracket →
          </a>
        <% end %>
      </div>
      """
    else
      # Get user's picks if they have a bracket
      picks = if assigns.user_bracket, do: assigns.user_bracket.picks || %{}, else: %{}
      assigns = assign(assigns, :user_picks, picks)
      bracket_tab_content(assigns)
    end
  end

  defp bracket_tab_content(assigns) do
    tournament = assigns.tournament
    matchups = assigns.matchups

    # Get tournament configuration
    bracket_size = tournament.bracket_size || 64
    region_count = tournament.region_count || 4
    region_names = tournament.region_names || ["East", "West", "South", "Midwest"]
    contestants_per_region = div(bracket_size, region_count)
    matchups_per_region_r1 = div(contestants_per_region, 2)
    regional_rounds = trunc(:math.log2(contestants_per_region))

    # Build matchups map by {region, round, position} for easy lookup
    # Regional matchups use region, Final Four/Championship use nil region
    matchups_map = Map.new(matchups, fn m ->
      key = {String.downcase(m.region || ""), m.round, m.position}
      {key, m}
    end)

    # Final Four and Championship use round 5 and 6 with nil region
    # Round 5 (Final Four): positions 1 and 2
    # Round 6 (Championship): position 1
    ff1_pos = 1  # Final Four game 1
    ff2_pos = 2  # Final Four game 2
    championship_pos = 1  # Championship game

    # Regional winner matchup keys (Round 4, Elite 8)
    # Each region has exactly one Round 4 matchup with position matching the region order
    regional_winner_1 = {String.downcase(Enum.at(region_names, 0)), 4, 1}  # sad at position 1
    regional_winner_2 = {String.downcase(Enum.at(region_names, 1)), 4, 2}  # happy at position 2
    regional_winner_3 = {String.downcase(Enum.at(region_names, 2)), 4, 3}  # South at position 3
    regional_winner_4 = {String.downcase(Enum.at(region_names, 3)), 4, 4}  # Midwest at position 4

    # Build contestants map from preloaded contestants
    contestants = if Ecto.assoc_loaded?(tournament.contestants), do: tournament.contestants, else: []
    contestants_map = Map.new(contestants, fn c -> {c.id, c} end)
    by_region = Enum.group_by(contestants, fn c -> String.downcase(c.region || "") end)

    # Get seed pairs for matchups
    seed_pairs = Tournaments.seeding_pattern(contestants_per_region)

    # Build region data with actual matchup info
    regions_data = region_names
      |> Enum.with_index()
      |> Enum.map(fn {region_name, idx} ->
        offset = idx * matchups_per_region_r1
        region_contestants = Map.get(by_region, String.downcase(region_name), [])
        by_seed = Map.new(region_contestants, fn c -> {c.seed, c} end)

        r1_matchups = seed_pairs
          |> Enum.with_index()
          |> Enum.map(fn {{seed_a, seed_b}, matchup_idx} ->
            %{
              position: offset + matchup_idx + 1,
              contestant_a: Map.get(by_seed, seed_a),
              contestant_b: Map.get(by_seed, seed_b)
            }
          end)

        {region_name, %{matchups: r1_matchups, offset: offset}}
      end)
      |> Map.new()

    assigns = assigns
      |> assign(:region_names, region_names)
      |> assign(:region_count, region_count)
      |> assign(:regional_rounds, regional_rounds)
      |> assign(:matchups_per_region_r1, matchups_per_region_r1)
      |> assign(:regions_data, regions_data)
      |> assign(:matchups_map, matchups_map)
      |> assign(:contestants_map, contestants_map)
      |> assign(:regional_winner_1, regional_winner_1)
      |> assign(:regional_winner_2, regional_winner_2)
      |> assign(:regional_winner_3, regional_winner_3)
      |> assign(:regional_winner_4, regional_winner_4)
      |> assign(:ff1_pos, ff1_pos)
      |> assign(:ff2_pos, ff2_pos)
      |> assign(:championship_pos, championship_pos)
      |> assign(:bracket_size, bracket_size)

    ~H"""
    <div class="space-y-4">
      <div class="text-center mb-4">
        <h2 class="text-xl md:text-2xl font-bold text-white">Tournament Bracket</h2>
        <p class="text-gray-400 text-sm">
          <%= if @tournament.status == "active" do %>
            Voting: <%= Tournaments.get_current_voting_phase_name(@tournament) %>
          <% else %>
            <%= status_label(@tournament.status) %>
          <% end %>
        </p>
      </div>

      <!-- CSS-based Results Bracket Layout -->
      <div class="overflow-x-auto pb-4">
        <div class="min-w-[1400px]">

          <!-- Top Half: First region (left) and Second region (right) -->
          <div class="flex justify-between">
            <!-- FIRST REGION - flows left to right -->
            <div class="flex-1">
              <div class="text-center mb-3">
                <span class="text-green-400 font-bold text-lg uppercase tracking-wider"><%= Enum.at(@region_names, 0) %></span>
              </div>
              <.results_region_left
                region_name={Enum.at(@region_names, 0)}
                region_data={@regions_data[Enum.at(@region_names, 0)]}
                matchups_map={@matchups_map}
                contestants_map={@contestants_map}
                regional_rounds={@regional_rounds}
                matchups_per_region_r1={@matchups_per_region_r1}
                bracket_size={@bracket_size}
              />
            </div>

            <!-- SECOND REGION - flows right to left -->
            <div class="flex-1">
              <div class="text-center mb-3">
                <span class="text-green-400 font-bold text-lg uppercase tracking-wider"><%= Enum.at(@region_names, 1) %></span>
              </div>
              <.results_region_right
                region_name={Enum.at(@region_names, 1)}
                region_data={@regions_data[Enum.at(@region_names, 1)]}
                matchups_map={@matchups_map}
                contestants_map={@contestants_map}
                regional_rounds={@regional_rounds}
                matchups_per_region_r1={@matchups_per_region_r1}
                bracket_size={@bracket_size}
              />
            </div>
          </div>

          <!-- Center Section: Final Four + Championship -->
          <div class="flex justify-between items-start my-6">
            <!-- Left Final Four -->
            <div class="flex-1 flex justify-end">
              <div class="w-48">
                <.results_final_four_slot
                  position={@ff1_pos}
                  source_a={@regional_winner_1}
                  source_b={@regional_winner_3}
                  placeholder_a={"#{Enum.at(@region_names, 0)} Winner"}
                  placeholder_b={"#{Enum.at(@region_names, 2)} Winner"}
                  matchups_map={@matchups_map}
                  contestants_map={@contestants_map}
                />
              </div>
            </div>

            <!-- Championship (center) -->
            <div class="w-56 mx-4">
              <.results_championship_slot
                matchups_map={@matchups_map}
                contestants_map={@contestants_map}
                ff1_pos={@ff1_pos}
                ff2_pos={@ff2_pos}
                championship_pos={@championship_pos}
              />
            </div>

            <!-- Right Final Four -->
            <div class="flex-1 flex justify-start">
              <%= if @region_count >= 4 do %>
                <div class="w-48">
                  <.results_final_four_slot
                    position={@ff2_pos}
                    source_a={@regional_winner_2}
                    source_b={@regional_winner_4}
                    placeholder_a={"#{Enum.at(@region_names, 1)} Winner"}
                    placeholder_b={"#{Enum.at(@region_names, 3)} Winner"}
                    matchups_map={@matchups_map}
                    contestants_map={@contestants_map}
                  />
                </div>
              <% end %>
            </div>
          </div>

          <%= if @region_count >= 4 do %>
            <!-- Bottom Half: Third region (left) and Fourth region (right) -->
            <div class="flex justify-between">
              <!-- THIRD REGION - flows left to right -->
              <div class="flex-1">
                <div class="text-center mb-3">
                  <span class="text-green-400 font-bold text-lg uppercase tracking-wider"><%= Enum.at(@region_names, 2) %></span>
                </div>
                <.results_region_left
                  region_name={Enum.at(@region_names, 2)}
                  region_data={@regions_data[Enum.at(@region_names, 2)]}
                  matchups_map={@matchups_map}
                  contestants_map={@contestants_map}
                  regional_rounds={@regional_rounds}
                  matchups_per_region_r1={@matchups_per_region_r1}
                  bracket_size={@bracket_size}
                />
              </div>

              <!-- FOURTH REGION - flows right to left -->
              <div class="flex-1">
                <div class="text-center mb-3">
                  <span class="text-green-400 font-bold text-lg uppercase tracking-wider"><%= Enum.at(@region_names, 3) %></span>
                </div>
                <.results_region_right
                  region_name={Enum.at(@region_names, 3)}
                  region_data={@regions_data[Enum.at(@region_names, 3)]}
                  matchups_map={@matchups_map}
                  contestants_map={@contestants_map}
                  regional_rounds={@regional_rounds}
                  matchups_per_region_r1={@matchups_per_region_r1}
                  bracket_size={@bracket_size}
                />
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Get matchups for a specific region, grouped by round
  defp get_region_matchups(matchups, region) do
    matchups
    |> Enum.filter(fn m -> m.region == region end)
    |> Enum.group_by(& &1.round)
    |> Enum.map(fn {round, ms} -> {round, Enum.sort_by(ms, & &1.position)} end)
    |> Enum.into(%{})
  end

  # Left-side region bracket (East, South) - flows left to right
  # Dynamically renders based on region_rounds (3 for 32-bracket, 4 for 64-bracket)
  defp region_bracket_left(assigns) do
    # Calculate container height based on number of first-round matchups
    # For 32-bracket: 4 matchups * 80px = 320px
    # For 64-bracket: 8 matchups * 80px = 640px
    first_round_count = length(Map.get(assigns.matchups, 1, []))
    container_height = max(first_round_count * 80, 320)

    assigns = assigns
      |> Map.put(:container_height, container_height)

    ~H"""
    <div class="flex items-center">
      <%= for round <- 1..@region_rounds do %>
        <%= if round > 1 do %>
          <!-- Connector column between rounds -->
          <div class="w-4"></div>
        <% end %>

        <div class={if round == @region_rounds, do: "flex flex-col justify-center", else: "flex flex-col justify-around"} style={"min-height: #{@container_height}px;"}>
          <%= for {matchup, idx} <- Enum.with_index(Map.get(@matchups, round, [])) do %>
            <div class="relative">
              <!-- Connector line from previous round (for rounds 2+) -->
              <%= if round > 1 do %>
                <div class="absolute left-0 top-1/2 w-4 h-px bg-gray-600 -translate-x-full"></div>
              <% end %>

              <.bracket_matchup_box matchup={matchup} size={if round < @region_rounds - 1, do: "small", else: "normal"} user_picks={@user_picks} />

              <%= if round < @region_rounds do %>
                <!-- Horizontal line to connector -->
                <div class="absolute right-0 top-1/2 w-4 h-px bg-gray-600 translate-x-full"></div>
                <!-- Vertical connector: pairs connect -->
                <% matchups_in_round = length(Map.get(@matchups, round, []))
                   connector_height = div(@container_height, matchups_in_round * 2) %>
                <%= if rem(idx, 2) == 0 do %>
                  <!-- Top of pair - line goes down -->
                  <div class="absolute right-0 top-1/2 w-px bg-gray-600 translate-x-[calc(100%+16px)]" style={"height: #{connector_height}px;"}></div>
                <% else %>
                  <!-- Bottom of pair - line goes up -->
                  <div class="absolute right-0 bottom-1/2 w-px bg-gray-600 translate-x-[calc(100%+16px)]" style={"height: #{connector_height}px;"}></div>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # Right-side region bracket (West, Midwest) - flows right to left
  # Dynamically renders based on region_rounds (3 for 32-bracket, 4 for 64-bracket)
  defp region_bracket_right(assigns) do
    # Calculate container height based on number of first-round matchups
    first_round_count = length(Map.get(assigns.matchups, 1, []))
    container_height = max(first_round_count * 80, 320)

    assigns = assigns
      |> Map.put(:container_height, container_height)

    ~H"""
    <div class="flex items-center justify-end">
      <%= for round <- @region_rounds..1 do %>
        <%= if round > 1 do %>
          <!-- Connector column between rounds -->
          <div class="w-4"></div>
        <% end %>

        <div class={if round == @region_rounds, do: "flex flex-col justify-center", else: "flex flex-col justify-around"} style={"min-height: #{@container_height}px;"}>
          <%= for {matchup, idx} <- Enum.with_index(Map.get(@matchups, round, [])) do %>
            <div class="relative">
              <%= if round < @region_rounds do %>
                <!-- Horizontal line to connector (toward next round) -->
                <div class="absolute left-0 top-1/2 w-4 h-px bg-gray-600 -translate-x-full"></div>
                <!-- Vertical connector for pairs -->
                <% matchups_in_round = length(Map.get(@matchups, round, []))
                   connector_height = div(@container_height, matchups_in_round * 2) %>
                <%= if rem(idx, 2) == 0 do %>
                  <div class="absolute left-0 top-1/2 w-px bg-gray-600 -translate-x-[16px]" style={"height: #{connector_height}px;"}></div>
                <% else %>
                  <div class="absolute left-0 bottom-1/2 w-px bg-gray-600 -translate-x-[16px]" style={"height: #{connector_height}px;"}></div>
                <% end %>
              <% end %>

              <.bracket_matchup_box matchup={matchup} size={if round < @region_rounds - 1, do: "small", else: "normal"} user_picks={@user_picks} />

              <!-- Connector line to next round (for rounds 2+, connects to the right) -->
              <%= if round > 1 do %>
                <div class="absolute right-0 top-1/2 w-4 h-px bg-gray-600 translate-x-full"></div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # Individual matchup box component
  defp bracket_matchup_box(assigns) do
    assigns = assigns
      |> Map.put_new(:size, "normal")
      |> Map.put_new(:highlight, false)
      |> Map.put_new(:user_picks, %{})

    round = assigns.matchup.round
    position = assigns.matchup.position

    # For rounds 2+, check if each contestant was correctly picked in the previous round
    # The indicator shows whether the user correctly predicted this contestant would advance
    {c1_pick_status, c2_pick_status} = if round > 1 and assigns.matchup.contestant_1_id do
      # Calculate the two source positions from previous round that feed into this matchup
      # Each matchup in round N is fed by 2 consecutive matchups in round N-1
      source_pos_1 = (position - 1) * 2 + 1  # First feeder matchup
      source_pos_2 = (position - 1) * 2 + 2  # Second feeder matchup

      source_bracket_pos_1 = matchup_to_bracket_position(round - 1, source_pos_1)
      source_bracket_pos_2 = matchup_to_bracket_position(round - 1, source_pos_2)

      # Get user's picks for those source positions
      user_pick_1 = Map.get(assigns.user_picks, to_string(source_bracket_pos_1))
      user_pick_2 = Map.get(assigns.user_picks, to_string(source_bracket_pos_2))

      # Contestant 1 came from source_pos_1, Contestant 2 came from source_pos_2
      c1_status = cond do
        is_nil(assigns.matchup.contestant_1_id) -> :pending
        is_nil(user_pick_1) -> :no_pick
        to_string(user_pick_1) == to_string(assigns.matchup.contestant_1_id) -> :correct
        true -> :incorrect
      end

      c2_status = cond do
        is_nil(assigns.matchup.contestant_2_id) -> :pending
        is_nil(user_pick_2) -> :no_pick
        to_string(user_pick_2) == to_string(assigns.matchup.contestant_2_id) -> :correct
        true -> :incorrect
      end

      {c1_status, c2_status}
    else
      # Round 1 - no previous picks to check
      {:no_pick, :no_pick}
    end

    # Overall matchup border based on both contestant statuses
    has_correct = c1_pick_status == :correct or c2_pick_status == :correct
    has_incorrect = c1_pick_status == :incorrect or c2_pick_status == :incorrect

    assigns = assigns
      |> assign(:c1_pick_status, c1_pick_status)
      |> assign(:c2_pick_status, c2_pick_status)
      |> assign(:has_correct, has_correct)
      |> assign(:has_incorrect, has_incorrect)

    ~H"""
    <div class={[
      "bg-gray-800 rounded overflow-hidden",
      @size == "small" && "w-36",
      @size == "normal" && "w-44",
      @highlight && "border border-yellow-500 ring-1 ring-yellow-500/50"
    ]}>
      <!-- Contestant 1 -->
      <div class={[
        "flex items-center px-2 py-1 border-t border-l border-r rounded-t",
        @c1_pick_status == :correct && "bg-green-900/40 border-green-600",
        @c1_pick_status == :incorrect && "bg-red-900/40 border-red-600",
        @c1_pick_status in [:pending, :no_pick] && "border-gray-700",
        !@matchup.contestant_1 && "justify-center"
      ]}>
        <%= if @matchup.contestant_1 do %>
          <span class={[
            "text-xs font-mono w-5",
            @c1_pick_status == :correct && "text-green-400",
            @c1_pick_status == :incorrect && "text-red-400",
            @c1_pick_status in [:pending, :no_pick] && "text-gray-500"
          ]}>
            <%= @matchup.contestant_1.seed %>
          </span>
        <% end %>
        <span class={[
          "text-xs truncate flex-1",
          @c1_pick_status == :correct && "text-green-400 font-semibold",
          @c1_pick_status == :incorrect && "text-red-400",
          @c1_pick_status in [:pending, :no_pick] && "text-gray-300",
          !@matchup.contestant_1 && "text-center"
        ]}>
          <%= if @matchup.contestant_1, do: @matchup.contestant_1.name, else: "TBD" %>
        </span>
        <%= cond do %>
          <% @c1_pick_status == :correct -> %>
            <span class="text-green-400 text-xs">✓</span>
          <% @c1_pick_status == :incorrect -> %>
            <span class="text-red-400 text-xs">✗</span>
          <% true -> %>
        <% end %>
      </div>
      <!-- Middle divider - always gray -->
      <div class="border-t border-gray-700"></div>
      <!-- Contestant 2 -->
      <div class={[
        "flex items-center px-2 py-1 border-b border-l border-r rounded-b",
        @c2_pick_status == :correct && "bg-green-900/40 border-green-600",
        @c2_pick_status == :incorrect && "bg-red-900/40 border-red-600",
        @c2_pick_status in [:pending, :no_pick] && "border-gray-700",
        !@matchup.contestant_2 && "justify-center"
      ]}>
        <%= if @matchup.contestant_2 do %>
          <span class={[
            "text-xs font-mono w-5",
            @c2_pick_status == :correct && "text-green-400",
            @c2_pick_status == :incorrect && "text-red-400",
            @c2_pick_status in [:pending, :no_pick] && "text-gray-500"
          ]}>
            <%= @matchup.contestant_2.seed %>
          </span>
        <% end %>
        <span class={[
          "text-xs truncate flex-1",
          @c2_pick_status == :correct && "text-green-400 font-semibold",
          @c2_pick_status == :incorrect && "text-red-400",
          @c2_pick_status in [:pending, :no_pick] && "text-gray-300",
          !@matchup.contestant_2 && "text-center"
        ]}>
          <%= if @matchup.contestant_2, do: @matchup.contestant_2.name, else: "TBD" %>
        </span>
        <%= cond do %>
          <% @c2_pick_status == :correct -> %>
            <span class="text-green-400 text-xs">✓</span>
          <% @c2_pick_status == :incorrect -> %>
            <span class="text-red-400 text-xs">✗</span>
          <% true -> %>
        <% end %>
      </div>
    </div>
    """
  end

  # Convert matchup round/position to bracket position (1-63)
  defp matchup_to_bracket_position(round, position) do
    base = case round do
      1 -> 0
      2 -> 32
      3 -> 48
      4 -> 56
      5 -> 60
      6 -> 62
    end
    base + position
  end

  # Voting Tab
  defp voting_tab(assigns) do
    votes_cast = map_size(assigns.pending_votes)
    total_matchups = length(assigns.matchups)
    all_voted = votes_cast == total_matchups && total_matchups > 0

    assigns = assigns
      |> assign(:votes_cast, votes_cast)
      |> assign(:total_matchups, total_matchups)
      |> assign(:all_voted, all_voted)

    ~H"""
    <div class="space-y-6">
      <%= if !@has_bracket do %>
        <div class="bg-yellow-900/20 border border-yellow-700 rounded-lg p-6 text-center">
          <p class="text-yellow-400 mb-4">You need to submit a bracket before you can vote!</p>
          <a href={"/tournament/#{@tournament.id}/bracket"} class="bg-blue-600 hover:bg-blue-700 text-white px-6 py-2 rounded">
            Fill Out Bracket
          </a>
        </div>
      <% else %>
        <%= if Enum.empty?(@matchups) do %>
          <div class="bg-gray-800 rounded-lg p-8 text-center border border-gray-700">
            <p class="text-gray-400">No matchups are currently open for voting.</p>
          </div>
        <% else %>
          <!-- Success Banner -->
          <%= if @submitted do %>
            <div class="bg-green-900/30 border border-green-600 rounded-lg p-4 mb-6 flex items-center justify-between">
              <div class="flex items-center">
                <svg class="w-6 h-6 text-green-400 mr-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"></path>
                </svg>
                <span class="text-green-400 font-medium">Your votes have been submitted!</span>
              </div>
              <span class="text-green-400/70 text-sm">You can change your votes until voting ends</span>
            </div>
          <% end %>

          <div class="text-center mb-4">
            <h2 class="text-xl font-bold text-white">
              Vote: <%= Tournaments.get_current_voting_phase_name(@tournament) %>
            </h2>
            <p class="text-gray-400 text-sm">Click on the contestant you think should win</p>
          </div>

          <!-- Round deadline banner -->
          <%= if hd(@matchups).voting_ends_at do %>
            <% voting_ends_at = hd(@matchups).voting_ends_at %>
            <% diff = DateTime.diff(voting_ends_at, DateTime.utc_now()) %>
            <div class="bg-gray-800/50 border border-gray-700 rounded-lg p-3 mb-4 text-center">
              <span class="text-gray-400 text-sm">Voting closes at </span>
              <span
                id="voting-deadline"
                phx-hook="LocalTime"
                data-utc={DateTime.to_iso8601(voting_ends_at)}
                data-format="datetime"
                class="text-white font-medium"
              ><%= Calendar.strftime(voting_ends_at, "%b %d at %I:%M %p") %> UTC</span>
              <%= if diff > 0 do %>
                <span class="text-gray-500 text-sm ml-2">(<%= format_countdown(diff) %> remaining)</span>
              <% else %>
                <span class="text-red-400 text-sm ml-2">(Voting ended)</span>
              <% end %>
            </div>
          <% end %>

          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <%= for matchup <- @matchups do %>
              <.voting_card matchup={matchup} current_user={@current_user} pending_vote={Map.get(@pending_votes, to_string(matchup.id))} />
            <% end %>
          </div>

          <!-- Submit Button -->
          <div class="mt-8 pt-6 border-t border-gray-700">
            <div class="flex flex-col items-center space-y-4">
              <div class="text-center">
                <span class={[
                  "text-lg font-semibold",
                  @all_voted && "text-green-400",
                  !@all_voted && "text-gray-400"
                ]}>
                  <%= @votes_cast %>/<%= @total_matchups %> matchups selected
                </span>
                <%= if @all_voted do %>
                  <span class="ml-2 text-green-400">✓</span>
                <% end %>
              </div>
              <button
                phx-click="submit_votes"
                phx-disable-with="Submitting..."
                disabled={@votes_cast == 0}
                class={[
                  "px-8 py-3 rounded-lg font-semibold text-lg transition-all",
                  @votes_cast > 0 && "bg-blue-600 hover:bg-blue-700 text-white cursor-pointer",
                  @votes_cast == 0 && "bg-gray-700 text-gray-500 cursor-not-allowed"
                ]}
              >
                Submit Votes
              </button>
              <p class="text-gray-500 text-sm">
                You can change your votes until voting ends
              </p>
            </div>
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp voting_card(assigns) do
    c1_votes = Map.get(assigns.matchup.vote_counts || %{}, assigns.matchup.contestant_1_id, 0)
    c2_votes = Map.get(assigns.matchup.vote_counts || %{}, assigns.matchup.contestant_2_id, 0)
    total = c1_votes + c2_votes
    c1_pct = if total > 0, do: round(c1_votes / total * 100), else: 50
    c2_pct = if total > 0, do: round(c2_votes / total * 100), else: 50

    # Use pending_vote for highlighting (local selection before submit)
    selected = assigns.pending_vote

    # Check if user has already voted on this matchup (don't show percentages until they vote)
    # Use Map.get to safely handle anonymous users where user_vote key doesn't exist
    has_voted = Map.get(assigns.matchup, :user_vote) != nil

    time_remaining = if assigns.matchup.voting_ends_at do
      diff = DateTime.diff(assigns.matchup.voting_ends_at, DateTime.utc_now())
      if diff > 0, do: format_countdown(diff), else: "Voting ended"
    end

    assigns =
      assigns
      |> assign(:c1_votes, c1_votes)
      |> assign(:c2_votes, c2_votes)
      |> assign(:c1_pct, c1_pct)
      |> assign(:c2_pct, c2_pct)
      |> assign(:total, total)
      |> assign(:selected, selected)
      |> assign(:has_voted, has_voted)
      |> assign(:time_remaining, time_remaining)

    ~H"""
    <div class="bg-gray-800 rounded-lg border border-gray-700 overflow-hidden">
      <!-- Header with region and timer -->
      <div class="bg-gray-750 px-3 py-2 flex justify-between items-center border-b border-gray-700">
        <span class="text-gray-400 text-xs"><%= @matchup.region || "Final Four+" %></span>
        <span class="text-gray-500 text-xs"><%= @time_remaining %></span>
      </div>

      <!-- Contestants -->
      <div class="p-3 space-y-2">
        <!-- Contestant 1 -->
        <button
          phx-click="select_vote"
          phx-value-matchup={@matchup.id}
          phx-value-contestant={@matchup.contestant_1_id}
          class={[
            "w-full text-left p-3 rounded transition-all duration-200",
            is_selected(@selected, @matchup.contestant_1_id) && "bg-blue-600 ring-2 ring-blue-400 scale-[1.02]",
            !is_selected(@selected, @matchup.contestant_1_id) && "bg-gray-700 hover:bg-gray-600"
          ]}
        >
          <div class="flex justify-between items-center">
            <span class="text-white text-sm">
              <span class="text-gray-400"><%= @matchup.contestant_1.seed %>.</span>
              <%= @matchup.contestant_1.name %>
            </span>
            <%= if is_selected(@selected, @matchup.contestant_1_id) do %>
              <span class="text-white font-bold text-xs">SELECTED</span>
            <% end %>
          </div>
        </button>

        <!-- Contestant 2 -->
        <button
          phx-click="select_vote"
          phx-value-matchup={@matchup.id}
          phx-value-contestant={@matchup.contestant_2_id}
          class={[
            "w-full text-left p-3 rounded transition-all duration-200",
            is_selected(@selected, @matchup.contestant_2_id) && "bg-blue-600 ring-2 ring-blue-400 scale-[1.02]",
            !is_selected(@selected, @matchup.contestant_2_id) && "bg-gray-700 hover:bg-gray-600"
          ]}
        >
          <div class="flex justify-between items-center">
            <span class="text-white text-sm">
              <span class="text-gray-400"><%= @matchup.contestant_2.seed %>.</span>
              <%= @matchup.contestant_2.name %>
            </span>
            <%= if is_selected(@selected, @matchup.contestant_2_id) do %>
              <span class="text-white font-bold text-xs">SELECTED</span>
            <% end %>
          </div>
        </button>
      </div>
    </div>
    """
  end

  # Leaderboard Tab
  defp leaderboard_tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="text-center mb-4">
        <h2 class="text-xl font-bold text-white">Leaderboard</h2>
        <p class="text-gray-400 text-sm">Top bracket predictions</p>
      </div>

      <%= if Enum.empty?(@leaderboard) do %>
        <div class="bg-gray-800 rounded-lg p-8 text-center border border-gray-700">
          <p class="text-gray-400">No brackets submitted yet.</p>
        </div>
      <% else %>
        <div class="bg-gray-800 rounded-lg border border-gray-700 overflow-x-auto">
          <table class="w-full min-w-[320px]">
            <thead>
              <tr class="border-b border-gray-700 bg-gray-750">
                <th class="text-left text-gray-400 text-xs sm:text-sm font-medium px-2 sm:px-4 py-2 sm:py-3 w-12 sm:w-16">Rank</th>
                <th class="text-left text-gray-400 text-xs sm:text-sm font-medium px-2 sm:px-4 py-2 sm:py-3">Player</th>
                <th class="text-right text-gray-400 text-xs sm:text-sm font-medium px-2 sm:px-4 py-2 sm:py-3">Pts</th>
                <th class="text-right text-gray-400 text-xs sm:text-sm font-medium px-2 sm:px-4 py-2 sm:py-3">Correct</th>
              </tr>
            </thead>
            <tbody>
              <%= for entry <- @leaderboard do %>
                <tr class="border-b border-gray-700 last:border-0 hover:bg-gray-750">
                  <td class="px-2 sm:px-4 py-2 sm:py-3">
                    <span class={"font-bold text-sm sm:text-base #{rank_color(entry.rank)}"}><%= entry.rank %></span>
                  </td>
                  <td class="px-2 sm:px-4 py-2 sm:py-3 text-white text-sm sm:text-base truncate max-w-[120px] sm:max-w-none">
                    <%= entry.user.display_name || entry.user.email %>
                  </td>
                  <td class="px-2 sm:px-4 py-2 sm:py-3 text-right text-blue-400 font-bold text-sm sm:text-base">
                    <%= entry.total_score %>
                  </td>
                  <td class="px-2 sm:px-4 py-2 sm:py-3 text-right text-gray-400 text-sm sm:text-base">
                    <%= entry.correct_picks %>/63
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
    """
  end

  # Chat Tab
  defp chat_tab(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto">
      <div class="bg-gray-800 rounded-lg border border-gray-700 overflow-hidden">
        <!-- Chat Header -->
        <div class="bg-gray-750 px-4 py-3 border-b border-gray-700">
          <h3 class="text-white font-medium">Tournament Chat</h3>
        </div>

        <!-- Messages -->
        <div class="h-96 overflow-y-auto p-4 space-y-3" id="chat-messages" phx-hook="ScrollToBottom">
          <%= if Enum.empty?(@messages) do %>
            <p class="text-gray-500 text-center text-sm">No messages yet. Start the conversation!</p>
          <% else %>
            <%= for message <- Enum.reverse(@messages) do %>
              <div class="flex space-x-3">
                <div class="flex-1">
                  <div class="flex items-baseline space-x-2">
                    <span class="text-blue-400 text-sm font-medium">
                      <%= message.user.display_name || message.user.email %>
                    </span>
                    <span
                      id={"chat-time-#{message.id}"}
                      phx-hook="LocalTime"
                      data-utc={DateTime.to_iso8601(message.inserted_at)}
                      data-format="time"
                      class="text-gray-600 text-xs"
                    ><%= format_time(message.inserted_at) %></span>
                  </div>
                  <p class="text-gray-300 text-sm mt-1"><%= message.content %></p>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>

        <!-- Input -->
        <%= if @current_user do %>
          <form phx-submit="send_message" class="border-t border-gray-700 p-3">
            <div class="flex space-x-2">
              <input
                type="text"
                name="content"
                value={@message_input}
                placeholder="Type a message..."
                maxlength="500"
                class="flex-1 bg-gray-700 border-gray-600 text-white rounded px-3 py-2 text-sm focus:ring-blue-500 focus:border-blue-500"
                autocomplete="off"
              />
              <button
                type="submit"
                class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded text-sm"
              >
                Send
              </button>
            </div>
          </form>
        <% else %>
          <div class="border-t border-gray-700 p-4 text-center">
            <a href="/auth/signin" class="text-blue-400 hover:text-blue-300 text-sm">
              Sign in to chat
            </a>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # My Bracket Tab - Shows user's submitted bracket predictions in visual bracket format
  # Highlights correct picks (green) and incorrect picks (red) based on actual results
  defp my_bracket_tab(assigns) do
    picks = assigns.user_bracket.picks || %{}
    tournament = assigns.tournament
    matchups = assigns.matchups

    # Build matchups_map by {region, round, position} for result lookup
    matchups_map = Map.new(matchups, fn m ->
      key = {String.downcase(m.region || ""), m.round, m.position}
      {key, m}
    end)

    # Build eliminated_map: contestant_id -> round_eliminated
    # A contestant is eliminated when they lose a matchup (are in matchup but not winner)
    eliminated_map = matchups
      |> Enum.filter(fn m -> m.winner_id != nil end)
      |> Enum.flat_map(fn m ->
        loser_id = cond do
          m.winner_id == m.contestant_1_id -> m.contestant_2_id
          m.winner_id == m.contestant_2_id -> m.contestant_1_id
          true -> nil
        end
        if loser_id, do: [{loser_id, m.round}], else: []
      end)
      |> Map.new()

    # Get tournament configuration
    bracket_size = tournament.bracket_size || 64
    region_count = tournament.region_count || 4
    region_names = tournament.region_names || ["East", "West", "South", "Midwest"]
    contestants_per_region = div(bracket_size, region_count)
    matchups_per_region_r1 = div(contestants_per_region, 2)
    regional_rounds = trunc(:math.log2(contestants_per_region))

    # Final Four positions (round 5, positions 1 and 2)
    ff1_pos = 1
    ff2_pos = 2
    championship_pos = 1

    # Regional winner matchup keys (Round 4, Elite 8)
    regional_winner_1 = {String.downcase(Enum.at(region_names, 0)), 4, 1}
    regional_winner_2 = {String.downcase(Enum.at(region_names, 1)), 4, 2}
    regional_winner_3 = {String.downcase(Enum.at(region_names, 2)), 4, 3}
    regional_winner_4 = {String.downcase(Enum.at(region_names, 3)), 4, 4}

    # Build proper regions_data with actual contestant matchups (exactly like bracket_editor)
    # Build contestants map from preloaded contestants
    contestants = if Ecto.assoc_loaded?(tournament.contestants), do: tournament.contestants, else: []
    contestants_map = Map.new(contestants, fn c -> {c.id, c} end)
    by_region = Enum.group_by(contestants, fn c -> String.downcase(c.region || "") end)

    # Get seed pairs for matchups
    seed_pairs = Tournaments.seeding_pattern(contestants_per_region)

    # Build region data with actual matchup info
    regions_data = region_names
      |> Enum.with_index()
      |> Enum.map(fn {region_name, idx} ->
        offset = idx * matchups_per_region_r1
        region_contestants = Map.get(by_region, String.downcase(region_name), [])
        by_seed = Map.new(region_contestants, fn c -> {c.seed, c} end)

        matchups = seed_pairs
          |> Enum.with_index()
          |> Enum.map(fn {{seed_a, seed_b}, matchup_idx} ->
            %{
              position: offset + matchup_idx + 1,
              contestant_a: Map.get(by_seed, seed_a),
              contestant_b: Map.get(by_seed, seed_b)
            }
          end)

        {region_name, %{matchups: matchups, offset: offset}}
      end)
      |> Map.new()

    assigns = assigns
      |> assign(:picks, picks)
      |> assign(:region_names, region_names)
      |> assign(:region_count, region_count)
      |> assign(:regional_rounds, regional_rounds)
      |> assign(:matchups_per_region_r1, matchups_per_region_r1)
      |> assign(:regions_data, regions_data)
      |> assign(:contestants_map, contestants_map)
      |> assign(:matchups_map, matchups_map)
      |> assign(:eliminated_map, eliminated_map)
      |> assign(:regional_winner_1, regional_winner_1)
      |> assign(:regional_winner_2, regional_winner_2)
      |> assign(:regional_winner_3, regional_winner_3)
      |> assign(:regional_winner_4, regional_winner_4)
      |> assign(:ff1_pos, ff1_pos)
      |> assign(:ff2_pos, ff2_pos)
      |> assign(:championship_pos, championship_pos)
      |> assign(:bracket_size, bracket_size)

    ~H"""
    <div class="space-y-4">
      <!-- Header -->
      <div class="text-center mb-4">
        <h2 class="text-xl md:text-2xl font-bold text-white">Your Bracket Predictions</h2>
        <p class="text-gray-400 text-sm">
          Submitted on
          <span
            id="my-bracket-submitted-time"
            phx-hook="LocalTime"
            data-utc={DateTime.to_iso8601(@user_bracket.submitted_at)}
            data-format="datetime"
          ><%= format_bracket_date(@user_bracket.submitted_at) %></span>
        </p>
      </div>

      <!-- ESPN-Style Bracket Layout -->
      <div class="overflow-x-auto pb-4">
        <div class="min-w-[1400px]">

          <!-- Top Half: First region (left) and Second region (right) -->
          <div class="flex justify-between">
            <!-- FIRST REGION - flows left to right -->
            <div class="flex-1">
              <div class="text-center mb-3">
                <span class="text-blue-400 font-bold text-lg uppercase tracking-wider"><%= Enum.at(@region_names, 0) %></span>
              </div>
              <.my_bracket_region_left
                region_data={@regions_data[Enum.at(@region_names, 0)]}
                region_name={Enum.at(@region_names, 0)}
                picks={@picks}
                contestants_map={@contestants_map}
                matchups_map={@matchups_map}
                eliminated_map={@eliminated_map}
                regional_rounds={@regional_rounds}
                matchups_per_region_r1={@matchups_per_region_r1}
                bracket_size={@bracket_size}
              />
            </div>

            <!-- SECOND REGION - flows right to left -->
            <div class="flex-1">
              <div class="text-center mb-3">
                <span class="text-blue-400 font-bold text-lg uppercase tracking-wider"><%= Enum.at(@region_names, 1) %></span>
              </div>
              <.my_bracket_region_right
                region_data={@regions_data[Enum.at(@region_names, 1)]}
                region_name={Enum.at(@region_names, 1)}
                picks={@picks}
                contestants_map={@contestants_map}
                matchups_map={@matchups_map}
                eliminated_map={@eliminated_map}
                regional_rounds={@regional_rounds}
                matchups_per_region_r1={@matchups_per_region_r1}
                bracket_size={@bracket_size}
              />
            </div>
          </div>

          <!-- Center Section: Final Four + Championship -->
          <div class="flex justify-between items-start my-6">
            <!-- Left Final Four (East vs South) -->
            <div class="flex-1 flex justify-end">
              <div class="w-48">
                <.my_bracket_final_four_slot
                  position={@ff1_pos}
                  source_a={@regional_winner_1}
                  source_b={@regional_winner_3}
                  placeholder_a={"#{Enum.at(@region_names, 0)} Winner"}
                  placeholder_b={"#{Enum.at(@region_names, 2)} Winner"}
                  picks={@picks}
                  contestants_map={@contestants_map}
                  matchups_map={@matchups_map}
                  eliminated_map={@eliminated_map}
                />
              </div>
            </div>

            <!-- Championship (center) -->
            <div class="w-56 mx-4">
              <.my_bracket_championship_slot
                picks={@picks}
                contestants_map={@contestants_map}
                matchups_map={@matchups_map}
                eliminated_map={@eliminated_map}
                ff1_pos={@ff1_pos}
                ff2_pos={@ff2_pos}
                championship_pos={@championship_pos}
              />
            </div>

            <!-- Right Final Four (West vs Midwest) -->
            <div class="flex-1 flex justify-start">
              <%= if @region_count >= 4 do %>
                <div class="w-48">
                  <.my_bracket_final_four_slot
                    position={@ff2_pos}
                    source_a={@regional_winner_2}
                    source_b={@regional_winner_4}
                    placeholder_a={"#{Enum.at(@region_names, 1)} Winner"}
                    placeholder_b={"#{Enum.at(@region_names, 3)} Winner"}
                    picks={@picks}
                    contestants_map={@contestants_map}
                    matchups_map={@matchups_map}
                    eliminated_map={@eliminated_map}
                  />
                </div>
              <% end %>
            </div>
          </div>

          <%= if @region_count >= 4 do %>
            <!-- Bottom Half: Third region (left) and Fourth region (right) -->
            <div class="flex justify-between">
              <!-- THIRD REGION - flows left to right -->
              <div class="flex-1">
                <div class="text-center mb-3">
                  <span class="text-blue-400 font-bold text-lg uppercase tracking-wider"><%= Enum.at(@region_names, 2) %></span>
                </div>
                <.my_bracket_region_left
                  region_data={@regions_data[Enum.at(@region_names, 2)]}
                  region_name={Enum.at(@region_names, 2)}
                  picks={@picks}
                  contestants_map={@contestants_map}
                  matchups_map={@matchups_map}
                  eliminated_map={@eliminated_map}
                  regional_rounds={@regional_rounds}
                  matchups_per_region_r1={@matchups_per_region_r1}
                  bracket_size={@bracket_size}
                />
              </div>

              <!-- FOURTH REGION - flows right to left -->
              <div class="flex-1">
                <div class="text-center mb-3">
                  <span class="text-blue-400 font-bold text-lg uppercase tracking-wider"><%= Enum.at(@region_names, 3) %></span>
                </div>
                <.my_bracket_region_right
                  region_data={@regions_data[Enum.at(@region_names, 3)]}
                  region_name={Enum.at(@region_names, 3)}
                  picks={@picks}
                  contestants_map={@contestants_map}
                  matchups_map={@matchups_map}
                  eliminated_map={@eliminated_map}
                  regional_rounds={@regional_rounds}
                  matchups_per_region_r1={@matchups_per_region_r1}
                  bracket_size={@bracket_size}
                />
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Left-side region bracket for My Bracket tab (read-only)
  # Uses exact same structure as bracket_editor_live.ex
  defp my_bracket_region_left(assigns) do
    offset = assigns.region_data.offset
    matchups_per_region_r1 = assigns.matchups_per_region_r1
    bracket_size = assigns.bracket_size

    # Calculate base positions for rounds dynamically (like bracket_editor)
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

    container_height = matchups_per_region_r1 * 80

    assigns = assigns
      |> assign(:offset, offset)
      |> assign(:r2_base, r2_base)
      |> assign(:r3_base, r3_base)
      |> assign(:r4_pos, r4_pos)
      |> assign(:r2_matchups_per_region, r2_matchups_per_region)
      |> assign(:r3_matchups_per_region, r3_matchups_per_region)
      |> assign(:container_height, container_height)

    ~H"""
    <div class="flex items-center">
      <!-- Round 1 - Use actual matchup data with both contestants -->
      <div class="flex flex-col justify-around" style={"min-height: #{@container_height}px;"}>
        <%= for {matchup, idx} <- Enum.with_index(@region_data.matchups) do %>
          <div class="relative">
            <.my_bracket_matchup_box
              position={matchup.position}
              contestant_a={matchup.contestant_a}
              contestant_b={matchup.contestant_b}
              picks={@picks}
              contestants_map={@contestants_map}
              matchups_map={@matchups_map}
              eliminated_map={@eliminated_map}
              region_name={@region_name}
              round={1}
              matchup_position={matchup.position}
              size="small"
            />
            <div class="absolute right-0 top-1/2 w-4 h-px bg-gray-600 translate-x-full"></div>
            <% connector_height = div(@container_height, @matchups_per_region_r1 * 2) %>
            <%= if rem(idx, 2) == 0 do %>
              <div class="absolute right-0 top-1/2 w-px bg-gray-600 translate-x-[calc(100%+16px)]" style={"height: #{connector_height}px;"}></div>
            <% else %>
              <div class="absolute right-0 bottom-1/2 w-px bg-gray-600 translate-x-[calc(100%+16px)]" style={"height: #{connector_height}px;"}></div>
            <% end %>
          </div>
        <% end %>
      </div>

      <div class="w-4"></div>

      <!-- Round 2 - Derive contestants from picks -->
      <%= if @r2_matchups_per_region > 0 do %>
        <div class="flex flex-col justify-around" style={"min-height: #{@container_height}px;"}>
          <%= for idx <- 0..(@r2_matchups_per_region - 1) do %>
            <% position = @r2_base + idx + 1 %>
            <% source_a = @offset + idx * 2 + 1 %>
            <% source_b = @offset + idx * 2 + 2 %>
            <div class="relative">
              <.my_bracket_matchup_box_from_picks
                position={position}
                source_a={source_a}
                source_b={source_b}
                picks={@picks}
                contestants_map={@contestants_map}
                matchups_map={@matchups_map}
                eliminated_map={@eliminated_map}
                region_name={@region_name}
                round={2}
                matchup_position={position}
                size="small"
              />
              <div class="absolute right-0 top-1/2 w-4 h-px bg-gray-600 translate-x-full"></div>
              <% connector_height = div(@container_height, @r2_matchups_per_region * 2) %>
              <%= if rem(idx, 2) == 0 do %>
                <div class="absolute right-0 top-1/2 w-px bg-gray-600 translate-x-[calc(100%+16px)]" style={"height: #{connector_height}px;"}></div>
              <% else %>
                <div class="absolute right-0 bottom-1/2 w-px bg-gray-600 translate-x-[calc(100%+16px)]" style={"height: #{connector_height}px;"}></div>
              <% end %>
            </div>
          <% end %>
        </div>

        <div class="w-4"></div>
      <% end %>

      <!-- Round 3 (Sweet 16) -->
      <%= if @r3_matchups_per_region > 0 do %>
        <div class="flex flex-col justify-around" style={"min-height: #{@container_height}px;"}>
          <%= for idx <- 0..(@r3_matchups_per_region - 1) do %>
            <% position = @r3_base + idx + 1 %>
            <% source_a = @r2_base + idx * 2 + 1 %>
            <% source_b = @r2_base + idx * 2 + 2 %>
            <div class="relative">
              <.my_bracket_matchup_box_from_picks
                position={position}
                source_a={source_a}
                source_b={source_b}
                picks={@picks}
                contestants_map={@contestants_map}
                matchups_map={@matchups_map}
                eliminated_map={@eliminated_map}
                region_name={@region_name}
                round={3}
                matchup_position={position}
              />
              <%= if @regional_rounds >= 4 do %>
                <div class="absolute right-0 top-1/2 w-4 h-px bg-gray-600 translate-x-full"></div>
                <% connector_height = div(@container_height, @r3_matchups_per_region * 2) %>
                <%= if rem(idx, 2) == 0 do %>
                  <div class="absolute right-0 top-1/2 w-px bg-gray-600 translate-x-[calc(100%+16px)]" style={"height: #{connector_height}px;"}></div>
                <% else %>
                  <div class="absolute right-0 bottom-1/2 w-px bg-gray-600 translate-x-[calc(100%+16px)]" style={"height: #{connector_height}px;"}></div>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </div>

        <%= if @regional_rounds >= 4 do %>
          <div class="w-4"></div>
        <% end %>
      <% end %>

      <!-- Round 4 (Elite 8) -->
      <%= if @regional_rounds >= 4 do %>
        <div class="flex flex-col justify-center" style={"min-height: #{@container_height}px;"}>
          <div class="relative">
            <.my_bracket_matchup_box_from_picks
              position={@r4_pos}
              source_a={@r3_base + 1}
              source_b={@r3_base + 2}
              picks={@picks}
              contestants_map={@contestants_map}
              matchups_map={@matchups_map}
              eliminated_map={@eliminated_map}
              region_name={@region_name}
              round={4}
              matchup_position={@r4_pos}
            />
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Right-side region bracket for My Bracket tab (read-only)
  # Uses exact same structure as bracket_editor_live.ex
  defp my_bracket_region_right(assigns) do
    offset = assigns.region_data.offset
    matchups_per_region_r1 = assigns.matchups_per_region_r1
    bracket_size = assigns.bracket_size

    # Calculate base positions for rounds dynamically (like bracket_editor)
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

    container_height = matchups_per_region_r1 * 80

    assigns = assigns
      |> assign(:offset, offset)
      |> assign(:r2_base, r2_base)
      |> assign(:r3_base, r3_base)
      |> assign(:r4_pos, r4_pos)
      |> assign(:r2_matchups_per_region, r2_matchups_per_region)
      |> assign(:r3_matchups_per_region, r3_matchups_per_region)
      |> assign(:container_height, container_height)

    ~H"""
    <div class="flex items-center justify-end">
      <!-- Round 4 (Elite 8) -->
      <%= if @regional_rounds >= 4 do %>
        <div class="flex flex-col justify-center" style={"min-height: #{@container_height}px;"}>
          <div class="relative">
            <.my_bracket_matchup_box_from_picks
              position={@r4_pos}
              source_a={@r3_base + 1}
              source_b={@r3_base + 2}
              picks={@picks}
              contestants_map={@contestants_map}
              matchups_map={@matchups_map}
              eliminated_map={@eliminated_map}
              region_name={@region_name}
              round={4}
              matchup_position={@r4_pos}
            />
          </div>
        </div>
      <% end %>

      <!-- Round 3 (Sweet 16) -->
      <%= if @r3_matchups_per_region > 0 do %>
        <%= if @regional_rounds >= 4 do %>
          <div class="w-4"></div>
        <% end %>

        <div class="flex flex-col justify-around" style={"min-height: #{@container_height}px;"}>
          <%= for idx <- 0..(@r3_matchups_per_region - 1) do %>
            <% position = @r3_base + idx + 1 %>
            <% source_a = @r2_base + idx * 2 + 1 %>
            <% source_b = @r2_base + idx * 2 + 2 %>
            <div class="relative">
              <%= if @regional_rounds >= 4 do %>
                <div class="absolute left-0 top-1/2 w-4 h-px bg-gray-600 -translate-x-full"></div>
                <% connector_height = div(@container_height, @r3_matchups_per_region * 2) %>
                <%= if rem(idx, 2) == 0 do %>
                  <div class="absolute left-0 top-1/2 w-px bg-gray-600 -translate-x-[16px]" style={"height: #{connector_height}px;"}></div>
                <% else %>
                  <div class="absolute left-0 bottom-1/2 w-px bg-gray-600 -translate-x-[16px]" style={"height: #{connector_height}px;"}></div>
                <% end %>
              <% end %>
              <.my_bracket_matchup_box_from_picks
                position={position}
                source_a={source_a}
                source_b={source_b}
                picks={@picks}
                contestants_map={@contestants_map}
                matchups_map={@matchups_map}
                eliminated_map={@eliminated_map}
                region_name={@region_name}
                round={3}
                matchup_position={position}
              />
            </div>
          <% end %>
        </div>

        <div class="w-4"></div>
      <% end %>

      <!-- Round 2 -->
      <%= if @r2_matchups_per_region > 0 do %>
        <div class="flex flex-col justify-around" style={"min-height: #{@container_height}px;"}>
          <%= for idx <- 0..(@r2_matchups_per_region - 1) do %>
            <% position = @r2_base + idx + 1 %>
            <% source_a = @offset + idx * 2 + 1 %>
            <% source_b = @offset + idx * 2 + 2 %>
            <div class="relative">
              <div class="absolute left-0 top-1/2 w-4 h-px bg-gray-600 -translate-x-full"></div>
              <% connector_height = div(@container_height, @r2_matchups_per_region * 2) %>
              <%= if rem(idx, 2) == 0 do %>
                <div class="absolute left-0 top-1/2 w-px bg-gray-600 -translate-x-[16px]" style={"height: #{connector_height}px;"}></div>
              <% else %>
                <div class="absolute left-0 bottom-1/2 w-px bg-gray-600 -translate-x-[16px]" style={"height: #{connector_height}px;"}></div>
              <% end %>
              <.my_bracket_matchup_box_from_picks
                position={position}
                source_a={source_a}
                source_b={source_b}
                picks={@picks}
                contestants_map={@contestants_map}
                matchups_map={@matchups_map}
                eliminated_map={@eliminated_map}
                region_name={@region_name}
                round={2}
                matchup_position={position}
                size="small"
              />
            </div>
          <% end %>
        </div>

        <div class="w-4"></div>
      <% end %>

      <!-- Round 1 - Use actual matchup data with both contestants -->
      <div class="flex flex-col justify-around" style={"min-height: #{@container_height}px;"}>
        <%= for {matchup, idx} <- Enum.with_index(@region_data.matchups) do %>
          <div class="relative">
            <% connector_height = div(@container_height, @matchups_per_region_r1 * 2) %>
            <%= if rem(idx, 2) == 0 do %>
              <div class="absolute left-0 top-1/2 w-px bg-gray-600 -translate-x-[16px]" style={"height: #{connector_height}px;"}></div>
            <% else %>
              <div class="absolute left-0 bottom-1/2 w-px bg-gray-600 -translate-x-[16px]" style={"height: #{connector_height}px;"}></div>
            <% end %>
            <div class="absolute left-0 top-1/2 w-4 h-px bg-gray-600 -translate-x-full"></div>
            <.my_bracket_matchup_box
              position={matchup.position}
              contestant_a={matchup.contestant_a}
              contestant_b={matchup.contestant_b}
              picks={@picks}
              contestants_map={@contestants_map}
              matchups_map={@matchups_map}
              eliminated_map={@eliminated_map}
              region_name={@region_name}
              round={1}
              matchup_position={matchup.position}
              size="small"
            />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Matchup box showing both contestants with the user's pick highlighted
  # For Round 1: contestant_a and contestant_b are passed directly
  # Shows green/checkmark for correct picks, red/X for incorrect picks
  defp my_bracket_matchup_box(assigns) do
    assigns = Map.put_new(assigns, :size, "normal")

    # Get the user's pick for this position
    current_pick = Map.get(assigns.picks, to_string(assigns.position))

    # Look up actual matchup result using {region, round, position}
    region_key = String.downcase(assigns.region_name)
    matchup_key = {region_key, assigns.round, assigns.matchup_position}
    actual_matchup = Map.get(assigns.matchups_map, matchup_key)
    actual_winner_id = if actual_matchup, do: actual_matchup.winner_id

    # Check if the picked contestant was eliminated in an earlier round
    # Use eliminated_map built from matchup results
    eliminated_round = if current_pick, do: Map.get(assigns.eliminated_map, current_pick)
    current_round = assigns.round

    # Determine pick status: :correct, :incorrect, :eliminated, or :pending
    pick_status = cond do
      is_nil(current_pick) -> :no_pick
      eliminated_round && eliminated_round < current_round -> :eliminated
      is_nil(actual_winner_id) -> :pending
      current_pick == actual_winner_id -> :correct
      true -> :incorrect
    end

    assigns = assigns
      |> assign(:current_pick, current_pick)
      |> assign(:actual_winner_id, actual_winner_id)
      |> assign(:pick_status, pick_status)

    ~H"""
    <div class={[
      "bg-gray-800 rounded border overflow-hidden",
      @pick_status == :correct && "border-green-500",
      @pick_status in [:incorrect, :eliminated] && "border-red-500",
      @pick_status in [:pending, :no_pick] && "border-gray-700",
      @size == "small" && "w-36",
      @size == "normal" && "w-44"
    ]}>
      <!-- Contestant A -->
      <div class={[
        "flex items-center px-2 py-1 border-b border-gray-700",
        @current_pick && @contestant_a && @current_pick == @contestant_a.id && @pick_status == :correct && "bg-green-600/40",
        @current_pick && @contestant_a && @current_pick == @contestant_a.id && @pick_status in [:incorrect, :eliminated] && "bg-red-600/30"
      ]}>
        <%= if @contestant_a do %>
          <span class={[
            "text-xs font-mono w-5",
            @current_pick == @contestant_a.id && @pick_status == :correct && "text-green-300",
            @current_pick == @contestant_a.id && @pick_status in [:incorrect, :eliminated] && "text-red-300",
            !(@current_pick == @contestant_a.id && @pick_status in [:correct, :incorrect, :eliminated]) && "text-gray-500"
          ]}><%= @contestant_a.seed %></span>
          <span class={[
            "text-xs truncate flex-1",
            @current_pick == @contestant_a.id && @pick_status == :correct && "text-white font-semibold",
            @current_pick == @contestant_a.id && @pick_status in [:incorrect, :eliminated] && "text-red-300 line-through",
            !(@current_pick == @contestant_a.id && @pick_status in [:correct, :incorrect, :eliminated]) && "text-gray-300"
          ]}><%= @contestant_a.name %></span>
          <%= if @current_pick == @contestant_a.id && @pick_status == :correct do %>
            <span class="text-green-300 text-xs">✓</span>
          <% end %>
          <%= if @current_pick == @contestant_a.id && @pick_status in [:incorrect, :eliminated] do %>
            <span class="text-red-400 text-xs">✗</span>
          <% end %>
        <% else %>
          <span class="text-gray-600 text-xs italic">TBD</span>
        <% end %>
      </div>
      <!-- Contestant B -->
      <div class={[
        "flex items-center px-2 py-1",
        @current_pick && @contestant_b && @current_pick == @contestant_b.id && @pick_status == :correct && "bg-green-600/40",
        @current_pick && @contestant_b && @current_pick == @contestant_b.id && @pick_status in [:incorrect, :eliminated] && "bg-red-600/30"
      ]}>
        <%= if @contestant_b do %>
          <span class={[
            "text-xs font-mono w-5",
            @current_pick == @contestant_b.id && @pick_status == :correct && "text-green-300",
            @current_pick == @contestant_b.id && @pick_status in [:incorrect, :eliminated] && "text-red-300",
            !(@current_pick == @contestant_b.id && @pick_status in [:correct, :incorrect, :eliminated]) && "text-gray-500"
          ]}><%= @contestant_b.seed %></span>
          <span class={[
            "text-xs truncate flex-1",
            @current_pick == @contestant_b.id && @pick_status == :correct && "text-white font-semibold",
            @current_pick == @contestant_b.id && @pick_status in [:incorrect, :eliminated] && "text-red-300 line-through",
            !(@current_pick == @contestant_b.id && @pick_status in [:correct, :incorrect, :eliminated]) && "text-gray-300"
          ]}><%= @contestant_b.name %></span>
          <%= if @current_pick == @contestant_b.id && @pick_status == :correct do %>
            <span class="text-green-300 text-xs">✓</span>
          <% end %>
          <%= if @current_pick == @contestant_b.id && @pick_status in [:incorrect, :eliminated] do %>
            <span class="text-red-400 text-xs">✗</span>
          <% end %>
        <% else %>
          <span class="text-gray-600 text-xs italic">TBD</span>
        <% end %>
      </div>
    </div>
    """
  end

  # Matchup box for later rounds - derives contestants from previous picks
  # Shows green/checkmark for correct picks, red/X for incorrect picks
  defp my_bracket_matchup_box_from_picks(assigns) do
    assigns = Map.put_new(assigns, :size, "normal")

    # Get contestants from previous picks
    pick_a = Map.get(assigns.picks, to_string(assigns.source_a))
    pick_b = Map.get(assigns.picks, to_string(assigns.source_b))

    contestant_a = if pick_a, do: Map.get(assigns.contestants_map, pick_a)
    contestant_b = if pick_b, do: Map.get(assigns.contestants_map, pick_b)

    # Get the user's pick for this position
    current_pick = Map.get(assigns.picks, to_string(assigns.position))

    # Look up actual matchup result using {region, round, position}
    region_key = String.downcase(assigns.region_name)
    matchup_key = {region_key, assigns.round, assigns.matchup_position}
    actual_matchup = Map.get(assigns.matchups_map, matchup_key)
    actual_winner_id = if actual_matchup, do: actual_matchup.winner_id

    # Check if the picked contestant was eliminated in an earlier round
    # Use eliminated_map built from matchup results
    eliminated_round = if current_pick, do: Map.get(assigns.eliminated_map, current_pick)
    current_round = assigns.round

    # Determine pick status: :correct, :incorrect, :eliminated, or :pending
    pick_status = cond do
      is_nil(current_pick) -> :no_pick
      eliminated_round && eliminated_round < current_round -> :eliminated
      is_nil(actual_winner_id) -> :pending
      current_pick == actual_winner_id -> :correct
      true -> :incorrect
    end

    assigns = assigns
      |> assign(:contestant_a, contestant_a)
      |> assign(:contestant_b, contestant_b)
      |> assign(:current_pick, current_pick)
      |> assign(:actual_winner_id, actual_winner_id)
      |> assign(:pick_status, pick_status)

    ~H"""
    <div class={[
      "bg-gray-800 rounded border overflow-hidden",
      @pick_status == :correct && "border-green-500",
      @pick_status in [:incorrect, :eliminated] && "border-red-500",
      @pick_status in [:pending, :no_pick] && "border-gray-700",
      @size == "small" && "w-36",
      @size == "normal" && "w-44"
    ]}>
      <!-- Contestant A -->
      <div class={[
        "flex items-center px-2 py-1 border-b border-gray-700",
        @current_pick && @contestant_a && @current_pick == @contestant_a.id && @pick_status == :correct && "bg-green-600/40",
        @current_pick && @contestant_a && @current_pick == @contestant_a.id && @pick_status in [:incorrect, :eliminated] && "bg-red-600/30"
      ]}>
        <%= if @contestant_a do %>
          <span class={[
            "text-xs font-mono w-5",
            @current_pick == @contestant_a.id && @pick_status == :correct && "text-green-300",
            @current_pick == @contestant_a.id && @pick_status in [:incorrect, :eliminated] && "text-red-300",
            !(@current_pick == @contestant_a.id && @pick_status in [:correct, :incorrect, :eliminated]) && "text-gray-500"
          ]}><%= @contestant_a.seed %></span>
          <span class={[
            "text-xs truncate flex-1",
            @current_pick == @contestant_a.id && @pick_status == :correct && "text-white font-semibold",
            @current_pick == @contestant_a.id && @pick_status in [:incorrect, :eliminated] && "text-red-300 line-through",
            !(@current_pick == @contestant_a.id && @pick_status in [:correct, :incorrect, :eliminated]) && "text-gray-300"
          ]}><%= @contestant_a.name %></span>
          <%= if @current_pick == @contestant_a.id && @pick_status == :correct do %>
            <span class="text-green-300 text-xs">✓</span>
          <% end %>
          <%= if @current_pick == @contestant_a.id && @pick_status in [:incorrect, :eliminated] do %>
            <span class="text-red-400 text-xs">✗</span>
          <% end %>
        <% else %>
          <span class="text-gray-600 text-xs italic">TBD</span>
        <% end %>
      </div>
      <!-- Contestant B -->
      <div class={[
        "flex items-center px-2 py-1",
        @current_pick && @contestant_b && @current_pick == @contestant_b.id && @pick_status == :correct && "bg-green-600/40",
        @current_pick && @contestant_b && @current_pick == @contestant_b.id && @pick_status in [:incorrect, :eliminated] && "bg-red-600/30"
      ]}>
        <%= if @contestant_b do %>
          <span class={[
            "text-xs font-mono w-5",
            @current_pick == @contestant_b.id && @pick_status == :correct && "text-green-300",
            @current_pick == @contestant_b.id && @pick_status in [:incorrect, :eliminated] && "text-red-300",
            !(@current_pick == @contestant_b.id && @pick_status in [:correct, :incorrect, :eliminated]) && "text-gray-500"
          ]}><%= @contestant_b.seed %></span>
          <span class={[
            "text-xs truncate flex-1",
            @current_pick == @contestant_b.id && @pick_status == :correct && "text-white font-semibold",
            @current_pick == @contestant_b.id && @pick_status in [:incorrect, :eliminated] && "text-red-300 line-through",
            !(@current_pick == @contestant_b.id && @pick_status in [:correct, :incorrect, :eliminated]) && "text-gray-300"
          ]}><%= @contestant_b.name %></span>
          <%= if @current_pick == @contestant_b.id && @pick_status == :correct do %>
            <span class="text-green-300 text-xs">✓</span>
          <% end %>
          <%= if @current_pick == @contestant_b.id && @pick_status in [:incorrect, :eliminated] do %>
            <span class="text-red-400 text-xs">✗</span>
          <% end %>
        <% else %>
          <span class="text-gray-600 text-xs italic">TBD</span>
        <% end %>
      </div>
    </div>
    """
  end

  # Final Four slot for My Bracket tab
  # Shows green/checkmark for correct picks, red/X for incorrect picks
  defp my_bracket_final_four_slot(assigns) do
    # source_a and source_b are tuple keys like {"sad", 4, 1} for looking up Elite 8 matchups
    # We need to convert these to global positions to look up user picks
    # Elite 8 positions are 57-60 (R1:32 + R2:16 + R3:8 + 1-4)

    # The source tuple is {region, round, position} where position is 1-4 for Elite 8
    # Elite 8 global positions: 56 + position = 57, 58, 59, 60
    {_region_a, _round_a, pos_a} = assigns.source_a
    {_region_b, _round_b, pos_b} = assigns.source_b

    elite8_global_pos_a = 56 + pos_a  # 57, 58, 59, or 60
    elite8_global_pos_b = 56 + pos_b

    # Look up user's picks for Elite 8 (these determine who advances to Final Four)
    pick_a = Map.get(assigns.picks, to_string(elite8_global_pos_a))
    pick_b = Map.get(assigns.picks, to_string(elite8_global_pos_b))

    contestant_a = if pick_a, do: Map.get(assigns.contestants_map, pick_a)
    contestant_b = if pick_b, do: Map.get(assigns.contestants_map, pick_b)

    # Final Four positions are 61 and 62 (position 1 = 61, position 2 = 62)
    ff_global_pos = 60 + assigns.position
    current_pick = Map.get(assigns.picks, to_string(ff_global_pos))
    winner = if current_pick, do: Map.get(assigns.contestants_map, current_pick)

    # Look up actual matchup result - Final Four uses round 5 with empty region
    matchup_key = {"", 5, assigns.position}
    actual_matchup = Map.get(assigns.matchups_map, matchup_key)
    actual_winner_id = if actual_matchup, do: actual_matchup.winner_id

    # Check if the picked contestant was eliminated in an earlier round
    # Use eliminated_map built from matchup results
    eliminated_round = if current_pick, do: Map.get(assigns.eliminated_map, current_pick)
    current_round = 5  # Final Four is round 5

    # Determine pick status
    pick_status = cond do
      is_nil(current_pick) -> :no_pick
      eliminated_round && eliminated_round < current_round -> :eliminated
      is_nil(actual_winner_id) -> :pending
      current_pick == actual_winner_id -> :correct
      true -> :incorrect
    end

    assigns = assigns
      |> assign(:contestant_a, contestant_a)
      |> assign(:contestant_b, contestant_b)
      |> assign(:winner, winner)
      |> assign(:current_pick, current_pick)
      |> assign(:actual_winner_id, actual_winner_id)
      |> assign(:pick_status, pick_status)

    ~H"""
    <div class="text-center">
      <div class="text-xs text-gray-500 mb-1">Final Four</div>
      <div class={[
        "bg-gray-800 rounded border overflow-hidden w-44 mx-auto",
        @pick_status == :correct && "border-green-500",
        @pick_status in [:incorrect, :eliminated] && "border-red-500",
        @pick_status in [:pending, :no_pick] && "border-gray-700"
      ]}>
        <!-- Contestant A -->
        <div class={[
          "flex items-center px-2 py-1.5 border-b border-gray-700",
          @winner && @contestant_a && @winner.id == @contestant_a.id && @pick_status == :correct && "bg-green-600/40",
          @winner && @contestant_a && @winner.id == @contestant_a.id && @pick_status in [:incorrect, :eliminated] && "bg-red-600/30"
        ]}>
          <%= if @contestant_a do %>
            <span class={[
              "text-xs font-mono w-5",
              @winner && @winner.id == @contestant_a.id && @pick_status == :correct && "text-green-300",
              @winner && @winner.id == @contestant_a.id && @pick_status in [:incorrect, :eliminated] && "text-red-300",
              !(@winner && @winner.id == @contestant_a.id) && "text-gray-500"
            ]}><%= @contestant_a.seed %></span>
            <span class={[
              "text-xs truncate flex-1",
              @winner && @winner.id == @contestant_a.id && @pick_status == :correct && "text-white font-semibold",
              @winner && @winner.id == @contestant_a.id && @pick_status in [:incorrect, :eliminated] && "text-red-300 line-through",
              !(@winner && @winner.id == @contestant_a.id) && "text-gray-300"
            ]}><%= @contestant_a.name %></span>
            <%= if @winner && @winner.id == @contestant_a.id do %>
              <%= if @pick_status == :correct do %>
                <span class="text-green-300 text-xs">✓</span>
              <% end %>
              <%= if @pick_status in [:incorrect, :eliminated] do %>
                <span class="text-red-400 text-xs">✗</span>
              <% end %>
            <% end %>
          <% else %>
            <span class="text-gray-500 text-xs"><%= @placeholder_a %></span>
          <% end %>
        </div>
        <!-- Contestant B -->
        <div class={[
          "flex items-center px-2 py-1.5",
          @winner && @contestant_b && @winner.id == @contestant_b.id && @pick_status == :correct && "bg-green-600/40",
          @winner && @contestant_b && @winner.id == @contestant_b.id && @pick_status in [:incorrect, :eliminated] && "bg-red-600/30"
        ]}>
          <%= if @contestant_b do %>
            <span class={[
              "text-xs font-mono w-5",
              @winner && @winner.id == @contestant_b.id && @pick_status == :correct && "text-green-300",
              @winner && @winner.id == @contestant_b.id && @pick_status in [:incorrect, :eliminated] && "text-red-300",
              !(@winner && @winner.id == @contestant_b.id) && "text-gray-500"
            ]}><%= @contestant_b.seed %></span>
            <span class={[
              "text-xs truncate flex-1",
              @winner && @winner.id == @contestant_b.id && @pick_status == :correct && "text-white font-semibold",
              @winner && @winner.id == @contestant_b.id && @pick_status in [:incorrect, :eliminated] && "text-red-300 line-through",
              !(@winner && @winner.id == @contestant_b.id) && "text-gray-300"
            ]}><%= @contestant_b.name %></span>
            <%= if @winner && @winner.id == @contestant_b.id do %>
              <%= if @pick_status == :correct do %>
                <span class="text-green-300 text-xs">✓</span>
              <% end %>
              <%= if @pick_status in [:incorrect, :eliminated] do %>
                <span class="text-red-400 text-xs">✗</span>
              <% end %>
            <% end %>
          <% else %>
            <span class="text-gray-500 text-xs"><%= @placeholder_b %></span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Championship slot for My Bracket tab
  # Shows green/checkmark for correct champion pick, red/X for incorrect
  defp my_bracket_championship_slot(assigns) do
    # Final Four global positions: 61 and 62 (ff1_pos=1 -> 61, ff2_pos=2 -> 62)
    ff1_global = 60 + assigns.ff1_pos
    ff2_global = 60 + assigns.ff2_pos

    # Get user's Final Four picks (who they think will be in the championship)
    pick_a = Map.get(assigns.picks, to_string(ff1_global))
    pick_b = Map.get(assigns.picks, to_string(ff2_global))

    contestant_a = if pick_a, do: Map.get(assigns.contestants_map, pick_a)
    contestant_b = if pick_b, do: Map.get(assigns.contestants_map, pick_b)

    # Championship is position 63 (62 + championship_pos where pos=1)
    championship_global = 62 + assigns.championship_pos
    champion_pick = Map.get(assigns.picks, to_string(championship_global))
    champion = if champion_pick, do: Map.get(assigns.contestants_map, champion_pick)

    # Look up actual matchup result - Championship uses round 6 with empty region
    matchup_key = {"", 6, assigns.championship_pos}
    actual_matchup = Map.get(assigns.matchups_map, matchup_key)
    actual_winner_id = if actual_matchup, do: actual_matchup.winner_id

    # Check if the picked contestant was eliminated in an earlier round
    # Use eliminated_map built from matchup results
    eliminated_round = if champion_pick, do: Map.get(assigns.eliminated_map, champion_pick)
    current_round = 6  # Championship is round 6

    # Determine pick status
    pick_status = cond do
      is_nil(champion_pick) -> :no_pick
      eliminated_round && eliminated_round < current_round -> :eliminated
      is_nil(actual_winner_id) -> :pending
      champion_pick == actual_winner_id -> :correct
      true -> :incorrect
    end

    assigns = assigns
      |> assign(:contestant_a, contestant_a)
      |> assign(:contestant_b, contestant_b)
      |> assign(:champion, champion)
      |> assign(:champion_pick, champion_pick)
      |> assign(:actual_winner_id, actual_winner_id)
      |> assign(:pick_status, pick_status)

    ~H"""
    <div class="text-center">
      <!-- Champion display -->
      <%= if @champion do %>
        <div class={[
          "mb-3 rounded-lg p-3",
          @pick_status == :correct && "bg-green-900/40 border border-green-500",
          @pick_status in [:incorrect, :eliminated] && "bg-red-900/40 border border-red-500",
          @pick_status in [:pending, :no_pick] && "bg-gray-800 border border-gray-700"
        ]}>
          <div class="flex items-center justify-center gap-2">
            <%= if @pick_status == :correct do %>
              <span class="text-green-300 text-lg">✓</span>
            <% end %>
            <%= if @pick_status in [:incorrect, :eliminated] do %>
              <span class="text-red-400 text-lg">✗</span>
            <% end %>
            <span class={[
              "text-lg font-bold",
              @pick_status == :correct && "text-green-400",
              @pick_status in [:incorrect, :eliminated] && "text-red-400 line-through",
              @pick_status in [:pending, :no_pick] && "text-white"
            ]}><%= @champion.seed %>. <%= @champion.name %></span>
          </div>
          <div class={[
            "text-xs",
            @pick_status == :correct && "text-green-500/70",
            @pick_status in [:incorrect, :eliminated] && "text-red-500/70",
            @pick_status in [:pending, :no_pick] && "text-gray-400"
          ]}>Your Champion Pick</div>
        </div>
      <% end %>

      <div class="text-xs text-yellow-500 font-bold mb-1 uppercase">Championship</div>
      <div class={[
        "bg-gray-800 rounded border overflow-hidden w-48 mx-auto",
        @pick_status == :correct && "border-green-500",
        @pick_status in [:incorrect, :eliminated] && "border-red-500",
        @pick_status in [:pending, :no_pick] && "border-yellow-600"
      ]}>
        <!-- Finalist A -->
        <div class={[
          "flex items-center px-2 py-1.5 border-b border-gray-700",
          @champion && @contestant_a && @champion.id == @contestant_a.id && @pick_status == :correct && "bg-green-600/40",
          @champion && @contestant_a && @champion.id == @contestant_a.id && @pick_status in [:incorrect, :eliminated] && "bg-red-600/30"
        ]}>
          <%= if @contestant_a do %>
            <span class={[
              "text-xs font-mono w-5",
              @champion && @champion.id == @contestant_a.id && @pick_status == :correct && "text-green-300",
              @champion && @champion.id == @contestant_a.id && @pick_status in [:incorrect, :eliminated] && "text-red-300",
              !(@champion && @champion.id == @contestant_a.id) && "text-gray-500"
            ]}><%= @contestant_a.seed %></span>
            <span class={[
              "text-xs truncate flex-1",
              @champion && @champion.id == @contestant_a.id && @pick_status == :correct && "text-white font-semibold",
              @champion && @champion.id == @contestant_a.id && @pick_status in [:incorrect, :eliminated] && "text-red-300 line-through",
              !(@champion && @champion.id == @contestant_a.id) && "text-gray-300"
            ]}><%= @contestant_a.name %></span>
            <%= if @champion && @champion.id == @contestant_a.id do %>
              <%= if @pick_status == :correct do %>
                <span class="text-green-300 text-xs">✓</span>
              <% end %>
              <%= if @pick_status in [:incorrect, :eliminated] do %>
                <span class="text-red-400 text-xs">✗</span>
              <% end %>
            <% end %>
          <% else %>
            <span class="text-gray-500 text-xs">Final Four 1 Winner</span>
          <% end %>
        </div>
        <!-- Finalist B -->
        <div class={[
          "flex items-center px-2 py-1.5",
          @champion && @contestant_b && @champion.id == @contestant_b.id && @pick_status == :correct && "bg-green-600/40",
          @champion && @contestant_b && @champion.id == @contestant_b.id && @pick_status in [:incorrect, :eliminated] && "bg-red-600/30"
        ]}>
          <%= if @contestant_b do %>
            <span class={[
              "text-xs font-mono w-5",
              @champion && @champion.id == @contestant_b.id && @pick_status == :correct && "text-green-300",
              @champion && @champion.id == @contestant_b.id && @pick_status in [:incorrect, :eliminated] && "text-red-300",
              !(@champion && @champion.id == @contestant_b.id) && "text-gray-500"
            ]}><%= @contestant_b.seed %></span>
            <span class={[
              "text-xs truncate flex-1",
              @champion && @champion.id == @contestant_b.id && @pick_status == :correct && "text-white font-semibold",
              @champion && @champion.id == @contestant_b.id && @pick_status in [:incorrect, :eliminated] && "text-red-300 line-through",
              !(@champion && @champion.id == @contestant_b.id) && "text-gray-300"
            ]}><%= @contestant_b.name %></span>
            <%= if @champion && @champion.id == @contestant_b.id do %>
              <%= if @pick_status == :correct do %>
                <span class="text-green-300 text-xs">✓</span>
              <% end %>
              <%= if @pick_status in [:incorrect, :eliminated] do %>
                <span class="text-red-400 text-xs">✗</span>
              <% end %>
            <% end %>
          <% else %>
            <span class="text-gray-500 text-xs">Final Four 2 Winner</span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp format_bracket_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y at %I:%M %p")
  end

  # =============================================================================
  # Results Bracket Components (showing actual tournament results)
  # =============================================================================

  # Left-side region bracket for Results tab
  # Expects: region_name (string like "sad"), region_data, matchups_per_region_r1, regional_rounds, bracket_size
  defp results_region_left(assigns) do
    region_data = assigns.region_data
    offset = region_data.offset
    matchups_per_region_r1 = assigns.matchups_per_region_r1
    regional_rounds = assigns.regional_rounds
    region_name = assigns.region_name

    # Calculate position bases for each round (positions within each round, offset by region index)
    # Round 2: 4 matchups per region, positions 1-4 for first region, 5-8 for second, etc.
    r2_pos_base = div(offset, 2)  # 0, 4, 8, 12 for regions 0-3
    r3_pos_base = div(offset, 4)  # 0, 2, 4, 6 for regions 0-3
    r4_pos = div(offset, 8) + 1   # 1, 2, 3, 4 for regions 0-3

    # Calculate matchups per round for this region
    r2_matchups_per_region = div(matchups_per_region_r1, 2)
    r3_matchups_per_region = if regional_rounds >= 4, do: div(r2_matchups_per_region, 2), else: 0

    # Container height based on R1 matchups (80px matches My Bracket tab)
    container_height = matchups_per_region_r1 * 80

    assigns = assigns
      |> assign(:r1_matchups, region_data.matchups)
      |> assign(:r2_pos_base, r2_pos_base)
      |> assign(:r3_pos_base, r3_pos_base)
      |> assign(:r4_pos, r4_pos)
      |> assign(:r2_matchups_per_region, r2_matchups_per_region)
      |> assign(:r3_matchups_per_region, r3_matchups_per_region)
      |> assign(:container_height, container_height)
      |> assign(:region_name, region_name)

    ~H"""
    <div class="flex items-center">
      <!-- Round 1 matchups -->
      <div class="flex flex-col justify-around" style={"min-height: #{@container_height}px;"}>
        <%= for matchup <- @r1_matchups do %>
          <div class="relative">
            <.results_matchup_box
              region={@region_name}
              position={matchup.position}
              contestant_a={matchup.contestant_a}
              contestant_b={matchup.contestant_b}
              matchups_map={@matchups_map}
              contestants_map={@contestants_map}
              size="small"
            />
            <!-- Connector to R2 -->
            <div class="absolute right-0 top-1/2 w-4 h-px bg-gray-600 translate-x-full"></div>
            <% connector_height = div(@container_height, @matchups_per_region_r1 * 2) %>
            <%= if rem(matchup.position - List.first(@r1_matchups).position, 2) == 0 do %>
              <div class="absolute right-0 top-1/2 w-px bg-gray-600 translate-x-[16px]" style={"height: #{connector_height}px;"}></div>
            <% else %>
              <div class="absolute right-0 bottom-1/2 w-px bg-gray-600 translate-x-[16px]" style={"height: #{connector_height}px;"}></div>
            <% end %>
          </div>
        <% end %>
      </div>

      <!-- Spacer R1->R2 -->
      <div class="w-4"></div>

      <!-- Round 2 matchups -->
      <div class="flex flex-col justify-around" style={"min-height: #{@container_height}px;"}>
        <%= for idx <- 0..(@r2_matchups_per_region - 1) do %>
          <% position = @r2_pos_base + idx + 1 %>
          <div class="relative">
            <.results_matchup_box_from_matchups
              region={@region_name}
              round={2}
              position={position}
              matchups_map={@matchups_map}
              contestants_map={@contestants_map}
              size="small"
            />
            <%= if @regional_rounds >= 3 do %>
              <div class="absolute right-0 top-1/2 w-4 h-px bg-gray-600 translate-x-full"></div>
              <% r2_connector = div(@container_height, @r2_matchups_per_region * 2) %>
              <%= if rem(idx, 2) == 0 do %>
                <div class="absolute right-0 top-1/2 w-px bg-gray-600 translate-x-[16px]" style={"height: #{r2_connector}px;"}></div>
              <% else %>
                <div class="absolute right-0 bottom-1/2 w-px bg-gray-600 translate-x-[16px]" style={"height: #{r2_connector}px;"}></div>
              <% end %>
            <% end %>
          </div>
        <% end %>
      </div>

      <!-- Round 3 (Sweet 16) if applicable -->
      <%= if @r3_matchups_per_region > 0 do %>
        <div class="w-4"></div>

        <div class="flex flex-col justify-around" style={"min-height: #{@container_height}px;"}>
          <%= for idx <- 0..(@r3_matchups_per_region - 1) do %>
            <% position = @r3_pos_base + idx + 1 %>
            <div class="relative">
              <.results_matchup_box_from_matchups
                region={@region_name}
                round={3}
                position={position}
                matchups_map={@matchups_map}
                contestants_map={@contestants_map}
              />
              <%= if @regional_rounds >= 4 do %>
                <div class="absolute right-0 top-1/2 w-4 h-px bg-gray-600 translate-x-full"></div>
                <% r3_connector = div(@container_height, @r3_matchups_per_region * 2) %>
                <%= if rem(idx, 2) == 0 do %>
                  <div class="absolute right-0 top-1/2 w-px bg-gray-600 translate-x-[16px]" style={"height: #{r3_connector}px;"}></div>
                <% else %>
                  <div class="absolute right-0 bottom-1/2 w-px bg-gray-600 translate-x-[16px]" style={"height: #{r3_connector}px;"}></div>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </div>

        <div class="w-4"></div>
      <% end %>

      <!-- Round 4 (Elite 8) if applicable -->
      <%= if @regional_rounds >= 4 do %>
        <div class="flex flex-col justify-center" style={"min-height: #{@container_height}px;"}>
          <.results_matchup_box_from_matchups
            region={@region_name}
            round={4}
            position={@r4_pos}
            matchups_map={@matchups_map}
            contestants_map={@contestants_map}
          />
        </div>
      <% end %>
    </div>
    """
  end

  # Right-side region bracket for Results tab
  # Expects: region_name (string like "happy"), region_data, matchups_per_region_r1, regional_rounds, bracket_size
  defp results_region_right(assigns) do
    region_data = assigns.region_data
    offset = region_data.offset
    matchups_per_region_r1 = assigns.matchups_per_region_r1
    regional_rounds = assigns.regional_rounds
    region_name = assigns.region_name

    # Calculate position bases for each round (positions within each round, offset by region index)
    r2_pos_base = div(offset, 2)  # 0, 4, 8, 12 for regions 0-3
    r3_pos_base = div(offset, 4)  # 0, 2, 4, 6 for regions 0-3
    r4_pos = div(offset, 8) + 1   # 1, 2, 3, 4 for regions 0-3

    # Calculate matchups per round for this region
    r2_matchups_per_region = div(matchups_per_region_r1, 2)
    r3_matchups_per_region = if regional_rounds >= 4, do: div(r2_matchups_per_region, 2), else: 0

    # Container height based on R1 matchups (80px matches My Bracket tab)
    container_height = matchups_per_region_r1 * 80

    assigns = assigns
      |> assign(:r1_matchups, region_data.matchups)
      |> assign(:r2_pos_base, r2_pos_base)
      |> assign(:r3_pos_base, r3_pos_base)
      |> assign(:r4_pos, r4_pos)
      |> assign(:r2_matchups_per_region, r2_matchups_per_region)
      |> assign(:r3_matchups_per_region, r3_matchups_per_region)
      |> assign(:container_height, container_height)
      |> assign(:region_name, region_name)

    ~H"""
    <div class="flex items-center justify-end">
      <!-- Round 4 (Elite 8) -->
      <%= if @regional_rounds >= 4 do %>
        <div class="flex flex-col justify-center" style={"min-height: #{@container_height}px;"}>
          <div class="relative">
            <.results_matchup_box_from_matchups
              region={@region_name}
              round={4}
              position={@r4_pos}
              matchups_map={@matchups_map}
              contestants_map={@contestants_map}
            />
          </div>
        </div>
      <% end %>

      <!-- Round 3 (Sweet 16) -->
      <%= if @r3_matchups_per_region > 0 do %>
        <%= if @regional_rounds >= 4 do %>
          <div class="w-4"></div>
        <% end %>

        <div class="flex flex-col justify-around" style={"min-height: #{@container_height}px;"}>
          <%= for idx <- 0..(@r3_matchups_per_region - 1) do %>
            <% position = @r3_pos_base + idx + 1 %>
            <div class="relative">
              <%= if @regional_rounds >= 4 do %>
                <div class="absolute left-0 top-1/2 w-4 h-px bg-gray-600 -translate-x-full"></div>
                <% connector_height = div(@container_height, @r3_matchups_per_region * 2) %>
                <%= if rem(idx, 2) == 0 do %>
                  <div class="absolute left-0 top-1/2 w-px bg-gray-600 -translate-x-[16px]" style={"height: #{connector_height}px;"}></div>
                <% else %>
                  <div class="absolute left-0 bottom-1/2 w-px bg-gray-600 -translate-x-[16px]" style={"height: #{connector_height}px;"}></div>
                <% end %>
              <% end %>
              <.results_matchup_box_from_matchups
                region={@region_name}
                round={3}
                position={position}
                matchups_map={@matchups_map}
                contestants_map={@contestants_map}
              />
            </div>
          <% end %>
        </div>

        <div class="w-4"></div>
      <% end %>

      <!-- Round 2 -->
      <div class="flex flex-col justify-around" style={"min-height: #{@container_height}px;"}>
        <%= for idx <- 0..(@r2_matchups_per_region - 1) do %>
          <% position = @r2_pos_base + idx + 1 %>
          <div class="relative">
            <%= if @regional_rounds >= 3 do %>
              <div class="absolute left-0 top-1/2 w-4 h-px bg-gray-600 -translate-x-full"></div>
              <% r2_connector = div(@container_height, @r2_matchups_per_region * 2) %>
              <%= if rem(idx, 2) == 0 do %>
                <div class="absolute left-0 top-1/2 w-px bg-gray-600 -translate-x-[16px]" style={"height: #{r2_connector}px;"}></div>
              <% else %>
                <div class="absolute left-0 bottom-1/2 w-px bg-gray-600 -translate-x-[16px]" style={"height: #{r2_connector}px;"}></div>
              <% end %>
            <% end %>
            <.results_matchup_box_from_matchups
              region={@region_name}
              round={2}
              position={position}
              matchups_map={@matchups_map}
              contestants_map={@contestants_map}
              size="small"
            />
          </div>
        <% end %>
      </div>

      <div class="w-4"></div>

      <!-- Round 1 -->
      <div class="flex flex-col justify-around" style={"min-height: #{@container_height}px;"}>
        <%= for matchup <- @r1_matchups do %>
          <div class="relative">
            <div class="absolute left-0 top-1/2 w-4 h-px bg-gray-600 -translate-x-full"></div>
            <% connector_height = div(@container_height, @matchups_per_region_r1 * 2) %>
            <%= if rem(matchup.position - List.first(@r1_matchups).position, 2) == 0 do %>
              <div class="absolute left-0 top-1/2 w-px bg-gray-600 -translate-x-[16px]" style={"height: #{connector_height}px;"}></div>
            <% else %>
              <div class="absolute left-0 bottom-1/2 w-px bg-gray-600 -translate-x-[16px]" style={"height: #{connector_height}px;"}></div>
            <% end %>
            <.results_matchup_box
              region={@region_name}
              position={matchup.position}
              contestant_a={matchup.contestant_a}
              contestant_b={matchup.contestant_b}
              matchups_map={@matchups_map}
              contestants_map={@contestants_map}
              size="small"
            />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Results matchup box for R1 (contestants known from seeding)
  # Results matchup box for Round 1 (contestants are passed directly)
  # Expects: region (lowercase string), position (integer)
  defp results_matchup_box(assigns) do
    assigns = Map.put_new(assigns, :size, "normal")

    ~H"""
    <div class={[
      "bg-gray-800 rounded border border-gray-700 overflow-hidden",
      @size == "small" && "w-36",
      @size == "normal" && "w-44"
    ]}>
      <!-- Contestant A -->
      <div class="flex items-center px-2 py-1 border-b border-gray-700">
        <%= if @contestant_a do %>
          <span class="text-xs font-mono w-5 text-gray-500"><%= @contestant_a.seed %></span>
          <span class="text-xs truncate flex-1 text-gray-300"><%= @contestant_a.name %></span>
        <% else %>
          <span class="text-gray-600 text-xs italic">TBD</span>
        <% end %>
      </div>
      <!-- Contestant B -->
      <div class="flex items-center px-2 py-1">
        <%= if @contestant_b do %>
          <span class="text-xs font-mono w-5 text-gray-500"><%= @contestant_b.seed %></span>
          <span class="text-xs truncate flex-1 text-gray-300"><%= @contestant_b.name %></span>
        <% else %>
          <span class="text-gray-600 text-xs italic">TBD</span>
        <% end %>
      </div>
    </div>
    """
  end

  # Results matchup box for later rounds (contestants come from previous matchup winners)
  # Expects: region (lowercase string), round (integer), position (integer)
  defp results_matchup_box_from_matchups(assigns) do
    assigns = Map.put_new(assigns, :size, "normal")
    # Build lookup key from region, round, and position
    key = {String.downcase(assigns[:region] || ""), assigns.round, assigns.position}
    matchup = Map.get(assigns.matchups_map, key)

    contestant_a = if matchup && matchup.contestant_1_id do
      Map.get(assigns.contestants_map, matchup.contestant_1_id)
    end
    contestant_b = if matchup && matchup.contestant_2_id do
      Map.get(assigns.contestants_map, matchup.contestant_2_id)
    end

    assigns = assigns
      |> assign(:contestant_a, contestant_a)
      |> assign(:contestant_b, contestant_b)

    ~H"""
    <div class={[
      "bg-gray-800 rounded border border-gray-700 overflow-hidden",
      @size == "small" && "w-36",
      @size == "normal" && "w-44"
    ]}>
      <!-- Contestant A -->
      <div class="flex items-center px-2 py-1 border-b border-gray-700">
        <%= if @contestant_a do %>
          <span class="text-xs font-mono w-5 text-gray-500"><%= @contestant_a.seed %></span>
          <span class="text-xs truncate flex-1 text-gray-300"><%= @contestant_a.name %></span>
        <% else %>
          <span class="text-gray-600 text-xs italic">TBD</span>
        <% end %>
      </div>
      <!-- Contestant B -->
      <div class="flex items-center px-2 py-1">
        <%= if @contestant_b do %>
          <span class="text-xs font-mono w-5 text-gray-500"><%= @contestant_b.seed %></span>
          <span class="text-xs truncate flex-1 text-gray-300"><%= @contestant_b.name %></span>
        <% else %>
          <span class="text-gray-600 text-xs italic">TBD</span>
        <% end %>
      </div>
    </div>
    """
  end

  # Final Four slot for Results tab
  defp results_final_four_slot(assigns) do
    # Get contestants from source matchups (Elite 8 winners)
    # source_a and source_b are {region, round, position} tuples
    source_a_matchup = Map.get(assigns.matchups_map, assigns.source_a)
    source_b_matchup = Map.get(assigns.matchups_map, assigns.source_b)

    contestant_a = if source_a_matchup && source_a_matchup.winner_id do
      Map.get(assigns.contestants_map, source_a_matchup.winner_id)
    end
    contestant_b = if source_b_matchup && source_b_matchup.winner_id do
      Map.get(assigns.contestants_map, source_b_matchup.winner_id)
    end

    assigns = assigns
      |> assign(:contestant_a, contestant_a)
      |> assign(:contestant_b, contestant_b)

    ~H"""
    <div class="text-center">
      <div class="text-xs text-gray-500 mb-1">Final Four</div>
      <div class="bg-gray-800 rounded border border-gray-700 overflow-hidden">
        <!-- Semifinalist A -->
        <div class="flex items-center px-2 py-1.5 border-b border-gray-700">
          <%= if @contestant_a do %>
            <span class="text-xs font-mono w-5 text-gray-500"><%= @contestant_a.seed %></span>
            <span class="text-xs truncate flex-1 text-white"><%= @contestant_a.name %></span>
          <% else %>
            <span class="text-gray-500 text-xs"><%= @placeholder_a %></span>
          <% end %>
        </div>
        <!-- Semifinalist B -->
        <div class="flex items-center px-2 py-1.5">
          <%= if @contestant_b do %>
            <span class="text-xs font-mono w-5 text-gray-500"><%= @contestant_b.seed %></span>
            <span class="text-xs truncate flex-1 text-white"><%= @contestant_b.name %></span>
          <% else %>
            <span class="text-gray-500 text-xs"><%= @placeholder_b %></span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Championship slot for Results tab
  defp results_championship_slot(assigns) do
    # Final Four matchups: round 5, positions 1 and 2, no region
    ff1_key = {"", 5, assigns.ff1_pos}
    ff2_key = {"", 5, assigns.ff2_pos}

    ff1_matchup = Map.get(assigns.matchups_map, ff1_key)
    ff2_matchup = Map.get(assigns.matchups_map, ff2_key)

    contestant_a = if ff1_matchup && ff1_matchup.winner_id do
      Map.get(assigns.contestants_map, ff1_matchup.winner_id)
    end
    contestant_b = if ff2_matchup && ff2_matchup.winner_id do
      Map.get(assigns.contestants_map, ff2_matchup.winner_id)
    end

    assigns = assigns
      |> assign(:contestant_a, contestant_a)
      |> assign(:contestant_b, contestant_b)

    ~H"""
    <div class="text-center">
      <div class="text-xs text-gray-500 mb-1">Championship</div>
      <div class="bg-gray-800 rounded border border-gray-700 overflow-hidden w-48 mx-auto">
        <!-- Finalist A -->
        <div class="flex items-center px-2 py-1.5 border-b border-gray-700">
          <%= if @contestant_a do %>
            <span class="text-xs font-mono w-5 text-gray-500"><%= @contestant_a.seed %></span>
            <span class="text-xs truncate flex-1 text-white"><%= @contestant_a.name %></span>
          <% else %>
            <span class="text-gray-500 text-xs">Final Four 1 Winner</span>
          <% end %>
        </div>
        <!-- Finalist B -->
        <div class="flex items-center px-2 py-1.5">
          <%= if @contestant_b do %>
            <span class="text-xs font-mono w-5 text-gray-500"><%= @contestant_b.seed %></span>
            <span class="text-xs truncate flex-1 text-white"><%= @contestant_b.name %></span>
          <% else %>
            <span class="text-gray-500 text-xs">Final Four 2 Winner</span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  # Round Completion Reveal Banner with Confetti
  defp round_reveal_banner(assigns) do
    ~H"""
    <!-- Confetti Animation -->
    <div class="confetti-container">
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
    </div>

    <!-- Overlay -->
    <div class="fixed inset-0 bg-black/70 z-50 flex items-center justify-center p-4">
      <!-- Modal Card -->
      <div class="bg-gray-800 rounded-2xl border border-blue-500 shadow-2xl shadow-blue-500/20 max-w-md w-full p-8 text-center relative animate-bounce-in">
        <!-- Close Button -->
        <button
          phx-click="dismiss_reveal"
          class="absolute top-4 right-4 text-gray-400 hover:text-white transition-colors"
        >
          <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>

        <!-- Celebration Icon -->
        <div class="text-6xl mb-4">
          🎉
        </div>

        <!-- Headline -->
        <h2 class="text-2xl font-bold text-white mb-2">
          <%= @round_name %> is Complete!
        </h2>

        <!-- Subtext -->
        <p class="text-gray-300 mb-2">
          View the updated results in the bracket
        </p>

        <!-- Voting Reminder -->
        <p class="text-blue-400 font-medium mb-6">
          Don't forget to vote in the next round!
        </p>

        <!-- CTA Button -->
        <button
          phx-click="dismiss_reveal"
          class="bg-blue-600 hover:bg-blue-700 text-white px-8 py-3 rounded-lg font-semibold text-lg transition-colors inline-flex items-center"
        >
          View Bracket
          <svg class="w-5 h-5 ml-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7l5 5m0 0l-5 5m5-5H6" />
          </svg>
        </button>
      </div>
    </div>
    """
  end

  defp tournament_complete_popup(assigns) do
    # Determine border color and emoji based on placement
    {border_color, emoji, headline} =
      case assigns.rank do
        1 -> {"border-yellow-500", "🥇", "Congratulations!"}
        2 -> {"border-gray-400", "🥈", "Congratulations!"}
        3 -> {"border-amber-600", "🥉", "Congratulations!"}
        _ -> {"border-blue-500", "🎉", "Tournament Complete!"}
      end

    assigns =
      assigns
      |> assign(:border_color, border_color)
      |> assign(:emoji, emoji)
      |> assign(:headline, headline)

    ~H"""
    <!-- Confetti Animation -->
    <div class="confetti-container">
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
      <div class="confetti"></div>
    </div>

    <!-- Overlay -->
    <div class="fixed inset-0 bg-black/70 z-50 flex items-center justify-center p-4">
      <!-- Modal Card -->
      <div class={"bg-gray-800 rounded-2xl border-2 #{@border_color} shadow-2xl max-w-md w-full p-8 text-center relative animate-bounce-in"}>
        <!-- Close Button -->
        <button
          phx-click="dismiss_tournament_complete"
          class="absolute top-4 right-4 text-gray-400 hover:text-white transition-colors"
        >
          <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>

        <!-- Celebration Icon -->
        <div class="text-6xl mb-4">
          <%= @emoji %>
        </div>

        <!-- Headline -->
        <h2 class="text-2xl font-bold text-white mb-2">
          <%= @headline %>
        </h2>

        <!-- Placement -->
        <p class="text-xl text-gray-300 mb-2">
          <%= if @rank do %>
            You finished in <span class="font-bold text-blue-400"><%= ordinal(@rank) %> place</span>!
          <% else %>
            Thanks for watching!
          <% end %>
        </p>

        <!-- Score -->
        <%= if @score do %>
          <p class="text-gray-400 mb-4">
            Final Score: <span class="text-white font-semibold"><%= @score %> points</span>
          </p>
        <% end %>

        <!-- Thank you message -->
        <p class="text-gray-300 mb-6">
          Thank you for participating and we hope to see you at the next tournament!
        </p>

        <!-- CTA Button -->
        <button
          phx-click="dismiss_tournament_complete"
          phx-value-tab="leaderboard"
          class="bg-blue-600 hover:bg-blue-700 text-white px-8 py-3 rounded-lg font-semibold text-lg transition-colors inline-flex items-center"
        >
          View Leaderboard
          <svg class="w-5 h-5 ml-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7l5 5m0 0l-5 5m5-5H6" />
          </svg>
        </button>
      </div>
    </div>
    """
  end

  defp ordinal(1), do: "1st"
  defp ordinal(2), do: "2nd"
  defp ordinal(3), do: "3rd"
  defp ordinal(n) when n >= 4 and n <= 20, do: "#{n}th"
  defp ordinal(n) do
    case rem(n, 10) do
      1 -> "#{n}st"
      2 -> "#{n}nd"
      3 -> "#{n}rd"
      _ -> "#{n}th"
    end
  end

  # Event Handlers
  @impl true
  def handle_event("toggle_mobile_menu", _, socket) do
    {:noreply, assign(socket, show_mobile_menu: !socket.assigns.show_mobile_menu)}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, tab: tab)}
  end

  # Select a vote locally (doesn't save to database yet)
  def handle_event("select_vote", %{"matchup" => matchup_id, "contestant" => contestant_id}, socket) do
    if socket.assigns.current_user && socket.assigns.has_bracket do
      # Keep IDs as strings (UUIDs), reset submitted state when changing votes
      pending_votes = Map.put(socket.assigns.pending_votes, matchup_id, contestant_id)
      {:noreply, assign(socket, pending_votes: pending_votes, submitted: false)}
    else
      {:noreply, put_flash(socket, :error, "You must have a submitted bracket to vote")}
    end
  end

  # Submit all pending votes to the database
  def handle_event("submit_votes", _params, socket) do
    if socket.assigns.current_user && socket.assigns.has_bracket do
      user_id = socket.assigns.current_user.id
      pending_votes = socket.assigns.pending_votes

      # Cast each vote
      results = Enum.map(pending_votes, fn {matchup_id, contestant_id} ->
        Voting.cast_vote(matchup_id, user_id, contestant_id)
      end)

      # Check for errors
      errors = Enum.filter(results, fn
        {:error, _} -> true
        _ -> false
      end)

      if Enum.empty?(errors) do
        # Reload matchups to show updated vote counts
        matchups =
          Tournaments.get_active_matchups(socket.assigns.tournament.id)
          |> load_vote_counts()
          |> load_user_votes(socket.assigns.current_user)

        {:noreply,
         socket
         |> assign(active_matchups: matchups, submitted: true)
         |> put_flash(:info, "Votes submitted successfully!")}
      else
        {:noreply, put_flash(socket, :error, "Some votes could not be saved. Please try again.")}
      end
    else
      {:noreply, put_flash(socket, :error, "You must have a submitted bracket to vote")}
    end
  end

  def handle_event("send_message", %{"content" => content}, socket) do
    if socket.assigns.current_user && String.trim(content) != "" do
      case Chat.send_message(socket.assigns.tournament.id, socket.assigns.current_user.id, content) do
        {:ok, _message} ->
          {:noreply, assign(socket, message_input: "")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not send message")}
      end
    else
      {:noreply, socket}
    end
  end

  # Dismiss round reveal banner and navigate to bracket tab
  def handle_event("dismiss_reveal", _, socket) do
    {:noreply,
     socket
     |> assign(show_round_reveal: false)
     |> assign(tab: "bracket")}
  end

  # Dismiss tournament complete popup and navigate to leaderboard tab
  def handle_event("dismiss_tournament_complete", %{"tab" => tab}, socket) do
    {:noreply,
     socket
     |> assign(show_tournament_complete: false)
     |> assign(tab: tab)}
  end

  def handle_event("dismiss_tournament_complete", _, socket) do
    {:noreply, assign(socket, show_tournament_complete: false)}
  end

  # PubSub Handlers
  @impl true
  def handle_info({:vote_cast, %{matchup_id: _, counts: _}}, socket) do
    # Reload matchups with new vote counts
    matchups =
      Tournaments.get_active_matchups(socket.assigns.tournament.id)
      |> load_vote_counts()
      |> load_user_votes(socket.assigns.current_user)

    {:noreply, assign(socket, active_matchups: matchups)}
  end

  def handle_info({:matchup_updated, _matchup}, socket) do
    all_matchups = Tournaments.get_all_matchups(socket.assigns.tournament.id)
    active_matchups =
      Tournaments.get_active_matchups(socket.assigns.tournament.id)
      |> load_vote_counts()
      |> load_user_votes(socket.assigns.current_user)

    {:noreply, assign(socket, all_matchups: all_matchups, active_matchups: active_matchups)}
  end

  def handle_info({:tournament_updated, tournament}, socket) do
    # Preload contestants for bracket display
    tournament = BracketBattle.Repo.preload(tournament, :contestants)
    socket = assign(socket, tournament: tournament)

    # Show tournament complete popup when tournament ends
    socket =
      if tournament.status == "completed" and socket.assigns.current_user do
        user_id = socket.assigns.current_user.id
        rank = Brackets.get_user_rank(tournament.id, user_id)
        bracket = Brackets.get_user_bracket(tournament.id, user_id)

        assign(socket,
          show_tournament_complete: true,
          user_final_rank: rank,
          user_final_score: bracket && bracket.total_score
        )
      else
        socket
      end

    {:noreply, socket}
  end

  # Handle round completion event - show celebration banner
  def handle_info({:round_completed, %{round: round, round_name: round_name}}, socket) do
    # Also reload matchups since the bracket has changed
    all_matchups = Tournaments.get_all_matchups(socket.assigns.tournament.id)
    active_matchups =
      Tournaments.get_active_matchups(socket.assigns.tournament.id)
      |> load_vote_counts()
      |> load_user_votes(socket.assigns.current_user)

    {:noreply,
     socket
     |> assign(show_round_reveal: true)
     |> assign(round_completed: round)
     |> assign(completed_round_name: round_name)
     |> assign(all_matchups: all_matchups)
     |> assign(active_matchups: active_matchups)}
  end

  def handle_info({:phase_completed, %{phase_name: phase_name, new_region: _new_region, new_round: _new_round}}, socket) do
    # Reload tournament to get updated region/round state
    tournament = Tournaments.get_tournament!(socket.assigns.tournament.id)
    all_matchups = Tournaments.get_all_matchups(tournament.id)
    active_matchups =
      Tournaments.get_active_matchups(tournament.id)
      |> load_vote_counts()
      |> load_user_votes(socket.assigns.current_user)

    # Reset pending votes for new phase
    pending_votes = active_matchups
      |> Enum.filter(fn m -> Map.get(m, :user_vote) end)
      |> Enum.map(fn m -> {to_string(m.id), to_string(m.user_vote.contestant_id)} end)
      |> Enum.into(%{})

    {:noreply,
     socket
     |> assign(tournament: tournament)
     |> assign(show_round_reveal: true)
     |> assign(completed_round_name: phase_name)
     |> assign(all_matchups: all_matchups)
     |> assign(active_matchups: active_matchups)
     |> assign(pending_votes: pending_votes)
     |> assign(submitted: false)}
  end

  def handle_info({:new_message, message}, socket) do
    messages = [message | socket.assigns.messages] |> Enum.take(50)
    {:noreply, assign(socket, messages: messages)}
  end

  def handle_info(:tick, socket) do
    # Force re-render for countdown timers
    {:noreply, socket}
  end

  def handle_info({:leaderboard_updated, _tournament_id}, socket) do
    leaderboard = Brackets.get_leaderboard(socket.assigns.tournament.id, limit: 50)
    {:noreply, assign(socket, leaderboard: leaderboard)}
  end

  def handle_info(_, socket), do: {:noreply, socket}

  # Helpers
  defp status_color("draft"), do: "bg-gray-600 text-gray-200"
  defp status_color("registration"), do: "bg-blue-600 text-blue-100"
  defp status_color("active"), do: "bg-green-600 text-green-100"
  defp status_color("completed"), do: "bg-blue-600 text-blue-100"
  defp status_color(_), do: "bg-gray-600 text-gray-200"

  defp status_label("draft"), do: "Coming Soon"
  defp status_label("registration"), do: "Registration Open"
  defp status_label("active"), do: "In Progress"
  defp status_label("completed"), do: "Completed"
  defp status_label(_), do: "Unknown"

  defp rank_color(1), do: "text-yellow-400"
  defp rank_color(2), do: "text-gray-300"
  defp rank_color(3), do: "text-amber-600"
  defp rank_color(_), do: "text-gray-400"

  defp format_countdown(seconds) when seconds < 60 do
    "#{seconds}s"
  end
  defp format_countdown(seconds) when seconds < 3600 do
    "#{div(seconds, 60)}m"
  end
  defp format_countdown(seconds) do
    hours = div(seconds, 3600)
    mins = div(rem(seconds, 3600), 60)
    "#{hours}h #{mins}m"
  end

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%I:%M %p")
  end

  # Check if a contestant is selected (handles nil and string comparison)
  defp is_selected(nil, _), do: false
  defp is_selected(selected, contestant_id) do
    to_string(selected) == to_string(contestant_id)
  end
end
