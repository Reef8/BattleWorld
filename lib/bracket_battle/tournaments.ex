defmodule BracketBattle.Tournaments do
  @moduledoc """
  Context for tournament management - creation, state transitions, and matchups.
  """

  import Ecto.Query
  alias BracketBattle.Repo
  alias BracketBattle.Tournaments.{Tournament, Contestant, Matchup}

  # ============================================================================
  # TOURNAMENT CRUD
  # ============================================================================

  @doc "Get the current active tournament (only one at a time)"
  def get_active_tournament do
    from(t in Tournament,
      where: t.status in ["registration", "active"],
      order_by: [desc: t.inserted_at],
      limit: 1
    )
    |> Repo.one()
    |> Repo.preload([:contestants, :matchups, :created_by])
  end

  @doc "Get tournament by ID with preloads"
  def get_tournament!(id) do
    Tournament
    |> Repo.get!(id)
    |> Repo.preload([:contestants, :matchups, :created_by])
  end

  @doc "Get tournament by ID, returns nil if not found"
  def get_tournament(id) do
    case Repo.get(Tournament, id) do
      nil -> nil
      tournament -> Repo.preload(tournament, [:contestants, :matchups, :created_by])
    end
  end

  @doc "List all tournaments"
  def list_tournaments do
    from(t in Tournament, order_by: [desc: t.inserted_at])
    |> Repo.all()
    |> Repo.preload(:created_by)
  end

  @doc "Create a new tournament (admin only)"
  def create_tournament(attrs, admin_user) do
    %Tournament{}
    |> Tournament.changeset(Map.put(attrs, "created_by_id", admin_user.id))
    |> Repo.insert()
  end

  @doc "Update tournament details"
  def update_tournament(%Tournament{} = tournament, attrs) do
    tournament
    |> Tournament.changeset(attrs)
    |> Repo.update()
  end

  @doc "Delete tournament"
  def delete_tournament(%Tournament{} = tournament) do
    Repo.delete(tournament)
  end

  # ============================================================================
  # TOURNAMENT STATE MACHINE
  # ============================================================================

  @doc "Transition: draft -> registration (after 64 contestants added)"
  def open_registration(%Tournament{status: "draft"} = tournament) do
    if count_contestants(tournament.id) == 64 do
      tournament
      |> Tournament.changeset(%{status: "registration"})
      |> Repo.update()
      |> broadcast_tournament_update()
    else
      {:error, :incomplete_contestants}
    end
  end

  @doc "Transition: registration -> active (starts round 1)"
  def start_tournament(%Tournament{status: "registration"} = tournament) do
    Repo.transaction(fn ->
      # Generate all 63 matchups
      generate_all_matchups(tournament)

      # Activate round 1 voting
      activate_round(tournament, 1)

      # Update tournament status
      tournament
      |> Tournament.changeset(%{
        status: "active",
        started_at: DateTime.utc_now(),
        current_round: 1
      })
      |> Repo.update!()
    end)
    |> broadcast_tournament_update()
  end

  @doc "Advance to next round after all matchups decided"
  def advance_round(%Tournament{status: "active", current_round: round} = tournament) do
    if all_matchups_decided?(tournament, round) do
      next_round = round + 1

      if next_round > 6 do
        complete_tournament(tournament)
      else
        Repo.transaction(fn ->
          # Populate next round matchups with winners
          populate_next_round(tournament, next_round)

          # Activate voting for next round
          activate_round(tournament, next_round)

          tournament
          |> Tournament.changeset(%{current_round: next_round})
          |> Repo.update!()
        end)
        |> broadcast_tournament_update()
      end
    else
      {:error, :matchups_pending}
    end
  end

  @doc "Complete the tournament"
  def complete_tournament(%Tournament{} = tournament) do
    tournament
    |> Tournament.changeset(%{
      status: "completed",
      completed_at: DateTime.utc_now()
    })
    |> Repo.update()
    |> broadcast_tournament_update()
  end

  # ============================================================================
  # CONTESTANTS
  # ============================================================================

  @doc "Add contestant to tournament"
  def add_contestant(%Tournament{} = tournament, attrs) do
    # Convert all keys to strings to avoid mixed key errors
    string_attrs = for {k, v} <- attrs, into: %{}, do: {to_string(k), v}

    %Contestant{}
    |> Contestant.changeset(Map.put(string_attrs, "tournament_id", tournament.id))
    |> Repo.insert()
  end

  @doc "Update contestant"
  def update_contestant(%Contestant{} = contestant, attrs) do
    contestant
    |> Contestant.changeset(attrs)
    |> Repo.update()
  end

  @doc "Delete contestant"
  def delete_contestant(%Contestant{} = contestant) do
    Repo.delete(contestant)
  end

  @doc "Get contestant by ID"
  def get_contestant!(id), do: Repo.get!(Contestant, id)

  @doc "List contestants for tournament"
  def list_contestants(tournament_id) do
    from(c in Contestant,
      where: c.tournament_id == ^tournament_id,
      order_by: [asc: c.region, asc: c.seed]
    )
    |> Repo.all()
  end

  @doc "Count contestants for tournament"
  def count_contestants(tournament_id) do
    from(c in Contestant, where: c.tournament_id == ^tournament_id, select: count())
    |> Repo.one()
  end

  # ============================================================================
  # MATCHUPS
  # ============================================================================

  @doc "Get matchups for a specific round"
  def get_matchups_by_round(tournament_id, round) do
    from(m in Matchup,
      where: m.tournament_id == ^tournament_id and m.round == ^round,
      order_by: [asc: m.position],
      preload: [:contestant_1, :contestant_2, :winner]
    )
    |> Repo.all()
  end

  @doc "Get all matchups for tournament"
  def get_all_matchups(tournament_id) do
    from(m in Matchup,
      where: m.tournament_id == ^tournament_id,
      order_by: [asc: m.round, asc: m.position],
      preload: [:contestant_1, :contestant_2, :winner]
    )
    |> Repo.all()
  end

  @doc "Get currently voting matchups"
  def get_active_matchups(tournament_id) do
    from(m in Matchup,
      where: m.tournament_id == ^tournament_id and m.status == "voting",
      preload: [:contestant_1, :contestant_2]
    )
    |> Repo.all()
  end

  @doc "Get matchup by ID"
  def get_matchup!(id) do
    Matchup
    |> Repo.get!(id)
    |> Repo.preload([:contestant_1, :contestant_2, :winner, :tournament])
  end

  @doc "Decide matchup winner (called by Oban job or admin)"
  def decide_matchup(%Matchup{} = matchup, winner_id, admin_decided \\ false) do
    matchup
    |> Matchup.changeset(%{
      winner_id: winner_id,
      status: "decided",
      decided_at: DateTime.utc_now(),
      admin_decided: admin_decided
    })
    |> Repo.update()
    |> broadcast_matchup_update()
  end

  # ============================================================================
  # PRIVATE HELPERS
  # ============================================================================

  defp generate_all_matchups(tournament) do
    contestants = list_contestants(tournament.id)

    # Group by region
    by_region = Enum.group_by(contestants, & &1.region)

    # Generate Round 1 matchups (32 games)
    # Standard NCAA seeding: 1v16, 8v9, 5v12, 4v13, 6v11, 3v14, 7v10, 2v15
    seed_pairs = [{1, 16}, {8, 9}, {5, 12}, {4, 13}, {6, 11}, {3, 14}, {7, 10}, {2, 15}]

    regions = ["East", "West", "South", "Midwest"]

    # Generate Round 1 matchups
    {_, round_1_matchups} =
      Enum.reduce(regions, {1, []}, fn region, {pos, matchups} ->
        region_contestants = Map.get(by_region, region, [])

        {new_pos, new_matchups} =
          Enum.reduce(seed_pairs, {pos, matchups}, fn {seed_a, seed_b}, {p, m} ->
            c1 = Enum.find(region_contestants, & &1.seed == seed_a)
            c2 = Enum.find(region_contestants, & &1.seed == seed_b)

            {:ok, matchup} =
              %Matchup{}
              |> Matchup.changeset(%{
                tournament_id: tournament.id,
                round: 1,
                position: p,
                region: region,
                contestant_1_id: c1 && c1.id,
                contestant_2_id: c2 && c2.id,
                status: "pending"
              })
              |> Repo.insert()

            {p + 1, [matchup | m]}
          end)

        {new_pos, new_matchups}
      end)

    # Generate placeholder matchups for rounds 2-6
    for round <- 2..6 do
      matchups_in_round = div(64, trunc(:math.pow(2, round)))

      for pos <- 1..matchups_in_round do
        region = if round <= 4, do: get_region_for_position(round, pos), else: nil

        %Matchup{}
        |> Matchup.changeset(%{
          tournament_id: tournament.id,
          round: round,
          position: pos,
          region: region,
          status: "pending"
        })
        |> Repo.insert!()
      end
    end

    round_1_matchups
  end

  defp get_region_for_position(round, pos) do
    # For rounds 2-4, determine which region based on position
    # Each region has: 4 matchups in R2, 2 in R3, 1 in R4
    regions = ["East", "West", "South", "Midwest"]

    case round do
      2 ->
        # R2: positions 1-4 = East, 5-8 = West, 9-12 = South, 13-16 = Midwest
        Enum.at(regions, div(pos - 1, 4))

      3 ->
        # R3: positions 1-2 = East, 3-4 = West, 5-6 = South, 7-8 = Midwest
        Enum.at(regions, div(pos - 1, 2))

      4 ->
        # R4 (Elite 8): positions 1 = East, 2 = West, 3 = South, 4 = Midwest
        Enum.at(regions, pos - 1)

      _ ->
        nil
    end
  end

  defp activate_round(tournament, round) do
    now = DateTime.utc_now()
    voting_end = DateTime.add(now, 24, :hour)

    from(m in Matchup,
      where: m.tournament_id == ^tournament.id and m.round == ^round
    )
    |> Repo.update_all(set: [
      status: "voting",
      voting_starts_at: now,
      voting_ends_at: voting_end
    ])
  end

  defp populate_next_round(tournament, round) do
    previous_round = round - 1
    previous_matchups = get_matchups_by_round(tournament.id, previous_round)
    next_matchups = get_matchups_by_round(tournament.id, round)

    # Winners from previous round, paired for next round
    winners = Enum.map(previous_matchups, & &1.winner_id)
    winner_pairs = Enum.chunk_every(winners, 2)

    Enum.zip(winner_pairs, next_matchups)
    |> Enum.each(fn {[w1, w2], matchup} ->
      matchup
      |> Matchup.changeset(%{contestant_1_id: w1, contestant_2_id: w2})
      |> Repo.update!()
    end)
  end

  defp all_matchups_decided?(tournament, round) do
    from(m in Matchup,
      where: m.tournament_id == ^tournament.id
        and m.round == ^round
        and m.status != "decided",
      select: count()
    )
    |> Repo.one() == 0
  end

  defp broadcast_tournament_update({:ok, tournament} = result) do
    Phoenix.PubSub.broadcast(BracketBattle.PubSub, "tournament:#{tournament.id}", {:tournament_updated, tournament})
    Phoenix.PubSub.broadcast(BracketBattle.PubSub, "tournaments", {:tournament_updated, tournament})
    result
  end
  defp broadcast_tournament_update(error), do: error

  defp broadcast_matchup_update({:ok, matchup} = result) do
    Phoenix.PubSub.broadcast(BracketBattle.PubSub, "tournament:#{matchup.tournament_id}", {:matchup_updated, matchup})
    result
  end
  defp broadcast_matchup_update(error), do: error
end
