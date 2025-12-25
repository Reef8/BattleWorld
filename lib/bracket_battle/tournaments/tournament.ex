defmodule BracketBattle.Tournaments.Tournament do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(draft registration active completed)

  schema "tournaments" do
    field :name, :string
    field :description, :string
    field :status, :string, default: "draft"
    field :current_round, :integer, default: 0
    field :registration_deadline, :utc_datetime
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :created_by, BracketBattle.Accounts.User
    has_many :contestants, BracketBattle.Tournaments.Contestant
    has_many :matchups, BracketBattle.Tournaments.Matchup
    has_many :user_brackets, BracketBattle.Brackets.UserBracket
    has_many :chat_messages, BracketBattle.Chat.Message

    timestamps(type: :utc_datetime)
  end

  def changeset(tournament, attrs) do
    tournament
    |> cast(attrs, [:name, :description, :status, :registration_deadline,
                    :started_at, :completed_at, :current_round, :created_by_id])
    |> validate_required([:name])
    |> validate_inclusion(:status, @statuses)
  end

  def statuses, do: @statuses
end
