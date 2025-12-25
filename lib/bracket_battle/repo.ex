defmodule BracketBattle.Repo do
  use Ecto.Repo,
    otp_app: :bracket_battle,
    adapter: Ecto.Adapters.Postgres
end
