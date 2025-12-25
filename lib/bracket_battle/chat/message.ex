defmodule BracketBattle.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chat_messages" do
    field :content, :string
    field :deleted_at, :utc_datetime

    belongs_to :tournament, BracketBattle.Tournaments.Tournament
    belongs_to :user, BracketBattle.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:content, :tournament_id, :user_id, :deleted_at])
    |> validate_required([:content, :tournament_id, :user_id])
    |> validate_length(:content, min: 1, max: 500)
  end
end
