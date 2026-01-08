defmodule BracketBattleWeb.AuthLive do
  use BracketBattleWeb, :live_view

  alias BracketBattle.Accounts

  @impl true
  def mount(_params, _session, socket) do
    ip_address = get_client_ip(socket)

    {:ok,
     assign(socket,
       email: "",
       email_sent: false,
       error: nil,
       form: to_form(%{"email" => ""}),
       ip_address: ip_address
     )}
  end

  # Get real client IP, checking CloudFlare header first
  defp get_client_ip(socket) do
    x_headers = get_connect_info(socket, :x_headers) || []

    # CloudFlare sends real IP in cf-connecting-ip header
    case List.keyfind(x_headers, "cf-connecting-ip", 0) do
      {_, ip} -> ip
      nil -> get_connect_info(socket, :peer_data)[:address] |> format_ip()
    end
  end

  defp format_ip(nil), do: nil
  defp format_ip(ip) when is_tuple(ip), do: ip |> :inet.ntoa() |> to_string()
  defp format_ip(ip), do: to_string(ip)

  @impl true
  def handle_event("send_magic_link", %{"email" => email}, socket) do
    case Accounts.create_magic_link(email, socket.assigns.ip_address) do
      {:ok, _magic_link} ->
        {:noreply,
         assign(socket,
           email_sent: true,
           email: email,
           error: nil
         )}

      {:error, :rate_limited} ->
        {:noreply,
         assign(socket,
           error: "Please wait a few minutes before requesting another link"
         )}

      {:error, _changeset} ->
        {:noreply,
         assign(socket,
           error: "Please enter a valid email address"
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gradient-to-b from-[#0a1628] via-[#1e3a5f] to-[#0d2137]">
      <div class="w-full max-w-md px-6">
        <!-- Flash messages -->
        <%= if Phoenix.Flash.get(@flash, :error) do %>
          <div class="mb-6 p-4 text-sm bg-red-900/50 text-red-200 border border-red-500 rounded-lg text-center">
            <%= Phoenix.Flash.get(@flash, :error) %>
          </div>
        <% end %>
        <%= if Phoenix.Flash.get(@flash, :info) do %>
          <div class="mb-6 p-4 text-sm bg-green-900/50 text-green-200 border border-green-500 rounded-lg text-center">
            <%= Phoenix.Flash.get(@flash, :info) %>
          </div>
        <% end %>

        <div class="bg-gray-800 rounded-2xl shadow-2xl p-8 border border-gray-700">
          <%= if @email_sent do %>
            <!-- Success state -->
            <div class="text-center">
              <div class="w-16 h-16 bg-blue-600 rounded-full flex items-center justify-center mx-auto mb-6">
                <svg xmlns="http://www.w3.org/2000/svg" class="h-8 w-8 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
                </svg>
              </div>
              <h1 class="text-2xl font-bold text-white mb-4">Check Your Email</h1>
              <p class="text-gray-300 mb-2">
                We sent a magic link to
              </p>
              <p class="text-blue-400 font-medium mb-6"><%= @email %></p>
              <p class="text-sm text-gray-500">
                Click the link in the email to sign in. The link expires in 15 minutes.
              </p>
            </div>
          <% else %>
            <!-- Email input form -->
            <div class="text-center mb-8">
              <h1 class="text-3xl font-bold text-white mb-2">BracketBattle</h1>
              <p class="text-gray-400">
                Enter your email to sign in or create an account
              </p>
            </div>

            <form phx-submit="send_magic_link">
              <div class="mb-6">
                <input
                  type="email"
                  name="email"
                  placeholder="you@example.com"
                  required
                  class="w-full px-4 py-3 bg-gray-700 border border-gray-600 rounded-lg text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                />
              </div>

              <%= if @error do %>
                <div class="mb-4 p-3 text-sm bg-red-900/50 text-red-200 border border-red-500 rounded-lg">
                  <%= @error %>
                </div>
              <% end %>

              <button
                type="submit"
                class="w-full py-3 px-4 bg-blue-600 hover:bg-blue-700 text-white font-semibold rounded-lg transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 focus:ring-offset-gray-800"
              >
                Send Magic Link
              </button>
            </form>
          <% end %>
        </div>

        <p class="text-center text-gray-500 text-sm mt-8">
          No password needed. We'll email you a secure link to sign in.
        </p>
      </div>
    </div>
    """
  end
end
