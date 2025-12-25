defmodule BracketBattleWeb.AdminAuth do
  @moduledoc """
  LiveView on_mount hook to ensure current user is an admin.
  Redirects to home page if not authenticated or not an admin.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias BracketBattle.Accounts

  def on_mount(:ensure_admin, _params, session, socket) do
    socket = assign_current_user(socket, session)

    if admin?(socket.assigns.current_user) do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/")}
    end
  end

  defp assign_current_user(socket, session) do
    user = if user_id = session["user_id"] do
      Accounts.get_user(user_id)
    end

    assign(socket, :current_user, user)
  end

  defp admin?(%{is_admin: true}), do: true
  defp admin?(_), do: false
end
