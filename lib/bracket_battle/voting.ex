defmodule BracketBattle.Voting do
  @moduledoc """
  Context for vote management and tallying.
  """

  import Ecto.Query
  alias BracketBattle.Repo
  alias BracketBattle.Voting.Vote
  alias BracketBattle.Tournaments.Matchup
  alias BracketBattle.Brackets

  # ============================================================================
  # VOTING
  # ============================================================================

  @doc "Cast a vote (requires submitted bracket)"
  def cast_vote(matchup_id, user_id, contestant_id) do
    matchup = Repo.get!(Matchup, matchup_id)

    with :ok <- validate_voting_open(matchup),
         :ok <- validate_has_bracket(matchup.tournament_id, user_id),
         :ok <- validate_contestant_in_matchup(matchup, contestant_id),
         :ok <- validate_not_already_voted(matchup_id, user_id) do
      %Vote{}
      |> Vote.changeset(%{
        matchup_id: matchup_id,
        user_id: user_id,
        contestant_id: contestant_id
      })
      |> Repo.insert()
      |> broadcast_vote()
    end
  end

  @doc "Get vote counts for matchup"
  def get_vote_counts(matchup_id) do
    from(v in Vote,
      where: v.matchup_id == ^matchup_id,
      group_by: v.contestant_id,
      select: {v.contestant_id, count(v.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "Get user's vote for matchup"
  def get_user_vote(matchup_id, user_id) do
    Repo.get_by(Vote, matchup_id: matchup_id, user_id: user_id)
  end

  @doc "Check if user has voted on matchup"
  def has_voted?(matchup_id, user_id) do
    from(v in Vote, where: v.matchup_id == ^matchup_id and v.user_id == ^user_id, select: count())
    |> Repo.one() > 0
  end

  @doc "List all votes for a matchup with user info"
  def list_votes_for_matchup(matchup_id) do
    from(v in Vote,
      where: v.matchup_id == ^matchup_id,
      preload: [:user, :contestant]
    )
    |> Repo.all()
  end

  @doc "Get total vote count for matchup"
  def get_total_votes(matchup_id) do
    from(v in Vote, where: v.matchup_id == ^matchup_id, select: count())
    |> Repo.one()
  end

  @doc "Check if user has voted on all currently active voting matchups in a round"
  def has_voted_in_round?(tournament_id, user_id, round) do
    matchup_count = from(m in Matchup,
      where: m.tournament_id == ^tournament_id and m.round == ^round and m.status == "voting",
      select: count()
    ) |> Repo.one()

    vote_count = from(v in Vote,
      join: m in Matchup, on: v.matchup_id == m.id,
      where: m.tournament_id == ^tournament_id and m.round == ^round and m.status == "voting" and v.user_id == ^user_id,
      select: count()
    ) |> Repo.one()

    vote_count > 0 and vote_count == matchup_count
  end

  # ============================================================================
  # VOTE TALLYING (called by Oban job)
  # ============================================================================

  @doc "Tally votes and determine winner"
  def tally_matchup(%Matchup{status: "voting"} = matchup) do
    counts = get_vote_counts(matchup.id)

    c1_votes = Map.get(counts, matchup.contestant_1_id, 0)
    c2_votes = Map.get(counts, matchup.contestant_2_id, 0)

    cond do
      c1_votes > c2_votes ->
        BracketBattle.Tournaments.decide_matchup(matchup, matchup.contestant_1_id)

      c2_votes > c1_votes ->
        BracketBattle.Tournaments.decide_matchup(matchup, matchup.contestant_2_id)

      true ->
        # Tie - needs admin decision
        {:tie, matchup.id, c1_votes, c2_votes}
    end
  end

  @doc "Get matchups that need vote tallying (voting ended)"
  def get_matchups_needing_tally do
    now = DateTime.utc_now()

    from(m in Matchup,
      where: m.status == "voting" and m.voting_ends_at <= ^now,
      preload: [:tournament]
    )
    |> Repo.all()
  end

  # ============================================================================
  # VALIDATION
  # ============================================================================

  defp validate_voting_open(%Matchup{status: "voting"} = matchup) do
    now = DateTime.utc_now()
    if DateTime.compare(now, matchup.voting_ends_at) == :lt do
      :ok
    else
      {:error, :voting_closed}
    end
  end
  defp validate_voting_open(_), do: {:error, :voting_not_open}

  defp validate_has_bracket(tournament_id, user_id) do
    if Brackets.has_submitted_bracket?(tournament_id, user_id) do
      :ok
    else
      {:error, :bracket_required}
    end
  end

  defp validate_contestant_in_matchup(matchup, contestant_id) do
    if contestant_id in [matchup.contestant_1_id, matchup.contestant_2_id] do
      :ok
    else
      {:error, :invalid_contestant}
    end
  end

  defp validate_not_already_voted(matchup_id, user_id) do
    if has_voted?(matchup_id, user_id) do
      {:error, :already_voted}
    else
      :ok
    end
  end

  defp broadcast_vote({:ok, vote} = result) do
    matchup = Repo.get!(Matchup, vote.matchup_id)
    counts = get_vote_counts(vote.matchup_id)

    Phoenix.PubSub.broadcast(
      BracketBattle.PubSub,
      "matchup:#{vote.matchup_id}",
      {:vote_cast, %{matchup_id: vote.matchup_id, counts: counts}}
    )

    Phoenix.PubSub.broadcast(
      BracketBattle.PubSub,
      "tournament:#{matchup.tournament_id}:votes",
      {:vote_cast, %{matchup_id: vote.matchup_id, counts: counts}}
    )

    result
  end
  defp broadcast_vote(error), do: error
end
