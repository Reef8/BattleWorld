defmodule BracketBattle.Brackets.UserBracket do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_brackets" do
    field :name, :string
    field :picks, :map, default: %{}
    field :is_complete, :boolean, default: false
    field :submitted_at, :utc_datetime
    field :total_score, :integer, default: 0
    field :round_1_score, :integer, default: 0
    field :round_2_score, :integer, default: 0
    field :round_3_score, :integer, default: 0
    field :round_4_score, :integer, default: 0
    field :round_5_score, :integer, default: 0
    field :round_6_score, :integer, default: 0
    field :correct_picks, :integer, default: 0
    field :possible_score, :integer, default: 0

    belongs_to :tournament, BracketBattle.Tournaments.Tournament
    belongs_to :user, BracketBattle.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(bracket, attrs) do
    bracket
    |> cast(attrs, [:name, :picks, :is_complete, :submitted_at, :tournament_id, :user_id])
    |> validate_required([:tournament_id, :user_id])
    |> unique_constraint([:tournament_id, :user_id])
  end

  def score_changeset(bracket, attrs) do
    bracket
    |> cast(attrs, [:total_score, :round_1_score, :round_2_score, :round_3_score,
                    :round_4_score, :round_5_score, :round_6_score,
                    :correct_picks, :possible_score])
  end
end
