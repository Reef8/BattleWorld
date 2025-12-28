defmodule BracketBattle.Fixtures do
  @moduledoc """
  Factory functions for creating test data.
  """

  alias BracketBattle.Repo
  alias BracketBattle.Accounts.User
  alias BracketBattle.Tournaments.{Tournament, Contestant, Matchup}
  alias BracketBattle.Brackets.UserBracket
  alias BracketBattle.Voting.Vote

  @doc "Create a user with optional attributes"
  def create_user(attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    %User{}
    |> User.magic_link_changeset(
      Map.merge(
        %{email: "user#{unique}@test.com"},
        attrs
      )
    )
    |> Ecto.Changeset.put_change(:display_name, Map.get(attrs, :display_name, "User #{unique}"))
    |> Ecto.Changeset.put_change(:is_admin, Map.get(attrs, :is_admin, false))
    |> Repo.insert!()
  end

  @doc "Create a tournament with optional attributes"
  def create_tournament(attrs \\ %{}) do
    user = Map.get_lazy(attrs, :created_by, fn -> create_user() end)

    %Tournament{}
    |> Tournament.changeset(
      Map.merge(
        %{
          name: "Test Tournament #{System.unique_integer([:positive])}",
          status: "draft",
          bracket_size: 64,
          region_count: 4,
          region_names: ["East", "West", "South", "Midwest"],
          created_by_id: user.id
        },
        Map.drop(attrs, [:created_by])
      )
    )
    |> Repo.insert!()
  end

  @doc "Create a contestant for a tournament"
  def create_contestant(tournament, attrs \\ %{}) do
    %Contestant{}
    |> Contestant.changeset(
      Map.merge(
        %{
          name: "Contestant #{System.unique_integer([:positive])}",
          seed: Map.get(attrs, :seed, 1),
          region: Map.get(attrs, :region, "East"),
          tournament_id: tournament.id
        },
        attrs
      ),
      tournament
    )
    |> Repo.insert!()
  end

  @doc "Create all contestants for a tournament (fills all regions with seeded contestants)"
  def create_all_contestants(tournament) do
    contestants_per_region = div(tournament.bracket_size, tournament.region_count)

    for region <- tournament.region_names,
        seed <- 1..contestants_per_region do
      create_contestant(tournament, %{
        name: "#{region} Seed #{seed}",
        seed: seed,
        region: region
      })
    end
  end

  @doc "Create a matchup for a tournament"
  def create_matchup(tournament, attrs \\ %{}) do
    %Matchup{}
    |> Matchup.changeset(
      Map.merge(
        %{
          round: 1,
          position: 1,
          region: "East",
          status: "pending",
          tournament_id: tournament.id
        },
        attrs
      ),
      tournament
    )
    |> Repo.insert!()
  end

  @doc "Create a matchup with voting window open"
  def create_voting_matchup(tournament, contestant_1, contestant_2, attrs \\ %{}) do
    now = DateTime.utc_now()
    voting_ends = DateTime.add(now, 24, :hour)

    create_matchup(tournament, Map.merge(%{
      contestant_1_id: contestant_1.id,
      contestant_2_id: contestant_2.id,
      status: "voting",
      voting_starts_at: DateTime.add(now, -1, :hour),
      voting_ends_at: voting_ends
    }, attrs))
  end

  @doc "Create a matchup with voting window closed"
  def create_closed_matchup(tournament, contestant_1, contestant_2, attrs \\ %{}) do
    now = DateTime.utc_now()

    create_matchup(tournament, Map.merge(%{
      contestant_1_id: contestant_1.id,
      contestant_2_id: contestant_2.id,
      status: "voting",
      voting_starts_at: DateTime.add(now, -25, :hour),
      voting_ends_at: DateTime.add(now, -1, :hour)
    }, attrs))
  end

  @doc "Create a user bracket"
  def create_bracket(user, tournament, attrs \\ %{}) do
    # Separate score fields from regular fields (scores need score_changeset)
    score_fields = [:total_score, :correct_picks, :possible_score,
                    :round_1_score, :round_2_score, :round_3_score,
                    :round_4_score, :round_5_score, :round_6_score]

    {score_attrs, regular_attrs} = Map.split(attrs, score_fields)

    base_attrs = Map.merge(
      %{
        user_id: user.id,
        tournament_id: tournament.id,
        picks: %{},
        is_complete: false
      },
      regular_attrs
    )

    %UserBracket{}
    |> UserBracket.changeset(base_attrs)
    |> UserBracket.score_changeset(score_attrs)
    |> Repo.insert!()
  end

  @doc "Create a submitted bracket"
  def create_submitted_bracket(user, tournament, attrs \\ %{}) do
    create_bracket(user, tournament, Map.merge(%{
      submitted_at: DateTime.utc_now(),
      is_complete: true
    }, attrs))
  end

  @doc "Create a complete bracket with all picks for a 64-bracket tournament"
  def create_complete_bracket(user, tournament, picks \\ %{}) do
    # Generate picks for all 63 positions if not provided
    full_picks = if map_size(picks) == 0 do
      # Create placeholder picks (just using position numbers as contestant IDs)
      for pos <- 1..63, into: %{} do
        {to_string(pos), Ecto.UUID.generate()}
      end
    else
      picks
    end

    create_bracket(user, tournament, %{
      picks: full_picks,
      is_complete: true,
      submitted_at: DateTime.utc_now()
    })
  end

  @doc "Create a vote"
  def create_vote(user, matchup, contestant) do
    %Vote{}
    |> Vote.changeset(%{
      user_id: user.id,
      matchup_id: matchup.id,
      contestant_id: contestant.id
    })
    |> Repo.insert!()
  end

  @doc "Create multiple votes for a matchup to set up tie scenarios"
  def create_tie_votes(matchup, count_per_contestant) do
    for _ <- 1..count_per_contestant do
      user = create_user()
      create_vote(user, matchup, %{id: matchup.contestant_1_id})
    end

    for _ <- 1..count_per_contestant do
      user = create_user()
      create_vote(user, matchup, %{id: matchup.contestant_2_id})
    end
  end

  @doc "Calculate expected total picks for a bracket size"
  def expected_picks_for_bracket_size(bracket_size) do
    # Total matchups = bracket_size - 1
    bracket_size - 1
  end
end
