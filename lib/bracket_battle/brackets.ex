defmodule BracketBattle.Brackets do
  @moduledoc """
  Context for user bracket management - picks and scoring.
  """

  import Ecto.Query
  alias BracketBattle.Repo
  alias BracketBattle.Brackets.UserBracket
  alias BracketBattle.Tournaments

  # ============================================================================
  # USER BRACKET MANAGEMENT
  # ============================================================================

  @doc "Get or create bracket for user in tournament"
  def get_or_create_bracket(tournament_id, user_id) do
    case Repo.get_by(UserBracket, tournament_id: tournament_id, user_id: user_id) do
      nil ->
        %UserBracket{}
        |> UserBracket.changeset(%{tournament_id: tournament_id, user_id: user_id})
        |> Repo.insert()

      bracket ->
        {:ok, bracket}
    end
  end

  @doc "Get user's bracket"
  def get_user_bracket(tournament_id, user_id) do
    Repo.get_by(UserBracket, tournament_id: tournament_id, user_id: user_id)
  end

  @doc "Get bracket by ID"
  def get_bracket!(id), do: Repo.get!(UserBracket, id)

  @doc "Update picks (saves progress)"
  def update_picks(%UserBracket{} = bracket, picks) do
    is_complete = map_size(picks) == 63 and Enum.all?(picks, fn {_, v} -> v != nil end)

    bracket
    |> UserBracket.changeset(%{
      picks: picks,
      is_complete: is_complete
    })
    |> Repo.update()
    |> broadcast_bracket_update()
  end

  @doc "Submit bracket (locks it in)"
  def submit_bracket(%UserBracket{is_complete: true} = bracket) do
    # Verify tournament is still in registration
    tournament = Tournaments.get_tournament!(bracket.tournament_id)

    if tournament.status == "registration" do
      bracket
      |> UserBracket.changeset(%{submitted_at: DateTime.utc_now()})
      |> Repo.update()
    else
      {:error, :registration_closed}
    end
  end

  def submit_bracket(_), do: {:error, :incomplete_bracket}

  @doc "Check if user has submitted bracket"
  def has_submitted_bracket?(tournament_id, user_id) do
    from(b in UserBracket,
      where: b.tournament_id == ^tournament_id
        and b.user_id == ^user_id
        and not is_nil(b.submitted_at),
      select: count()
    )
    |> Repo.one() > 0
  end

  @doc "Get bracket count for tournament"
  def count_submitted_brackets(tournament_id) do
    from(b in UserBracket,
      where: b.tournament_id == ^tournament_id and not is_nil(b.submitted_at),
      select: count()
    )
    |> Repo.one()
  end

  # ============================================================================
  # LEADERBOARD
  # ============================================================================

  @doc "Get leaderboard with pagination"
  def get_leaderboard(tournament_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    from(b in UserBracket,
      where: b.tournament_id == ^tournament_id and not is_nil(b.submitted_at),
      order_by: [desc: b.total_score, desc: b.correct_picks, asc: b.submitted_at],
      limit: ^limit,
      offset: ^offset,
      preload: [:user]
    )
    |> Repo.all()
    |> Enum.with_index(offset + 1)
    |> Enum.map(fn {bracket, rank} -> Map.put(bracket, :rank, rank) end)
  end

  @doc "Get user's rank"
  def get_user_rank(tournament_id, user_id) do
    bracket = get_user_bracket(tournament_id, user_id)

    if bracket && bracket.submitted_at do
      # Count brackets with higher score
      higher_count = from(b in UserBracket,
        where: b.tournament_id == ^tournament_id
          and not is_nil(b.submitted_at)
          and (b.total_score > ^bracket.total_score
            or (b.total_score == ^bracket.total_score and b.correct_picks > ^bracket.correct_picks)),
        select: count()
      )
      |> Repo.one()

      higher_count + 1
    else
      nil
    end
  end

  @doc "List all submitted brackets for tournament"
  def list_submitted_brackets(tournament_id) do
    from(b in UserBracket,
      where: b.tournament_id == ^tournament_id and not is_nil(b.submitted_at),
      preload: [:user]
    )
    |> Repo.all()
  end

  @doc "Get all brackets for a user across tournaments"
  def get_user_brackets(user_id) do
    from(b in UserBracket,
      where: b.user_id == ^user_id,
      order_by: [desc: b.inserted_at],
      preload: [:tournament]
    )
    |> Repo.all()
  end

  defp broadcast_bracket_update({:ok, bracket} = result) do
    Phoenix.PubSub.broadcast(
      BracketBattle.PubSub,
      "tournament:#{bracket.tournament_id}:brackets",
      {:bracket_updated, bracket}
    )
    result
  end
  defp broadcast_bracket_update(error), do: error
end
