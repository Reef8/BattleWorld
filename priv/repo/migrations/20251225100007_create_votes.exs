defmodule BracketBattle.Repo.Migrations.CreateVotes do
  use Ecto.Migration

  def change do
    create table(:votes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :matchup_id, references(:matchups, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :contestant_id, references(:contestants, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:votes, [:matchup_id, :user_id])
    create index(:votes, [:matchup_id, :contestant_id])
    create index(:votes, [:user_id])
  end
end
