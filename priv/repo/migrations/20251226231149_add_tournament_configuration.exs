defmodule BracketBattle.Repo.Migrations.AddTournamentConfiguration do
  use Ecto.Migration

  def change do
    alter table(:tournaments) do
      # Tournament size (power of 2: 8, 16, 32, 64, 128)
      add :bracket_size, :integer, default: 64

      # Number of regions (2-8)
      add :region_count, :integer, default: 4

      # Custom region names stored as array
      add :region_names, {:array, :string}, default: ["East", "West", "South", "Midwest"]

      # Custom round names stored as map (round number => name)
      add :round_names, :map, default: %{}

      # Custom scoring per round (optional override)
      add :scoring_config, :map, default: %{}
    end
  end
end
