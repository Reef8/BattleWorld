defmodule BracketBattle.Repo.Migrations.AddRegionVotingFields do
  use Ecto.Migration

  def change do
    alter table(:tournaments) do
      # Current voting state
      add :current_voting_region, :string
      add :current_voting_round, :integer

      # Configurable voting durations per region/round (in hours)
      # Structure: %{"East" => %{1 => 24, 2 => 12}, "Final Four" => %{1 => 48}}
      add :voting_durations, :map, default: %{}

      # Default voting duration in hours (fallback)
      add :default_voting_duration_hours, :integer, default: 24
    end
  end
end
