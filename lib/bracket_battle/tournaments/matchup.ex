defmodule BracketBattle.Tournaments.Matchup do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending voting decided)

  schema "matchups" do
    field :round, :integer
    field :position, :integer
    field :region, :string
    field :status, :string, default: "pending"
    field :voting_starts_at, :utc_datetime
    field :voting_ends_at, :utc_datetime
    field :decided_at, :utc_datetime
    field :admin_decided, :boolean, default: false

    belongs_to :tournament, BracketBattle.Tournaments.Tournament
    belongs_to :contestant_1, BracketBattle.Tournaments.Contestant
    belongs_to :contestant_2, BracketBattle.Tournaments.Contestant
    belongs_to :winner, BracketBattle.Tournaments.Contestant
    has_many :votes, BracketBattle.Voting.Vote

    timestamps(type: :utc_datetime)
  end

  def changeset(matchup, attrs) do
    matchup
    |> cast(attrs, [:round, :position, :region, :status, :voting_starts_at,
                    :voting_ends_at, :decided_at, :admin_decided,
                    :tournament_id, :contestant_1_id, :contestant_2_id, :winner_id])
    |> validate_required([:round, :position, :tournament_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:round, 1..6)
    |> unique_constraint([:tournament_id, :round, :position])
  end

  def statuses, do: @statuses
end
