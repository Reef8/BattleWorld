defmodule BracketBattle.Tournaments.Contestant do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @regions ~w(East West South Midwest)

  schema "contestants" do
    field :name, :string
    field :seed, :integer
    field :region, :string
    field :image_url, :string
    field :description, :string
    field :eliminated_in_round, :integer

    belongs_to :tournament, BracketBattle.Tournaments.Tournament

    timestamps(type: :utc_datetime)
  end

  def changeset(contestant, attrs) do
    contestant
    |> cast(attrs, [:name, :seed, :region, :image_url, :description, :eliminated_in_round, :tournament_id])
    |> validate_required([:name, :seed, :region])
    |> validate_inclusion(:seed, 1..16)
    |> validate_inclusion(:region, @regions)
    |> unique_constraint([:tournament_id, :seed, :region])
  end

  def regions, do: @regions
end
