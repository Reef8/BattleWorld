defmodule BracketBattle.Accounts do
  @moduledoc """
  The Accounts context - handles user authentication via magic links.
  """

  alias BracketBattle.Repo
  alias BracketBattle.Accounts.{User, MagicLink}

  # ============================================================================
  # MAGIC LINK AUTHENTICATION
  # ============================================================================

  @doc """
  Creates a magic link for the given email and sends it.
  If the user doesn't exist, creates a new user on verification.
  Returns {:ok, magic_link} on success.
  """
  def create_magic_link(email) do
    changeset = MagicLink.create_changeset(email)

    case Repo.insert(changeset) do
      {:ok, magic_link} ->
        send_magic_link_email(magic_link)
        {:ok, magic_link}

      {:error, _changeset} = error ->
        error
    end
  end

  @doc """
  Verifies a magic link token and signs in the user.
  Returns {:ok, user} on success, {:error, reason} on failure.
  """
  def verify_magic_link(token) do
    with {:ok, magic_link} <- get_valid_magic_link(token),
         {:ok, magic_link} <- mark_magic_link_used(magic_link),
         {:ok, user} <- get_or_create_user(magic_link.email) do
      {:ok, user}
    end
  end

  defp get_valid_magic_link(token) do
    magic_link = Repo.get_by(MagicLink, token: token)
    now = DateTime.utc_now()

    cond do
      is_nil(magic_link) ->
        {:error, :invalid_token}

      not is_nil(magic_link.used_at) ->
        {:error, :already_used}

      DateTime.compare(now, magic_link.expires_at) == :gt ->
        {:error, :expired}

      true ->
        {:ok, magic_link}
    end
  end

  defp mark_magic_link_used(magic_link) do
    magic_link
    |> Ecto.Changeset.change(used_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  defp get_or_create_user(email) do
    case get_user_by_email(email) do
      nil ->
        # Create new user with magic link auth
        %User{}
        |> User.magic_link_changeset(%{email: email})
        |> Repo.insert()

      user ->
        {:ok, user}
    end
  end

  defp send_magic_link_email(magic_link) do
    magic_link_url = build_magic_link_url(magic_link.token)

    client = Resend.client()

    Resend.Emails.send(client, %{
      from: "noreply@minnowstournament.com",
      to: [magic_link.email],
      subject: "Sign in to BracketBattle",
      html: """
      <div style="font-family: system-ui, -apple-system, sans-serif; max-width: 600px; margin: 0 auto; padding: 40px 20px;">
        <h1 style="color: #1a1a1a; font-size: 24px; margin-bottom: 24px;">Sign in to BracketBattle</h1>

        <p style="color: #525252; font-size: 16px; line-height: 24px; margin-bottom: 24px;">
          Click the button below to sign in to your account. This link will expire in 15 minutes.
        </p>

        <a href="#{magic_link_url}" style="display: inline-block; background: #7c3aed; color: white; padding: 12px 24px; text-decoration: none; border-radius: 4px; font-weight: 500;">
          Sign In
        </a>

        <p style="color: #737373; font-size: 14px; line-height: 20px; margin-top: 32px;">
          If you didn't request this email, you can safely ignore it.
        </p>
      </div>
      """
    })
  end

  defp build_magic_link_url(token) do
    BracketBattleWeb.Endpoint.url() <> "/auth/verify?token=#{token}"
  end

  # ============================================================================
  # USER QUERIES
  # ============================================================================

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def get_user!(id), do: Repo.get!(User, id)

  def get_user(id), do: Repo.get(User, id)

  @doc """
  Updates a user's display name.
  """
  def update_display_name(%User{} = user, display_name) do
    user
    |> User.profile_changeset(%{display_name: display_name})
    |> Repo.update()
  end

  @doc """
  Check if a user is an admin.
  """
  def admin?(%User{is_admin: is_admin}), do: is_admin
  def admin?(_), do: false

  @doc """
  Make a user an admin (for seeding/console use).
  """
  def make_admin!(%User{} = user) do
    user
    |> Ecto.Changeset.change(is_admin: true)
    |> Repo.update!()
  end

  @doc """
  Get the date when user first submitted a bracket ("member since").
  Returns nil if user has never submitted a bracket.
  """
  def get_first_bracket_date(user_id) do
    import Ecto.Query
    alias BracketBattle.Brackets.UserBracket

    from(b in UserBracket,
      where: b.user_id == ^user_id and not is_nil(b.submitted_at),
      select: min(b.submitted_at)
    )
    |> Repo.one()
  end
end
