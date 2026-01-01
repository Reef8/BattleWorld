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

    # Region-based voting fields
    field :current_voting_region, :string
    field :current_voting_round, :integer
    field :voting_durations, :map, default: %{}
    field :default_voting_duration_hours, :integer, default: 24

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
                    :bracket_size, :region_count, :region_names, :round_names, :scoring_config,
                    :current_voting_region, :current_voting_round, :voting_durations,
                    :default_voting_duration_hours])
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

  @doc "Calculate total regional rounds (before Final Four)"
  def regional_rounds(%__MODULE__{bracket_size: size, region_count: regions})
      when is_integer(size) and is_integer(regions) do
    contestants_per_region = div(size, regions)
    trunc(:math.log2(contestants_per_region))
  end
  def regional_rounds(_), do: 4

  @doc "Get voting duration for a specific region and round (in hours)"
  def get_voting_duration(%__MODULE__{} = tournament, region, round) do
    durations = tournament.voting_durations || %{}
    region_key = region || "Final"
    round_key = to_string(round)

    region_durations = Map.get(durations, region_key, %{})

    cond do
      Map.has_key?(region_durations, round) -> Map.get(region_durations, round)
      Map.has_key?(region_durations, round_key) -> Map.get(region_durations, round_key)
      true -> tournament.default_voting_duration_hours || 24
    end
  end

  @doc "Get ordered list of region voting sequence"
  def voting_sequence(%__MODULE__{region_names: names} = tournament) do
    reg_rounds = regional_rounds(tournament)
    tot_rounds = total_rounds(tournament)

    # Build sequence: Sketch R1, Rotoscope R1, Cartoon R1, Claymation R1, Sketch R2, ...
    # (all regions for each round, then move to next round)
    region_sequence = for round <- 1..reg_rounds, region <- names do
      {region, round}
    end

    # Add Final Four and Championship (no region)
    final_sequence = for round <- (reg_rounds + 1)..tot_rounds do
      {nil, round}
    end

    region_sequence ++ final_sequence
  end

  @doc "Get the next voting phase after the current one"
  def next_voting_phase(%__MODULE__{} = tournament, current_region, current_round) do
    sequence = voting_sequence(tournament)
    current_index = Enum.find_index(sequence, fn {r, rd} ->
      r == current_region && rd == current_round
    end)

    if current_index && current_index + 1 < length(sequence) do
      Enum.at(sequence, current_index + 1)
    else
      nil
    end
  end
end
