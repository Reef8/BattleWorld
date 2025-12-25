defmodule BracketBattle.Repo.Migrations.CreateTournaments do
  use Ecto.Migration

  def change do
    create table(:tournaments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "draft"
      add :current_round, :integer, default: 0
      add :registration_deadline, :utc_datetime
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:tournaments, [:status])
    create index(:tournaments, [:created_by_id])
  end
end
