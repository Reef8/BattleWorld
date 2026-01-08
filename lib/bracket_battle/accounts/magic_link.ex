defmodule BracketBattle.Accounts.MagicLink do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "magic_links" do
    field :email, :string
    field :token, :string
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime
    field :ip_address, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(magic_link, attrs) do
    magic_link
    |> cast(attrs, [:email, :token, :expires_at, :used_at, :ip_address])
    |> validate_required([:email, :token, :expires_at])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> unique_constraint(:token)
  end

  @doc """
  Generates a new magic link token for the given email.
  Token expires in 15 minutes.
  """
  def create_changeset(email, ip_address \\ nil) do
    token = generate_token()
    expires_at = DateTime.utc_now() |> DateTime.add(15, :minute)

    %__MODULE__{}
    |> changeset(%{
      email: email,
      token: token,
      expires_at: expires_at,
      ip_address: ip_address
    })
  end

  @doc """
  Generates a secure random token
  """
  def generate_token do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end
end
