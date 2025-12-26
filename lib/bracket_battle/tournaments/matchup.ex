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

  def changeset(matchup, attrs, tournament \\ nil) do
    matchup
    |> cast(attrs, [:round, :position, :region, :status, :voting_starts_at,
                    :voting_ends_at, :decided_at, :admin_decided,
                    :tournament_id, :contestant_1_id, :contestant_2_id, :winner_id])
    |> validate_required([:round, :position, :tournament_id])
    |> validate_inclusion(:status, @statuses)
    |> validate_round_for_tournament(tournament)
    |> unique_constraint([:tournament_id, :round, :position])
  end

  defp validate_round_for_tournament(changeset, nil) do
    # Fallback to 1-7 (max for 128 contestants) if no tournament provided
    validate_number(changeset, :round, greater_than_or_equal_to: 1, less_than_or_equal_to: 7)
  end

  defp validate_round_for_tournament(changeset, %{bracket_size: size}) when is_integer(size) do
    max_round = trunc(:math.log2(size))
    validate_number(changeset, :round, greater_than_or_equal_to: 1, less_than_or_equal_to: max_round)
  end

  defp validate_round_for_tournament(changeset, _) do
    validate_number(changeset, :round, greater_than_or_equal_to: 1, less_than_or_equal_to: 6)
  end

  def statuses, do: @statuses
end
