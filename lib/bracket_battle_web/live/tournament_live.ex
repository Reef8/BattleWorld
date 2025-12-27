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

    tournament = Tournaments.get_tournament!(tournament_id)

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

    # Get recent chat messages
    messages = Chat.get_messages(tournament_id, limit: 50)

    # Get leaderboard
    leaderboard = Brackets.get_leaderboard(tournament_id, limit: 50)

    # Build pending_votes from existing user votes (using string keys for consistency)
    pending_votes = active_matchups
      |> Enum.filter(fn m -> m.user_vote end)
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
       messages: messages,
       leaderboard: leaderboard,
       message_input: "",
       tab: "bracket",
       pending_votes: pending_votes,
       submitted: false,
       # Round completion reveal state
       show_round_reveal: false,
       round_completed: nil,
       completed_round_name: nil
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

    <div class="min-h-screen bg-gray-900">
      <!-- Header -->
      <header class="bg-gray-800 border-b border-gray-700 sticky top-0 z-10">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between items-center h-16">
            <div class="flex items-center space-x-4">
              <a href="/" class="text-gray-400 hover:text-white text-sm">&larr; Home</a>
              <h1 class="text-xl font-bold text-white"><%= @tournament.name %></h1>
              <span class={"px-2 py-1 rounded text-xs font-medium #{status_color(@tournament.status)}"}>
                <%= status_label(@tournament.status) %>
              </span>
            </div>
            <div class="flex items-center space-x-4">
              <%= if @current_user do %>
                <%= if @tournament.status == "registration" do %>
                  <a href={"/tournament/#{@tournament.id}/bracket"} class="bg-purple-600 hover:bg-purple-700 text-white px-4 py-2 rounded text-sm">
                    <%= if @has_bracket, do: "View Bracket", else: "Fill Bracket" %>
                  </a>
                <% end %>
                <span class="text-gray-400 text-sm"><%= @current_user.display_name || @current_user.email %></span>
              <% else %>
                <a href="/auth/signin" class="bg-purple-600 hover:bg-purple-700 text-white px-4 py-2 rounded text-sm">
                  Sign In
                </a>
              <% end %>
            </div>
          </div>
        </div>
      </header>

      <!-- Tab Navigation -->
      <div class="bg-gray-800 border-b border-gray-700">
        <div class="max-w-7xl mx-auto px-4">
          <nav class="flex space-x-4">
            <button
              phx-click="switch_tab"
              phx-value-tab="bracket"
              class={"px-4 py-3 text-sm font-medium border-b-2 transition-colors #{if @tab == "bracket", do: "border-purple-500 text-white", else: "border-transparent text-gray-400 hover:text-white"}"}
            >
              Bracket
            </button>
            <%= if @tournament.status == "active" do %>
              <button
                phx-click="switch_tab"
                phx-value-tab="voting"
                class={"px-4 py-3 text-sm font-medium border-b-2 transition-colors #{if @tab == "voting", do: "border-purple-500 text-white", else: "border-transparent text-gray-400 hover:text-white"}"}
              >
                Vote
                <%= if length(@active_matchups) > 0 and map_size(@pending_votes) < length(@active_matchups) do %>
                  <span class="ml-1 bg-purple-600 text-white text-xs px-2 py-0.5 rounded-full">
                    <%= length(@active_matchups) - map_size(@pending_votes) %>
                  </span>
                <% end %>
              </button>
            <% end %>
            <button
              phx-click="switch_tab"
              phx-value-tab="leaderboard"
              class={"px-4 py-3 text-sm font-medium border-b-2 transition-colors #{if @tab == "leaderboard", do: "border-purple-500 text-white", else: "border-transparent text-gray-400 hover:text-white"}"}
            >
              Leaderboard
            </button>
            <button
              phx-click="switch_tab"
              phx-value-tab="chat"
              class={"px-4 py-3 text-sm font-medium border-b-2 transition-colors #{if @tab == "chat", do: "border-purple-500 text-white", else: "border-transparent text-gray-400 hover:text-white"}"}
            >
              Chat
            </button>
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
             class="inline-block bg-purple-600 hover:bg-purple-700 text-white px-6 py-3 rounded-lg font-medium transition-colors">
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
    # Group matchups by round and region
    by_round = Enum.group_by(assigns.matchups, & &1.round)

    # Get region names from tournament (default to standard names)
    region_names = assigns.tournament.region_names || ["East", "West", "South", "Midwest"]
    [region_1, region_2, region_3, region_4] = Enum.take(region_names, 4)

    # Separate matchups by region for rounds 1-4
    region_1_matchups = get_region_matchups(assigns.matchups, region_1)
    region_2_matchups = get_region_matchups(assigns.matchups, region_2)
    region_3_matchups = get_region_matchups(assigns.matchups, region_3)
    region_4_matchups = get_region_matchups(assigns.matchups, region_4)

    # Final Four and Championship (rounds 5-6)
    final_four = Map.get(by_round, 5, []) |> Enum.sort_by(& &1.position)
    championship = Map.get(by_round, 6, []) |> Enum.sort_by(& &1.position)

    # Get user picks (already set by bracket_tab)
    user_picks = Map.get(assigns, :user_picks, %{})

    assigns = assigns
      |> assign(:region_names, region_names)
      |> assign(:region_1_matchups, region_1_matchups)
      |> assign(:region_2_matchups, region_2_matchups)
      |> assign(:region_3_matchups, region_3_matchups)
      |> assign(:region_4_matchups, region_4_matchups)
      |> assign(:final_four, final_four)
      |> assign(:championship, championship)
      |> assign(:user_picks, user_picks)

    ~H"""
    <div class="space-y-4">
      <div class="text-center mb-4">
        <h2 class="text-2xl font-bold text-white">Tournament Bracket</h2>
        <p class="text-gray-400 text-sm">
          <%= if @tournament.status == "active" do %>
            Round <%= @tournament.current_round %> in progress
          <% else %>
            <%= status_label(@tournament.status) %>
          <% end %>
        </p>
      </div>

      <!-- ESPN-Style Bracket Layout -->
      <div class="overflow-x-auto pb-4">
        <div class="min-w-[1400px]">
          <!-- Top Half: Region 1 (left) and Region 2 (right) -->
          <div class="flex">
            <!-- REGION 1 - flows left to right -->
            <div class="flex-1">
              <div class="text-center mb-3">
                <span class="text-purple-400 font-bold text-lg uppercase tracking-wider"><%= Enum.at(@region_names, 0) %></span>
              </div>
              <.region_bracket_left matchups={@region_1_matchups} user_picks={@user_picks} />
            </div>

            <!-- CENTER COLUMN - Final Four Top + Championship -->
            <div class="w-72 flex flex-col items-center justify-end px-4">
              <!-- Final Four Game 1 (Region 1 vs Region 2 winners) -->
              <%= if length(@final_four) > 0 do %>
                <div class="mb-2">
                  <div class="text-center text-xs text-gray-500 mb-1">Final Four</div>
                  <.bracket_matchup_box matchup={Enum.at(@final_four, 0)} user_picks={@user_picks} />
                </div>
              <% end %>
            </div>

            <!-- REGION 2 - flows right to left -->
            <div class="flex-1">
              <div class="text-center mb-3">
                <span class="text-purple-400 font-bold text-lg uppercase tracking-wider"><%= Enum.at(@region_names, 1) %></span>
              </div>
              <.region_bracket_right matchups={@region_2_matchups} user_picks={@user_picks} />
            </div>
          </div>

          <!-- Championship in Center - uses relative/absolute positioning to align with Final Four -->
          <div class="relative my-6" style="height: 80px;">
            <div class="absolute left-[56.5%] -translate-x-1/2">
              <div class="w-72 flex items-center justify-center px-4">
                <div class="text-center">
                  <div class="text-xs text-yellow-500 font-bold mb-1 uppercase">Championship</div>
                  <%= if length(@championship) > 0 do %>
                    <.bracket_matchup_box matchup={Enum.at(@championship, 0)} highlight={true} user_picks={@user_picks} />
                  <% end %>
                </div>
              </div>
            </div>
          </div>

          <!-- Bottom Half: Region 3 (left) and Region 4 (right) -->
          <div class="flex">
            <!-- REGION 3 - flows left to right -->
            <div class="flex-1">
              <div class="text-center mb-3">
                <span class="text-purple-400 font-bold text-lg uppercase tracking-wider"><%= Enum.at(@region_names, 2) %></span>
              </div>
              <.region_bracket_left matchups={@region_3_matchups} user_picks={@user_picks} />
            </div>

            <!-- CENTER COLUMN - Final Four Bottom -->
            <div class="w-72 flex flex-col items-center justify-start px-4">
              <!-- Final Four Game 2 (Region 3 vs Region 4 winners) -->
              <%= if length(@final_four) > 1 do %>
                <div class="mt-2">
                  <div class="text-center text-xs text-gray-500 mb-1">Final Four</div>
                  <.bracket_matchup_box matchup={Enum.at(@final_four, 1)} user_picks={@user_picks} />
                </div>
              <% end %>
            </div>

            <!-- REGION 4 - flows right to left -->
            <div class="flex-1">
              <div class="text-center mb-3">
                <span class="text-purple-400 font-bold text-lg uppercase tracking-wider"><%= Enum.at(@region_names, 3) %></span>
              </div>
              <.region_bracket_right matchups={@region_4_matchups} user_picks={@user_picks} />
            </div>
          </div>
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
  defp region_bracket_left(assigns) do
    ~H"""
    <div class="flex items-center">
      <!-- Round 1 (8 matchups) -->
      <div class="flex flex-col justify-around" style="min-height: 640px;">
        <%= for {matchup, idx} <- Enum.with_index(Map.get(@matchups, 1, [])) do %>
          <div class="relative">
            <.bracket_matchup_box matchup={matchup} size="small" user_picks={@user_picks} />
            <!-- Horizontal line to connector -->
            <div class="absolute right-0 top-1/2 w-4 h-px bg-gray-600 translate-x-full"></div>
            <!-- Vertical connector: pairs connect (0-1, 2-3, 4-5, 6-7) -->
            <%= if rem(idx, 2) == 0 do %>
              <!-- Top of pair - line goes down -->
              <div class="absolute right-0 top-1/2 w-px bg-gray-600 translate-x-[calc(100%+16px)]" style="height: 40px;"></div>
            <% else %>
              <!-- Bottom of pair - line goes up -->
              <div class="absolute right-0 bottom-1/2 w-px bg-gray-600 translate-x-[calc(100%+16px)]" style="height: 40px;"></div>
            <% end %>
          </div>
        <% end %>
      </div>

      <!-- Connector column R1->R2 -->
      <div class="w-4"></div>

      <!-- Round 2 (4 matchups) -->
      <div class="flex flex-col justify-around" style="min-height: 640px;">
        <%= for {matchup, idx} <- Enum.with_index(Map.get(@matchups, 2, [])) do %>
          <div class="relative">
            <.bracket_matchup_box matchup={matchup} size="small" user_picks={@user_picks} />
            <!-- Horizontal line to next connector -->
            <div class="absolute right-0 top-1/2 w-4 h-px bg-gray-600 translate-x-full"></div>
            <!-- Vertical connector for pairs -->
            <%= if rem(idx, 2) == 0 do %>
              <div class="absolute right-0 top-1/2 w-px bg-gray-600 translate-x-[calc(100%+16px)]" style="height: 80px;"></div>
            <% else %>
              <div class="absolute right-0 bottom-1/2 w-px bg-gray-600 translate-x-[calc(100%+16px)]" style="height: 80px;"></div>
            <% end %>
          </div>
        <% end %>
      </div>

      <!-- Connector column R2->R3 -->
      <div class="w-4"></div>

      <!-- Sweet 16 (2 matchups) -->
      <div class="flex flex-col justify-around" style="min-height: 640px;">
        <%= for {matchup, idx} <- Enum.with_index(Map.get(@matchups, 3, [])) do %>
          <div class="relative">
            <.bracket_matchup_box matchup={matchup} user_picks={@user_picks} />
            <div class="absolute right-0 top-1/2 w-4 h-px bg-gray-600 translate-x-full"></div>
            <!-- Vertical connector for pair -->
            <%= if rem(idx, 2) == 0 do %>
              <div class="absolute right-0 top-1/2 w-px bg-gray-600 translate-x-[calc(100%+16px)]" style="height: 160px;"></div>
            <% else %>
              <div class="absolute right-0 bottom-1/2 w-px bg-gray-600 translate-x-[calc(100%+16px)]" style="height: 160px;"></div>
            <% end %>
          </div>
        <% end %>
      </div>

      <!-- Connector column R3->R4 -->
      <div class="w-4"></div>

      <!-- Elite 8 (1 matchup) -->
      <div class="flex flex-col justify-center" style="min-height: 640px;">
        <%= for matchup <- Map.get(@matchups, 4, []) do %>
          <div class="relative">
            <.bracket_matchup_box matchup={matchup} user_picks={@user_picks} />
            <!-- No line on right - this connects to Final Four in center -->
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Right-side region bracket (West, Midwest) - flows right to left
  defp region_bracket_right(assigns) do
    ~H"""
    <div class="flex items-center justify-end">
      <!-- Elite 8 (1 matchup) -->
      <div class="flex flex-col justify-center" style="min-height: 640px;">
        <%= for matchup <- Map.get(@matchups, 4, []) do %>
          <div class="relative">
            <!-- No line on left - this connects to Final Four in center -->
            <.bracket_matchup_box matchup={matchup} user_picks={@user_picks} />
          </div>
        <% end %>
      </div>

      <!-- Connector column R4<-R3 -->
      <div class="w-4"></div>

      <!-- Sweet 16 (2 matchups) -->
      <div class="flex flex-col justify-around" style="min-height: 640px;">
        <%= for {matchup, idx} <- Enum.with_index(Map.get(@matchups, 3, [])) do %>
          <div class="relative">
            <!-- Horizontal line to next connector (toward Elite 8) -->
            <div class="absolute left-0 top-1/2 w-4 h-px bg-gray-600 -translate-x-full"></div>
            <!-- Vertical connector for pair -->
            <%= if rem(idx, 2) == 0 do %>
              <div class="absolute left-0 top-1/2 w-px bg-gray-600 -translate-x-[16px]" style="height: 160px;"></div>
            <% else %>
              <div class="absolute left-0 bottom-1/2 w-px bg-gray-600 -translate-x-[16px]" style="height: 160px;"></div>
            <% end %>
            <.bracket_matchup_box matchup={matchup} user_picks={@user_picks} />
          </div>
        <% end %>
      </div>

      <!-- Connector column R3<-R2 -->
      <div class="w-4"></div>

      <!-- Round 2 (4 matchups) -->
      <div class="flex flex-col justify-around" style="min-height: 640px;">
        <%= for {matchup, idx} <- Enum.with_index(Map.get(@matchups, 2, [])) do %>
          <div class="relative">
            <!-- Horizontal line to next connector (toward Sweet 16) -->
            <div class="absolute left-0 top-1/2 w-4 h-px bg-gray-600 -translate-x-full"></div>
            <!-- Vertical connector for pairs -->
            <%= if rem(idx, 2) == 0 do %>
              <div class="absolute left-0 top-1/2 w-px bg-gray-600 -translate-x-[16px]" style="height: 80px;"></div>
            <% else %>
              <div class="absolute left-0 bottom-1/2 w-px bg-gray-600 -translate-x-[16px]" style="height: 80px;"></div>
            <% end %>
            <.bracket_matchup_box matchup={matchup} size="small" user_picks={@user_picks} />
          </div>
        <% end %>
      </div>

      <!-- Connector column R2<-R1 -->
      <div class="w-4"></div>

      <!-- Round 1 (8 matchups) -->
      <div class="flex flex-col justify-around" style="min-height: 640px;">
        <%= for {matchup, idx} <- Enum.with_index(Map.get(@matchups, 1, [])) do %>
          <div class="relative">
            <.bracket_matchup_box matchup={matchup} size="small" user_picks={@user_picks} />
            <!-- Horizontal line to connector (toward Round 2) -->
            <div class="absolute left-0 top-1/2 w-4 h-px bg-gray-600 -translate-x-full"></div>
            <!-- Vertical connector: pairs connect (0-1, 2-3, 4-5, 6-7) -->
            <%= if rem(idx, 2) == 0 do %>
              <!-- Top of pair - line goes down -->
              <div class="absolute left-0 top-1/2 w-px bg-gray-600 -translate-x-[16px]" style="height: 40px;"></div>
            <% else %>
              <!-- Bottom of pair - line goes up -->
              <div class="absolute left-0 bottom-1/2 w-px bg-gray-600 -translate-x-[16px]" style="height: 40px;"></div>
            <% end %>
          </div>
        <% end %>
      </div>
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
          <a href={"/tournament/#{@tournament.id}/bracket"} class="bg-purple-600 hover:bg-purple-700 text-white px-6 py-2 rounded">
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
            <h2 class="text-xl font-bold text-white">Vote on Round <%= @tournament.current_round %></h2>
            <p class="text-gray-400 text-sm">Click on the contestant you think should win</p>
          </div>

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
                  @votes_cast > 0 && "bg-purple-600 hover:bg-purple-700 text-white cursor-pointer",
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
            is_selected(@selected, @matchup.contestant_1_id) && "bg-purple-600 ring-2 ring-purple-400 scale-[1.02]",
            !is_selected(@selected, @matchup.contestant_1_id) && "bg-gray-700 hover:bg-gray-600"
          ]}
        >
          <div class="flex justify-between items-center mb-1">
            <span class="text-white text-sm">
              <span class="text-gray-400"><%= @matchup.contestant_1.seed %>.</span>
              <%= @matchup.contestant_1.name %>
            </span>
            <%= if is_selected(@selected, @matchup.contestant_1_id) do %>
              <span class="text-white font-bold text-xs">SELECTED</span>
            <% else %>
              <span class="text-gray-400 text-sm"><%= @c1_pct %>%</span>
            <% end %>
          </div>
          <div class="w-full bg-gray-600 rounded-full h-1.5">
            <div class="bg-purple-500 h-1.5 rounded-full transition-all" style={"width: #{@c1_pct}%"}></div>
          </div>
        </button>

        <!-- Contestant 2 -->
        <button
          phx-click="select_vote"
          phx-value-matchup={@matchup.id}
          phx-value-contestant={@matchup.contestant_2_id}
          class={[
            "w-full text-left p-3 rounded transition-all duration-200",
            is_selected(@selected, @matchup.contestant_2_id) && "bg-purple-600 ring-2 ring-purple-400 scale-[1.02]",
            !is_selected(@selected, @matchup.contestant_2_id) && "bg-gray-700 hover:bg-gray-600"
          ]}
        >
          <div class="flex justify-between items-center mb-1">
            <span class="text-white text-sm">
              <span class="text-gray-400"><%= @matchup.contestant_2.seed %>.</span>
              <%= @matchup.contestant_2.name %>
            </span>
            <%= if is_selected(@selected, @matchup.contestant_2_id) do %>
              <span class="text-white font-bold text-xs">SELECTED</span>
            <% else %>
              <span class="text-gray-400 text-sm"><%= @c2_pct %>%</span>
            <% end %>
          </div>
          <div class="w-full bg-gray-600 rounded-full h-1.5">
            <div class="bg-purple-500 h-1.5 rounded-full transition-all" style={"width: #{@c2_pct}%"}></div>
          </div>
        </button>
      </div>

      <!-- Footer -->
      <div class="px-3 py-2 bg-gray-750 border-t border-gray-700 text-center">
        <span class="text-gray-500 text-xs"><%= @total %> votes</span>
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
        <div class="bg-gray-800 rounded-lg border border-gray-700 overflow-hidden">
          <table class="w-full">
            <thead>
              <tr class="border-b border-gray-700 bg-gray-750">
                <th class="text-left text-gray-400 text-sm font-medium px-4 py-3 w-16">Rank</th>
                <th class="text-left text-gray-400 text-sm font-medium px-4 py-3">Player</th>
                <th class="text-right text-gray-400 text-sm font-medium px-4 py-3">Points</th>
                <th class="text-right text-gray-400 text-sm font-medium px-4 py-3">Correct</th>
              </tr>
            </thead>
            <tbody>
              <%= for entry <- @leaderboard do %>
                <tr class="border-b border-gray-700 last:border-0 hover:bg-gray-750">
                  <td class="px-4 py-3">
                    <span class={"font-bold #{rank_color(entry.rank)}"}><%= entry.rank %></span>
                  </td>
                  <td class="px-4 py-3 text-white">
                    <%= entry.user.display_name || entry.user.email %>
                  </td>
                  <td class="px-4 py-3 text-right text-purple-400 font-bold">
                    <%= entry.total_score %>
                  </td>
                  <td class="px-4 py-3 text-right text-gray-400">
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
                    <span class="text-purple-400 text-sm font-medium">
                      <%= message.user.display_name || message.user.email %>
                    </span>
                    <span class="text-gray-600 text-xs">
                      <%= format_time(message.inserted_at) %>
                    </span>
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
                class="flex-1 bg-gray-700 border-gray-600 text-white rounded px-3 py-2 text-sm focus:ring-purple-500 focus:border-purple-500"
                autocomplete="off"
              />
              <button
                type="submit"
                class="bg-purple-600 hover:bg-purple-700 text-white px-4 py-2 rounded text-sm"
              >
                Send
              </button>
            </div>
          </form>
        <% else %>
          <div class="border-t border-gray-700 p-4 text-center">
            <a href="/auth/signin" class="text-purple-400 hover:text-purple-300 text-sm">
              Sign in to chat
            </a>
          </div>
        <% end %>
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
      <div class="bg-gray-800 rounded-2xl border border-purple-500 shadow-2xl shadow-purple-500/20 max-w-md w-full p-8 text-center relative animate-bounce-in">
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
        <p class="text-purple-400 font-medium mb-6">
          Don't forget to vote in the next round!
        </p>

        <!-- CTA Button -->
        <button
          phx-click="dismiss_reveal"
          class="bg-purple-600 hover:bg-purple-700 text-white px-8 py-3 rounded-lg font-semibold text-lg transition-colors inline-flex items-center"
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

  # Event Handlers
  @impl true
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
    {:noreply, assign(socket, tournament: tournament)}
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
  defp status_color("completed"), do: "bg-purple-600 text-purple-100"
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
