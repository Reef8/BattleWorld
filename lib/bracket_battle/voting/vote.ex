defmodule BracketBattle.Voting.Vote do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "votes" do
    belongs_to :matchup, BracketBattle.Tournaments.Matchup
    belongs_to :user, BracketBattle.Accounts.User
    belongs_to :contestant, BracketBattle.Tournaments.Contestant

    timestamps(type: :utc_datetime)
  end

  def changeset(vote, attrs) do
    vote
    |> cast(attrs, [:matchup_id, :user_id, :contestant_id])
    |> validate_required([:matchup_id, :user_id, :contestant_id])
    |> unique_constraint([:matchup_id, :user_id])
  end
end
