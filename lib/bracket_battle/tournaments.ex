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

  @doc "Transition: draft -> registration (after all contestants added)"
  def open_registration(%Tournament{status: "draft"} = tournament) do
    expected_count = tournament.bracket_size || 64

    if count_contestants(tournament.id) == expected_count do
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

  @doc "End current round early - tally votes and decide winners"
  def end_round_early(%Tournament{status: "active", current_round: round} = tournament) do
    alias BracketBattle.Voting
    alias BracketBattle.Scoring

    result = Repo.transaction(fn ->
      # Get all voting matchups for current round
      matchups = get_matchups_by_round(tournament.id, round)
                 |> Enum.filter(& &1.status == "voting")

      # Tally each and decide winners (ties left undecided)
      ties = Enum.reduce(matchups, [], fn matchup, acc ->
        case Voting.tally_matchup(matchup) do
          {:ok, _} -> acc
          {:tie, matchup_id, _, _} -> [matchup_id | acc]
        end
      end)

      if Enum.empty?(ties) do
        # Reload tournament to get fresh state
        fresh_tournament = get_tournament!(tournament.id)
        # All decided, advance to next round
        case advance_round(fresh_tournament) do
          {:ok, updated} -> {:advanced, updated}
          {:error, reason} -> Repo.rollback(reason)
        end
      else
        {:ties_pending, ties}
      end
    end)

    # Recalculate scores after matchups decided
    case result do
      {:ok, _} -> Scoring.recalculate_all_scores(tournament.id)
      _ -> :ok
    end

    result
  end

  @doc "Advance to next round after all matchups decided"
  def advance_round(%Tournament{status: "active", current_round: round} = tournament) do
    total_rounds = Tournament.total_rounds(tournament)

    if all_matchups_decided?(tournament, round) do
      next_round = round + 1

      if next_round > total_rounds do
        complete_tournament(tournament)
      else
        result = Repo.transaction(fn ->
          # Populate next round matchups with winners
          populate_next_round(tournament, next_round)

          # Activate voting for next round
          activate_round(tournament, next_round)

          tournament
          |> Tournament.changeset(%{current_round: next_round})
          |> Repo.update!()
        end)
        |> broadcast_tournament_update()

        # Broadcast round completion event for celebration banner
        case result do
          {:ok, updated_tournament} ->
            completed_round_name = get_round_name(tournament, round)
            broadcast_round_completed(updated_tournament, round, completed_round_name)
          _ -> :ok
        end

        result
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
    |> Contestant.changeset(Map.put(string_attrs, "tournament_id", tournament.id), tournament)
    |> Repo.insert()
  end

  @doc "Update contestant"
  def update_contestant(%Contestant{} = contestant, attrs, tournament \\ nil) do
    contestant
    |> Contestant.changeset(attrs, tournament)
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
  # ROUND NAME HELPERS
  # ============================================================================

  @doc "Generate default round names based on bracket size"
  def default_round_names(bracket_size) do
    total = trunc(:math.log2(bracket_size))

    # Build from the end (Championship) backwards
    base = %{total => "Championship"}

    base
    |> maybe_add_round_name(total, 1, "Final Four")
    |> maybe_add_round_name(total, 2, "Elite 8")
    |> maybe_add_round_name(total, 3, "Sweet 16")
    |> fill_remaining_rounds(total)
  end

  defp maybe_add_round_name(names, total, offset, name) do
    round = total - offset
    if round >= 1, do: Map.put(names, round, name), else: names
  end

  defp fill_remaining_rounds(names, total) do
    Enum.reduce(1..total, names, fn round, acc ->
      if Map.has_key?(acc, round), do: acc, else: Map.put(acc, round, "Round #{round}")
    end)
  end

  @doc "Get round name for a tournament"
  def get_round_name(%Tournament{round_names: custom, bracket_size: size}, round) do
    # Try custom name first (handle both integer and string keys)
    custom_name = Map.get(custom || %{}, round) || Map.get(custom || %{}, to_string(round))

    if custom_name && custom_name != "" do
      custom_name
    else
      # Fall back to default
      default_names = default_round_names(size || 64)
      Map.get(default_names, round, "Round #{round}")
    end
  end

  # ============================================================================
  # PRIVATE HELPERS
  # ============================================================================

  defp generate_all_matchups(tournament) do
    contestants = list_contestants(tournament.id)

    # Get tournament configuration
    bracket_size = tournament.bracket_size || 64
    _region_count = tournament.region_count || 4
    region_names = tournament.region_names || ["East", "West", "South", "Midwest"]
    contestants_per_region = Tournament.contestants_per_region(tournament)
    total_rounds = Tournament.total_rounds(tournament)

    # Group by region
    by_region = Enum.group_by(contestants, & &1.region)

    # Get seeding pattern for this bracket size
    seed_pairs = seeding_pattern(contestants_per_region)

    # Generate Round 1 matchups
    {_, round_1_matchups} =
      Enum.reduce(region_names, {1, []}, fn region, {pos, matchups} ->
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

    # Calculate how many rounds have regions (before Final Four equivalent)
    region_rounds = calculate_region_rounds(contestants_per_region)

    # Generate placeholder matchups for rounds 2+
    for round <- 2..total_rounds do
      matchups_in_round = div(bracket_size, trunc(:math.pow(2, round)))

      for pos <- 1..matchups_in_round do
        region = if round <= region_rounds do
          get_region_for_position(round, pos, region_names, contestants_per_region)
        else
          nil
        end

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

  # Calculate how many rounds have regional matchups
  defp calculate_region_rounds(contestants_per_region) do
    # Rounds with regions = log2(contestants_per_region)
    # e.g., 16 per region = 4 rounds (R1-R4), then Final Four+
    trunc(:math.log2(contestants_per_region))
  end

  defp get_region_for_position(round, pos, region_names, contestants_per_region) do
    # Calculate matchups per region in this round
    matchups_per_region = div(contestants_per_region, trunc(:math.pow(2, round)))

    if matchups_per_region >= 1 do
      region_index = div(pos - 1, matchups_per_region)
      Enum.at(region_names, region_index)
    else
      nil
    end
  end

  @doc "Get seeding pattern for a given number of contestants per region"
  def seeding_pattern(contestants_per_region) do
    case contestants_per_region do
      2 -> [{1, 2}]
      4 -> [{1, 4}, {2, 3}]
      8 -> [{1, 8}, {4, 5}, {3, 6}, {2, 7}]
      16 -> [{1, 16}, {8, 9}, {5, 12}, {4, 13}, {6, 11}, {3, 14}, {7, 10}, {2, 15}]
      32 -> generate_seeding_pattern(32)
      _ -> generate_seeding_pattern(contestants_per_region)
    end
  end

  defp generate_seeding_pattern(size) do
    # Standard bracket seeding: 1 vs size, then recursively fill
    # This ensures proper bracket placement
    do_generate_seeds(1, size)
  end

  defp do_generate_seeds(low, high) when low >= high, do: []
  defp do_generate_seeds(low, high) do
    [{low, high}] ++ do_generate_seeds(low + 1, high - 1)
    |> Enum.take(div(high - low + 1, 2))
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

  defp broadcast_round_completed(tournament, completed_round, round_name) do
    Phoenix.PubSub.broadcast(
      BracketBattle.PubSub,
      "tournament:#{tournament.id}",
      {:round_completed, %{round: completed_round, round_name: round_name}}
    )
  end
end
