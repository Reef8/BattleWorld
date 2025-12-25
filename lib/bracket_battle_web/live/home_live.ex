defmodule BracketBattleWeb.HomeLive do
  use BracketBattleWeb, :live_view

  alias BracketBattle.Accounts

  @impl true
  def mount(_params, session, socket) do
    user = if user_id = session["user_id"] do
      Accounts.get_user(user_id)
    end

    {:ok,
     assign(socket,
       current_user: user,
       page_title: "BracketBattle"
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-purple-900 via-gray-900 to-gray-900">
      <!-- Header -->
      <header class="border-b border-gray-800">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between items-center h-16">
            <div class="flex items-center">
              <h1 class="text-2xl font-bold text-white">BracketBattle</h1>
            </div>

            <nav class="flex items-center space-x-4">
              <%= if @current_user do %>
                <span class="text-gray-400 text-sm">
                  <%= @current_user.display_name || @current_user.email %>
                </span>
                <a href="/auth/signout" class="text-gray-400 hover:text-white text-sm">
                  Sign Out
                </a>
              <% else %>
                <a href="/auth/signin" class="bg-purple-600 hover:bg-purple-700 text-white px-4 py-2 rounded-lg text-sm font-medium transition-colors">
                  Sign In
                </a>
              <% end %>
            </nav>
          </div>
        </div>
      </header>

      <!-- Main Content -->
      <main class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <div class="text-center">
          <!-- Hero Section -->
          <div class="mb-12">
            <h2 class="text-5xl font-extrabold text-white mb-4">
              March Madness-Style
              <span class="text-purple-400">Bracket Battles</span>
            </h2>
            <p class="text-xl text-gray-400 max-w-2xl mx-auto">
              Create brackets, vote on matchups, and compete on the leaderboard.
              From Marvel characters to movie villains - anything can be a tournament!
            </p>
          </div>

          <!-- Tournament Status Card -->
          <div class="bg-gray-800/50 border border-gray-700 rounded-2xl p-8 max-w-lg mx-auto">
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
              <a href="/auth/signin" class="inline-block bg-purple-600 hover:bg-purple-700 text-white px-6 py-3 rounded-lg font-medium transition-colors">
                Sign In to Get Started
              </a>
            <% end %>
          </div>

          <!-- Features -->
          <div class="mt-16 grid grid-cols-1 md:grid-cols-3 gap-8">
            <div class="bg-gray-800/30 border border-gray-700/50 rounded-xl p-6">
              <div class="w-12 h-12 bg-purple-600/20 rounded-lg flex items-center justify-center mb-4 mx-auto">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-purple-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </div>
              <h3 class="text-lg font-semibold text-white mb-2">Fill Your Bracket</h3>
              <p class="text-gray-400 text-sm">
                Predict all 63 matchups before the tournament starts
              </p>
            </div>

            <div class="bg-gray-800/30 border border-gray-700/50 rounded-xl p-6">
              <div class="w-12 h-12 bg-purple-600/20 rounded-lg flex items-center justify-center mb-4 mx-auto">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-purple-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </div>
              <h3 class="text-lg font-semibold text-white mb-2">Vote on Matchups</h3>
              <p class="text-gray-400 text-sm">
                24-hour voting rounds determine who moves on
              </p>
            </div>

            <div class="bg-gray-800/30 border border-gray-700/50 rounded-xl p-6">
              <div class="w-12 h-12 bg-purple-600/20 rounded-lg flex items-center justify-center mb-4 mx-auto">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-purple-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
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
end
