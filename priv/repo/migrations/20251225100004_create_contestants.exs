defmodule BracketBattle.Repo.Migrations.CreateContestants do
  use Ecto.Migration

  def change do
    create table(:contestants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :tournament_id, references(:tournaments, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :seed, :integer, null: false
      add :region, :string, null: false
      add :image_url, :string
      add :description, :text
      add :eliminated_in_round, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:contestants, [:tournament_id])
    create unique_index(:contestants, [:tournament_id, :seed, :region])
  end
end
