defmodule BracketBattleWeb.AuthController do
  use BracketBattleWeb, :controller

  import Ecto.Query
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

  # Dev-only auto login (only works in dev environment)
  def dev_login(conn, _params) do
    if Mix.env() == :dev do
      # Get the first user or a specific one
      user = BracketBattle.Repo.one(
        from(u in BracketBattle.Accounts.User, limit: 1)
      )

      if user do
        conn
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Dev login as #{user.email}")
        |> redirect(to: "/")
      else
        conn
        |> put_flash(:error, "No users in database")
        |> redirect(to: "/")
      end
    else
      conn
      |> put_flash(:error, "Not available in production")
      |> redirect(to: "/")
    end
  end
end
