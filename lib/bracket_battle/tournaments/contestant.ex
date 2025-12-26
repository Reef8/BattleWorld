defmodule BracketBattle.Tournaments.Contestant do
  use Ecto.Schema
  import Ecto.Changeset

  alias BracketBattle.Tournaments.Tournament

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # Default regions for backward compatibility
  @default_regions ~w(East West South Midwest)

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

  @doc """
  Creates a changeset for a contestant.
  Accepts an optional tournament parameter for dynamic validation.
  """
  def changeset(contestant, attrs, tournament \\ nil) do
    contestant
    |> cast(attrs, [:name, :seed, :region, :image_url, :description, :eliminated_in_round, :tournament_id])
    |> validate_required([:name, :seed, :region])
    |> validate_seed_for_tournament(tournament)
    |> validate_region_for_tournament(tournament)
    |> unique_constraint([:tournament_id, :seed, :region])
  end

  defp validate_seed_for_tournament(changeset, nil) do
    # Fallback to 1-16 if no tournament provided
    validate_inclusion(changeset, :seed, 1..16)
  end

  defp validate_seed_for_tournament(changeset, %Tournament{} = tournament) do
    max_seed = Tournament.max_seed(tournament)
    validate_inclusion(changeset, :seed, 1..max_seed)
  end

  defp validate_region_for_tournament(changeset, nil) do
    # Fallback to default regions if no tournament provided
    validate_inclusion(changeset, :region, @default_regions)
  end

  defp validate_region_for_tournament(changeset, %Tournament{region_names: regions}) when is_list(regions) do
    validate_inclusion(changeset, :region, regions)
  end

  defp validate_region_for_tournament(changeset, _) do
    validate_inclusion(changeset, :region, @default_regions)
  end

  def default_regions, do: @default_regions
end
