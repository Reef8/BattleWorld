defmodule BracketBattle.Repo.Migrations.CreateMatchups do
  use Ecto.Migration

  def change do
    create table(:matchups, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tournament_id, references(:tournaments, type: :binary_id, on_delete: :delete_all), null: false
      add :round, :integer, null: false
      add :position, :integer, null: false
      add :region, :string
      add :contestant_1_id, references(:contestants, type: :binary_id, on_delete: :nilify_all)
      add :contestant_2_id, references(:contestants, type: :binary_id, on_delete: :nilify_all)
      add :winner_id, references(:contestants, type: :binary_id, on_delete: :nilify_all)
      add :status, :string, default: "pending"
      add :voting_starts_at, :utc_datetime
      add :voting_ends_at, :utc_datetime
      add :decided_at, :utc_datetime
      add :admin_decided, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:matchups, [:tournament_id, :round, :position])
    create index(:matchups, [:tournament_id, :status])
    create index(:matchups, [:voting_ends_at])
  end
end
