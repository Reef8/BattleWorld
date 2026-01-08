defmodule BracketBattle.Repo.Migrations.AddIpToMagicLinks do
  use Ecto.Migration

  def change do
    alter table(:magic_links) do
      add :ip_address, :string
    end

    create index(:magic_links, [:ip_address, :inserted_at])
  end
end
