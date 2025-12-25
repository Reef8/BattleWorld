defmodule BracketBattle.Repo.Migrations.CreateUserBrackets do
  use Ecto.Migration

  def change do
    create table(:user_brackets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tournament_id, references(:tournaments, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string
      add :picks, :map, null: false, default: %{}
      add :is_complete, :boolean, default: false
      add :submitted_at, :utc_datetime
      add :total_score, :integer, default: 0
      add :round_1_score, :integer, default: 0
      add :round_2_score, :integer, default: 0
      add :round_3_score, :integer, default: 0
      add :round_4_score, :integer, default: 0
      add :round_5_score, :integer, default: 0
      add :round_6_score, :integer, default: 0
      add :correct_picks, :integer, default: 0
      add :possible_score, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_brackets, [:tournament_id, :user_id])
    create index(:user_brackets, [:tournament_id, :total_score])
    create index(:user_brackets, [:tournament_id, :submitted_at])
  end
end
