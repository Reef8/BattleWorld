defmodule BracketBattle.Tournaments.Tournament do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(draft registration active completed)
  @valid_bracket_sizes [8, 16, 32, 64, 128]
  @default_regions ["East", "West", "South", "Midwest"]

  schema "tournaments" do
    field :name, :string
    field :description, :string
    field :status, :string, default: "draft"
    field :current_round, :integer, default: 0
    field :registration_deadline, :utc_datetime
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    # Configuration fields
    field :bracket_size, :integer, default: 64
    field :region_count, :integer, default: 4
    field :region_names, {:array, :string}, default: @default_regions
    field :round_names, :map, default: %{}
    field :scoring_config, :map, default: %{}

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
                    :started_at, :completed_at, :current_round, :created_by_id,
                    :bracket_size, :region_count, :region_names, :round_names, :scoring_config])
    |> validate_required([:name])
    |> validate_inclusion(:status, @statuses)
    |> validate_bracket_config()
  end

  defp validate_bracket_config(changeset) do
    changeset
    |> validate_inclusion(:bracket_size, @valid_bracket_sizes)
    |> validate_number(:region_count, greater_than_or_equal_to: 2, less_than_or_equal_to: 8)
    |> validate_region_names_count()
    |> validate_bracket_divisible_by_regions()
  end

  defp validate_region_names_count(changeset) do
    region_count = get_field(changeset, :region_count) || 4
    region_names = get_field(changeset, :region_names) || @default_regions

    if length(region_names) != region_count do
      add_error(changeset, :region_names, "must have exactly #{region_count} region names")
    else
      changeset
    end
  end

  defp validate_bracket_divisible_by_regions(changeset) do
    size = get_field(changeset, :bracket_size) || 64
    regions = get_field(changeset, :region_count) || 4

    if rem(size, regions) != 0 do
      add_error(changeset, :region_count, "bracket size must be evenly divisible by region count")
    else
      changeset
    end
  end

  # Computed properties
  def total_rounds(%__MODULE__{bracket_size: size}) when is_integer(size) do
    trunc(:math.log2(size))
  end
  def total_rounds(_), do: 6

  def contestants_per_region(%__MODULE__{bracket_size: size, region_count: regions})
      when is_integer(size) and is_integer(regions) do
    div(size, regions)
  end
  def contestants_per_region(_), do: 16

  def max_seed(%__MODULE__{} = tournament) do
    contestants_per_region(tournament)
  end

  def total_matchups(%__MODULE__{bracket_size: size}) when is_integer(size) do
    size - 1
  end
  def total_matchups(_), do: 63

  def statuses, do: @statuses
  def valid_bracket_sizes, do: @valid_bracket_sizes
  def default_regions, do: @default_regions
end
