defmodule BracketBattleWeb.HomeLive do
  use BracketBattleWeb, :live_view

  alias BracketBattle.Accounts
  alias BracketBattle.Brackets
  alias BracketBattle.Tournaments
  alias BracketBattle.Voting

  @impl true
  def mount(_params, session, socket) do
    user = if user_id = session["user_id"] do
      Accounts.get_user(user_id)
    end

    # Get active tournament, or fall back to most recently completed one
    tournament = Tournaments.get_active_tournament() || Tournaments.get_latest_completed_tournament()

    has_voted = if user && tournament && tournament.status == "active" do
      Voting.has_voted_in_round?(tournament.id, user.id, tournament.current_round)
    else
      false
    end

    # Load matchups for ticker when tournament is active
    matchups = if tournament && tournament.status == "active" do
      load_ticker_matchups(tournament)
    else
      []
    end

    # Extract voting end time from first matchup (all matchups in a round share the same end time)
    voting_ends_at = if matchups != [], do: hd(matchups).voting_ends_at, else: nil

    # Check if user participated in a completed tournament
    {user_final_rank, user_final_score} =
      if user && tournament && tournament.status == "completed" do
        bracket = Brackets.get_user_bracket(tournament.id, user.id)
        if bracket do
          rank = Brackets.get_user_rank(tournament.id, user.id)
          {rank, bracket.total_score}
        else
          {nil, nil}
        end
      else
        {nil, nil}
      end

    {:ok,
     assign(socket,
       current_user: user,
       tournament: tournament,
       has_voted: has_voted,
       matchups: matchups,
       voting_ends_at: voting_ends_at,
       page_title: "BracketBattle",
       show_tournament_start: false,
       show_tournament_complete: false,
       show_welcome_splash: false,
       show_mobile_menu: false,
       user_final_rank: user_final_rank,
       user_final_score: user_final_score
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <!-- Welcome Splash for first-time visitors -->
    <div id="welcome-splash-check" phx-hook="WelcomeSplash" class="hidden"></div>
    <%= if @show_welcome_splash do %>
      <.welcome_splash />
    <% end %>

    <!-- Tournament Start Check (localStorage hook) -->
    <%= if @tournament && @tournament.status == "active" && @tournament.current_round == 1 do %>
      <div id="tournament-start-check"
           phx-hook="TournamentStartReveal"
           data-tournament-id={@tournament.id}
           class="hidden">
      </div>
    <% end %>

    <!-- Tournament Start Reveal Banner -->
    <%= if @show_tournament_start do %>
      <.tournament_start_banner tournament={@tournament} />
    <% end %>

    <!-- Tournament Complete Check (localStorage hook) -->
    <%= if @tournament && @tournament.status == "completed" && @current_user && @user_final_rank do %>
      <div id="tournament-complete-check"
           phx-hook="TournamentCompleteReveal"
           data-tournament-id={@tournament.id}
           class="hidden">
      </div>
    <% end %>

    <!-- Tournament Complete Popup -->
    <%= if @show_tournament_complete do %>
      <.tournament_complete_popup
        tournament={@tournament}
        rank={@user_final_rank}
        score={@user_final_score}
      />
    <% end %>

    <!-- Live Matchups Ticker - Full width at very top -->
    <%= if @tournament do %>
      <div class="ticker-container">
        <%= if @tournament.status == "active" && length(@matchups) > 0 do %>
          <!-- Active tournament: show matchups -->
          <div class="ticker-label">
            <span class="live-dot"></span>
            LIVE MATCHUPS
          </div>
          <div class="ticker-track">
            <div class="ticker-content">
              <%= for matchup <- @matchups ++ @matchups do %>
                <.ticker_matchup matchup={matchup} has_voted={@has_voted} />
              <% end %>
            </div>
          </div>
        <% else %>
          <%= if @tournament.status == "registration" do %>
            <!-- Registration: show countdown message -->
            <div class="ticker-label">
              <span class="countdown-icon">⏱</span>
              COMING SOON
            </div>
            <div class="ticker-track">
              <div class="ticker-content">
                <%= for _ <- 1..3 do %>
                  <div class="ticker-countdown-msg">
                    🏆 <%= @tournament.name %> • Voting starts soon • Fill out your bracket now!
                  </div>
                <% end %>
              </div>
            </div>
          <% end %>
        <% end %>
      </div>
    <% end %>

    <div class="min-h-screen bg-gradient-to-b from-[#0a1628] via-[#1e3a5f] to-[#0d2137] relative overflow-hidden">
      <!-- Ambient bubbles -->
      <div class="ambient-bubbles">
        <div class="ambient-bubble"></div>
        <div class="ambient-bubble"></div>
        <div class="ambient-bubble"></div>
        <div class="ambient-bubble"></div>
        <div class="ambient-bubble"></div>
        <div class="ambient-bubble"></div>
        <div class="ambient-bubble"></div>
        <div class="ambient-bubble"></div>
      </div>

      <!-- Header -->
      <header class="border-b border-gray-800">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between items-center h-16">
            <div class="flex items-center">
              <h1 class="text-2xl font-bold text-white">Minnows</h1>
            </div>

            <!-- Desktop nav -->
            <nav class="hidden md:flex items-center space-x-4">
              <%= if @current_user do %>
                <%= if @current_user.is_admin do %>
                  <a href="/admin" class="text-blue-400 hover:text-blue-300 text-sm">
                    Admin
                  </a>
                <% end %>
                <a href="/dashboard" class="text-gray-400 hover:text-white text-sm">
                  <%= @current_user.display_name || @current_user.email %>
                </a>
                <a href="/auth/signout" class="text-gray-400 hover:text-white text-sm">
                  Sign Out
                </a>
              <% else %>
                <a href="/auth/signin" class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors">
                  Sign In
                </a>
              <% end %>
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
          <div class="md:hidden border-t border-gray-800 bg-gray-900">
            <div class="px-4 py-3 space-y-2">
              <%= if @current_user do %>
                <%= if @current_user.is_admin do %>
                  <a href="/admin" class="block py-2 text-blue-400 hover:text-blue-300">
                    Admin
                  </a>
                <% end %>
                <a href="/dashboard" class="block py-2 text-gray-400 hover:text-white">
                  <%= @current_user.display_name || @current_user.email %>
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

      <!-- Main Content -->
      <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 sm:py-12">
        <div class="text-center">
          <!-- Hero Section -->
          <div class="mb-8 sm:mb-12">
            <h2 class="text-4xl sm:text-5xl md:text-6xl font-extrabold text-white mb-3 sm:mb-4">
              <span class="text-blue-400">Minnows</span>
            </h2>
            <p class="text-lg sm:text-xl md:text-2xl text-gray-300 font-medium mb-2">
              In a sea of minnows, be the shark
            </p>
            <p class="text-base sm:text-lg md:text-xl text-gray-400 max-w-2xl mx-auto px-2">
              Create brackets, vote on matchups, talk smack in the chat, and compete on the leaderboard for ultimate tournament glory!
            </p>
          </div>

          <!-- Tournament Status Card -->
          <div class="bg-[#0d2137]/70 border border-blue-900/50 rounded-2xl p-4 sm:p-6 md:p-8 max-w-lg mx-auto">
            <%= if @tournament do %>
              <div class="text-gray-400 text-xs sm:text-sm uppercase tracking-wide mb-2">
                <%= status_label(@tournament.status) %>
              </div>
              <div class="text-2xl sm:text-3xl font-bold text-white mb-3 sm:mb-4">
                <%= @tournament.name %>
              </div>
              <p class="text-gray-500 text-sm sm:text-base mb-4 sm:mb-6">
                <%= @tournament.description || "64 contestants battle it out!" %>
              </p>

              <%= if @current_user do %>
                <%= case @tournament.status do %>
                  <% "registration" -> %>
                    <div class="space-y-2">
                      <a href={"/tournament/#{@tournament.id}"} class="inline-block bg-blue-600 hover:bg-blue-700 text-white px-6 py-3 rounded-lg font-medium transition-colors">
                        View Tournament
                      </a>
                      <div>
                        <a href={"/tournament/#{@tournament.id}/bracket"} class="text-blue-400 hover:text-blue-300 text-sm">
                          Fill Out Your Bracket →
                        </a>
                      </div>
                    </div>
                  <% "active" -> %>
                    <div class="space-y-2">
                      <div class="text-green-400 text-sm">
                        <%= if @tournament.current_voting_region do %>
                          <%= String.capitalize(@tournament.current_voting_region) %> Region, Round <%= @tournament.current_voting_round %> voting is open!
                        <% else %>
                          Round <%= @tournament.current_round %> voting is open!
                        <% end %>
                      </div>
                      <%= if @voting_ends_at do %>
                        <div class="text-gray-400 text-xs">
                          Voting period ends
                          <span
                            id="home-voting-deadline"
                            phx-hook="LocalTime"
                            data-utc={DateTime.to_iso8601(@voting_ends_at)}
                            data-format="datetime"
                          ><%= format_time(@voting_ends_at) %> UTC</span>
                        </div>
                      <% end %>
                      <a href={"/tournament/#{@tournament.id}"} class="inline-block bg-blue-600 hover:bg-blue-700 text-white px-6 py-3 rounded-lg font-medium transition-colors">
                        <%= if @has_voted, do: "View Bracket", else: "Vote Now" %>
                      </a>
                    </div>
                  <% "completed" -> %>
                    <a href={"/tournament/#{@tournament.id}"} class="inline-block bg-gray-700 hover:bg-gray-600 text-white px-6 py-3 rounded-lg font-medium transition-colors">
                      View Final Bracket
                    </a>
                <% end %>
              <% else %>
                <div class="space-y-3">
                  <a href={"/tournament/#{@tournament.id}"} class="inline-block bg-blue-600 hover:bg-blue-700 text-white px-6 py-3 rounded-lg font-medium transition-colors">
                    View Tournament
                  </a>
                  <div>
                    <a href="/auth/signin" class="text-blue-400 hover:text-blue-300 text-sm">
                      Sign in to participate →
                    </a>
                  </div>
                </div>
              <% end %>
            <% else %>
              <div class="text-gray-400 text-sm uppercase tracking-wide mb-2">
                Current Tournament
              </div>
              <div class="text-3xl font-bold text-white mb-4">
                Coming Soon
              </div>
              <p class="text-gray-500 mb-6">
                No active tournament right now. Check back soon for the next battle!
              </p>

              <%= if @current_user do %>
                <div class="text-green-400 text-sm">
                  You're signed in and ready to compete!
                </div>
              <% else %>
                <a href="/auth/signin" class="inline-block bg-blue-600 hover:bg-blue-700 text-white px-6 py-3 rounded-lg font-medium transition-colors">
                  Sign In to Get Started
                </a>
              <% end %>
            <% end %>
          </div>

          <!-- Features -->
          <div class="mt-16 grid grid-cols-1 md:grid-cols-3 gap-8">
            <div class="bg-gray-800/30 border border-gray-700/50 rounded-xl p-6">
              <div class="w-12 h-12 bg-blue-600/20 rounded-lg flex items-center justify-center mb-4 mx-auto">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-blue-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </div>
              <h3 class="text-lg font-semibold text-white mb-2">Fill Out Your Bracket</h3>
              <p class="text-gray-400 text-sm">
                Predict all matchups before the tournament starts
              </p>
            </div>

            <div class="bg-gray-800/30 border border-gray-700/50 rounded-xl p-6">
              <div class="w-12 h-12 bg-blue-600/20 rounded-lg flex items-center justify-center mb-4 mx-auto">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-blue-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </div>
              <h3 class="text-lg font-semibold text-white mb-2">Vote on Matchups</h3>
              <p class="text-gray-400 text-sm">
                Voting on matchups determines who moves on
              </p>
            </div>

            <div class="bg-gray-800/30 border border-gray-700/50 rounded-xl p-6">
              <div class="w-12 h-12 bg-blue-600/20 rounded-lg flex items-center justify-center mb-4 mx-auto">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-blue-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
                </svg>
              </div>
              <h3 class="text-lg font-semibold text-white mb-2">Climb the Leaderboard</h3>
              <p class="text-gray-400 text-sm">
                Earn points for correct predictions. More points in later rounds!
              </p>
            </div>
          </div>
        </div>
      </main>
    </div>
    """
  end

  defp status_label("registration"), do: "Registration Open"
  defp status_label("active"), do: "Tournament In Progress"
  defp status_label("completed"), do: "Tournament Complete"
  defp status_label(_), do: "Current Tournament"

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%b %d at %I:%M %p")
  end

  defp load_ticker_matchups(tournament) do
    tournament.id
    |> Tournaments.get_matchups_by_round(tournament.current_round)
    |> Enum.filter(fn m -> m.status == "voting" end)
    |> Enum.map(fn m ->
      counts = Voting.get_vote_counts(m.id)
      c1_votes = Map.get(counts, m.contestant_1_id, 0)
      c2_votes = Map.get(counts, m.contestant_2_id, 0)
      total = c1_votes + c2_votes

      %{
        id: m.id,
        contestant_1: m.contestant_1,
        contestant_2: m.contestant_2,
        c1_votes: c1_votes,
        c2_votes: c2_votes,
        c1_pct: if(total > 0, do: round(c1_votes / total * 100), else: 50),
        c2_pct: if(total > 0, do: round(c2_votes / total * 100), else: 50),
        region: m.region || "Final Four",
        round: m.round,
        status: m.status,
        winner_id: m.winner_id,
        voting_ends_at: m.voting_ends_at
      }
    end)
  end

  # Ticker matchup component
  defp ticker_matchup(assigns) do
    ~H"""
    <div class="ticker-matchup">
      <div class="ticker-contestants">
        <span class={["ticker-contestant", @matchup.winner_id == @matchup.contestant_1.id && "winner"]}>
          (<%= @matchup.contestant_1.seed %>) <%= @matchup.contestant_1.name %>
        </span>
        <span class="ticker-vs">vs</span>
        <span class={["ticker-contestant", @matchup.winner_id == @matchup.contestant_2.id && "winner"]}>
          (<%= @matchup.contestant_2.seed %>) <%= @matchup.contestant_2.name %>
        </span>
      </div>
    </div>
    """
  end

  # Tournament Start Reveal Banner (no confetti)
  defp tournament_start_banner(assigns) do
    ~H"""
    <!-- Overlay -->
    <div class="fixed inset-0 bg-black/70 z-50 flex items-center justify-center p-4">
      <!-- Modal Card -->
      <div class="bg-gray-800 rounded-2xl border border-yellow-500 shadow-2xl shadow-yellow-500/20 max-w-md w-full p-8 text-center relative">
        <!-- Close Button -->
        <button
          phx-click="dismiss_tournament_start"
          class="absolute top-4 right-4 text-gray-400 hover:text-white transition-colors"
        >
          <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>

        <!-- Trophy Icon -->
        <div class="text-6xl mb-4">
          🏆
        </div>

        <!-- Headline -->
        <h2 class="text-2xl font-bold text-white mb-2">
          <%= @tournament.name %> Has Begun!
        </h2>

        <!-- Subtext -->
        <p class="text-gray-300 mb-2">
          Round 1 voting is now open
        </p>

        <!-- Call to action -->
        <p class="text-yellow-400 font-medium mb-6">
          Cast your votes to help decide the winners!
        </p>

        <!-- CTA Button - Navigate to tournament -->
        <a
          href={"/tournament/#{@tournament.id}"}
          phx-click="dismiss_tournament_start"
          class="bg-yellow-500 hover:bg-yellow-600 text-gray-900 px-6 py-3 rounded-lg font-semibold transition-colors inline-flex items-center justify-center"
        >
          Go to Tournament
          <svg class="w-5 h-5 ml-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7l5 5m0 0l-5 5m5-5H6" />
          </svg>
        </a>
      </div>
    </div>
    """
  end

  # Tournament Complete Popup - shows final ranking after tournament ends
  defp tournament_complete_popup(assigns) do
    {border_color, emoji, headline} =
      case assigns.rank do
        1 -> {"border-yellow-500", "🥇", "You Won!"}
        2 -> {"border-gray-400", "🥈", "2nd Place!"}
        3 -> {"border-amber-600", "🥉", "3rd Place!"}
        _ -> {"border-blue-500", "🎉", "Tournament Complete!"}
      end

    assigns = assign(assigns, border_color: border_color, emoji: emoji, headline: headline)

    ~H"""
    <!-- Confetti -->
    <div class="confetti-container">
      <%= for i <- 1..40 do %>
        <div class={"confetti confetti-#{i}"}></div>
      <% end %>
    </div>

    <!-- Modal -->
    <div class="fixed inset-0 bg-black/80 z-50 flex items-center justify-center p-4">
      <div class={"bg-gray-800 rounded-2xl #{@border_color} border-2 shadow-2xl max-w-md w-full p-8 text-center relative"}>
        <!-- Close button -->
        <button phx-click="dismiss_tournament_complete" class="absolute top-4 right-4 text-gray-400 hover:text-white transition-colors">
          <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>

        <div class="text-6xl mb-4"><%= @emoji %></div>
        <h2 class="text-2xl font-bold text-white mb-2"><%= @headline %></h2>
        <p class="text-gray-300 mb-4"><%= @tournament.name %> has ended</p>

        <div class="bg-gray-700/50 rounded-xl p-4 mb-6">
          <div class="text-4xl font-bold text-white mb-1">#<%= @rank %></div>
          <div class="text-gray-400 text-sm">Final Placement</div>
          <%= if @score do %>
            <div class="text-blue-400 font-semibold mt-2"><%= @score %> points</div>
          <% end %>
        </div>

        <a href={"/tournament/#{@tournament.id}?tab=leaderboard"}
           phx-click="dismiss_tournament_complete"
           class="inline-block bg-blue-600 hover:bg-blue-700 text-white px-6 py-3 rounded-lg font-semibold transition-colors">
          View Leaderboard
        </a>
      </div>
    </div>
    """
  end

  # Welcome Splash - Epic Title Reveal for first-time visitors
  defp welcome_splash(assigns) do
    ~H"""
    <div id="welcome-splash" class="welcome-splash" phx-click="dismiss_welcome_splash">
      <!-- Bubbles floating up from the deep -->
      <div class="splash-bubble bubble-1"></div>
      <div class="splash-bubble bubble-2"></div>
      <div class="splash-bubble bubble-3"></div>
      <div class="splash-bubble bubble-4"></div>
      <div class="splash-bubble bubble-5"></div>
      <div class="splash-bubble bubble-6"></div>
      <div class="splash-bubble bubble-7"></div>
      <div class="splash-bubble bubble-8"></div>
      <div class="splash-bubble bubble-9"></div>
      <div class="splash-bubble bubble-10"></div>
      <div class="splash-bubble bubble-11"></div>
      <div class="splash-bubble bubble-12"></div>

      <!-- Animated Title -->
      <div class="text-center relative z-10">
        <h1 class="splash-title">
          <span class="text-white">Minnows</span>
        </h1>
        <p class="splash-tagline">Let the feeding frenzy begin</p>
        <div class="splash-cta">
          <span class="text-blue-200 text-sm">Click anywhere to continue</span>
        </div>
      </div>

      <!-- Skip text -->
      <div class="splash-skip">
        Press anywhere to skip
      </div>
    </div>
    """
  end

  # Event Handlers

  @impl true
  def handle_event("toggle_mobile_menu", _, socket) do
    {:noreply, assign(socket, show_mobile_menu: !socket.assigns.show_mobile_menu)}
  end

  # Show tournament start banner (triggered from JS hook if not seen before)
  def handle_event("show_tournament_start", _, socket) do
    if socket.assigns.tournament &&
       socket.assigns.tournament.status == "active" &&
       socket.assigns.tournament.current_round == 1 do
      {:noreply, assign(socket, show_tournament_start: true)}
    else
      {:noreply, socket}
    end
  end

  # Dismiss tournament start banner and save to localStorage via push_event
  def handle_event("dismiss_tournament_start", _, socket) do
    {:noreply,
     socket
     |> assign(show_tournament_start: false)
     |> push_event("tournament_start_dismissed", %{tournament_id: socket.assigns.tournament.id})}
  end

  # Show welcome splash (triggered from JS hook if not seen before)
  def handle_event("show_welcome_splash", _, socket) do
    {:noreply, assign(socket, show_welcome_splash: true)}
  end

  # Dismiss welcome splash and save to localStorage via push_event
  def handle_event("dismiss_welcome_splash", _, socket) do
    {:noreply,
     socket
     |> assign(show_welcome_splash: false)
     |> push_event("welcome_splash_dismissed", %{})}
  end

  # Show tournament complete popup (triggered from JS hook if not seen before)
  def handle_event("show_tournament_complete", _, socket) do
    {:noreply, assign(socket, show_tournament_complete: true)}
  end

  # Dismiss tournament complete popup and save to localStorage via push_event
  def handle_event("dismiss_tournament_complete", _, socket) do
    {:noreply,
     socket
     |> assign(show_tournament_complete: false)
     |> push_event("tournament_complete_dismissed", %{tournament_id: socket.assigns.tournament.id})}
  end
end
