# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     BracketBattle.Repo.insert!(%BracketBattle.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias BracketBattle.Repo
alias BracketBattle.Accounts.User

# Admin email - this user will be created and made admin
admin_email = "Sharifk8@gmail.com"

# Create or update admin user
case Repo.get_by(User, email: admin_email) do
  nil ->
    %User{}
    |> User.magic_link_changeset(%{email: admin_email})
    |> Ecto.Changeset.put_change(:is_admin, true)
    |> Ecto.Changeset.put_change(:display_name, "Admin")
    |> Repo.insert!()
    IO.puts("Created admin user: #{admin_email}")

  user ->
    user
    |> Ecto.Changeset.change(is_admin: true)
    |> Repo.update!()
    IO.puts("Made existing user admin: #{admin_email}")
end

IO.puts("\nAdmin setup complete! Sign in at http://localhost:4002/auth/signin")
