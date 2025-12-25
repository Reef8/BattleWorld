defmodule BracketBattle.Repo.Migrations.CreateMagicLinks do
  use Ecto.Migration

  def change do
    create table(:magic_links, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :token, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:magic_links, [:token])
    create index(:magic_links, [:email])
    create index(:magic_links, [:expires_at])
  end
end
