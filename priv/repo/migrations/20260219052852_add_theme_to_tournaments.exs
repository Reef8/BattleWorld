defmodule BracketBattle.Repo.Migrations.AddThemeToTournaments do
  use Ecto.Migration

  def change do
    alter table(:tournaments) do
      add :theme, :string, default: "default"
    end
  end
end
