defmodule BracketBattleWeb.UserAuth do
  @moduledoc """
  LiveView on_mount hook to ensure current user is logged in.
  Redirects to sign-in page if not authenticated.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias BracketBattle.Accounts

  def on_mount(:ensure_user, _params, session, socket) do
    socket = assign_current_user(socket, session)

    if socket.assigns.current_user do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/auth/signin")}
    end
  end

  defp assign_current_user(socket, session) do
    user = if user_id = session["user_id"] do
      Accounts.get_user(user_id)
    end

    assign(socket, :current_user, user)
  end
end
