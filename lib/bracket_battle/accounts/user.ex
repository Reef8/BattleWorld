defmodule BracketBattle.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :display_name, :string
    field :is_admin, :boolean, default: false
    field :confirmed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for magic link registration - just email
  """
  def magic_link_changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> validate_email()
  end

  @doc """
  Changeset for updating user profile
  """
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name])
    |> validate_length(:display_name, max: 50)
  end

  defp validate_email(changeset) do
    changeset
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, BracketBattle.Repo)
    |> unique_constraint(:email)
  end
end
