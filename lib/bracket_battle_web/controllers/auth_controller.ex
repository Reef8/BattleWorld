defmodule BracketBattleWeb.AuthController do
  use BracketBattleWeb, :controller

  alias BracketBattle.Accounts

  def verify(conn, %{"token" => token}) do
    case Accounts.verify_magic_link(token) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Welcome to BracketBattle!")
        |> redirect(to: "/")

      {:error, :invalid_token} ->
        conn
        |> put_flash(:error, "Invalid magic link")
        |> redirect(to: "/auth/signin")

      {:error, :already_used} ->
        conn
        |> put_flash(:error, "This magic link has already been used")
        |> redirect(to: "/auth/signin")

      {:error, :expired} ->
        conn
        |> put_flash(:error, "This magic link has expired. Please request a new one.")
        |> redirect(to: "/auth/signin")
    end
  end

  def signout(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "Signed out successfully")
    |> redirect(to: "/")
  end
end
