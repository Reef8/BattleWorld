defmodule BracketBattle.VotingTest do
  use BracketBattle.DataCase, async: true

  alias BracketBattle.Voting
  alias BracketBattle.Fixtures

  describe "cast_vote/3" do
    setup do
      user = Fixtures.create_user()
      tournament = Fixtures.create_tournament(%{status: "active"})
      contestant_1 = Fixtures.create_contestant(tournament, %{seed: 1, region: "East"})
      contestant_2 = Fixtures.create_contestant(tournament, %{seed: 2, region: "East"})

      # Create submitted bracket for user (required to vote)
      Fixtures.create_submitted_bracket(user, tournament)

      matchup = Fixtures.create_voting_matchup(tournament, contestant_1, contestant_2)

      %{
        user: user,
        tournament: tournament,
        contestant_1: contestant_1,
        contestant_2: contestant_2,
        matchup: matchup
      }
    end

    test "succeeds and creates vote", %{user: user, matchup: matchup, contestant_1: c1} do
      assert {:ok, vote} = Voting.cast_vote(matchup.id, user.id, c1.id)
      assert vote.matchup_id == matchup.id
      assert vote.user_id == user.id
      assert vote.contestant_id == c1.id
    end

    test "updates vote count after casting", %{user: user, matchup: matchup, contestant_1: c1} do
      assert Voting.get_total_votes(matchup.id) == 0

      {:ok, _} = Voting.cast_vote(matchup.id, user.id, c1.id)

      assert Voting.get_total_votes(matchup.id) == 1
    end

    test "changing vote replaces previous vote", %{
      user: user,
      matchup: matchup,
      contestant_1: c1,
      contestant_2: c2
    } do
      {:ok, vote1} = Voting.cast_vote(matchup.id, user.id, c1.id)
      assert vote1.contestant_id == c1.id

      {:ok, vote2} = Voting.cast_vote(matchup.id, user.id, c2.id)
      assert vote2.contestant_id == c2.id

      # Total votes should still be 1 (replaced, not added)
      assert Voting.get_total_votes(matchup.id) == 1

      # Vote counts should show 1 for c2, 0 for c1
      counts = Voting.get_vote_counts(matchup.id)
      assert Map.get(counts, c1.id, 0) == 0
      assert Map.get(counts, c2.id, 0) == 1
    end

    test "fails when voting window closed", %{user: user, tournament: tournament} do
      contestant_1 = Fixtures.create_contestant(tournament, %{seed: 3, region: "West"})
      contestant_2 = Fixtures.create_contestant(tournament, %{seed: 4, region: "West"})

      closed_matchup = Fixtures.create_closed_matchup(tournament, contestant_1, contestant_2, %{
        position: 2,
        region: "West"
      })

      assert {:error, :voting_closed} = Voting.cast_vote(closed_matchup.id, user.id, contestant_1.id)
    end

    test "fails without submitted bracket", %{
      matchup: matchup,
      contestant_1: c1
    } do
      # Create user without a bracket
      user_without_bracket = Fixtures.create_user()

      assert {:error, :bracket_required} = Voting.cast_vote(matchup.id, user_without_bracket.id, c1.id)
    end

    test "fails with invalid contestant", %{user: user, tournament: tournament, matchup: matchup} do
      other_contestant = Fixtures.create_contestant(tournament, %{seed: 5, region: "South"})

      assert {:error, :invalid_contestant} = Voting.cast_vote(matchup.id, user.id, other_contestant.id)
    end
  end

  describe "tally_matchup/1" do
    setup do
      tournament = Fixtures.create_tournament(%{status: "active"})
      contestant_1 = Fixtures.create_contestant(tournament, %{seed: 1, region: "East"})
      contestant_2 = Fixtures.create_contestant(tournament, %{seed: 2, region: "East"})

      matchup = Fixtures.create_voting_matchup(tournament, contestant_1, contestant_2)

      %{
        tournament: tournament,
        contestant_1: contestant_1,
        contestant_2: contestant_2,
        matchup: matchup
      }
    end

    test "returns winner when contestant_1 has more votes", %{
      matchup: matchup,
      tournament: tournament,
      contestant_1: c1,
      contestant_2: c2
    } do
      # Create 3 votes for c1, 1 for c2
      for _ <- 1..3 do
        user = Fixtures.create_user()
        Fixtures.create_submitted_bracket(user, tournament)
        Fixtures.create_vote(user, matchup, c1)
      end

      user = Fixtures.create_user()
      Fixtures.create_submitted_bracket(user, tournament)
      Fixtures.create_vote(user, matchup, c2)

      result = Voting.tally_matchup(matchup)
      assert {:ok, decided_matchup} = result
      assert decided_matchup.winner_id == c1.id
    end

    test "returns winner when contestant_2 has more votes", %{
      matchup: matchup,
      tournament: tournament,
      contestant_1: c1,
      contestant_2: c2
    } do
      # Create 1 vote for c1, 3 for c2
      user1 = Fixtures.create_user()
      Fixtures.create_submitted_bracket(user1, tournament)
      Fixtures.create_vote(user1, matchup, c1)

      for _ <- 1..3 do
        user = Fixtures.create_user()
        Fixtures.create_submitted_bracket(user, tournament)
        Fixtures.create_vote(user, matchup, c2)
      end

      result = Voting.tally_matchup(matchup)
      assert {:ok, decided_matchup} = result
      assert decided_matchup.winner_id == c2.id
    end

    test "returns tie when votes are equal", %{
      matchup: matchup,
      tournament: tournament,
      contestant_1: c1,
      contestant_2: c2
    } do
      # Create 2 votes for each contestant
      for _ <- 1..2 do
        user = Fixtures.create_user()
        Fixtures.create_submitted_bracket(user, tournament)
        Fixtures.create_vote(user, matchup, c1)
      end

      for _ <- 1..2 do
        user = Fixtures.create_user()
        Fixtures.create_submitted_bracket(user, tournament)
        Fixtures.create_vote(user, matchup, c2)
      end

      result = Voting.tally_matchup(matchup)

      # BUG: This returns {:tie, matchup_id, c1_votes, c2_votes} which is not properly handled
      # The test documents the current behavior - fix should make this return something usable
      assert {:tie, matchup_id, votes_1, votes_2} = result
      assert matchup_id == matchup.id
      assert votes_1 == 2
      assert votes_2 == 2
    end

    test "returns tie when no votes cast (0-0)", %{matchup: matchup} do
      result = Voting.tally_matchup(matchup)

      assert {:tie, matchup_id, 0, 0} = result
      assert matchup_id == matchup.id
    end
  end

  describe "get_vote_counts/1" do
    test "returns empty map when no votes" do
      tournament = Fixtures.create_tournament(%{status: "active"})
      contestant_1 = Fixtures.create_contestant(tournament, %{seed: 1, region: "East"})
      contestant_2 = Fixtures.create_contestant(tournament, %{seed: 2, region: "East"})
      matchup = Fixtures.create_voting_matchup(tournament, contestant_1, contestant_2)

      assert Voting.get_vote_counts(matchup.id) == %{}
    end

    test "returns correct counts for each contestant" do
      tournament = Fixtures.create_tournament(%{status: "active"})
      contestant_1 = Fixtures.create_contestant(tournament, %{seed: 1, region: "East"})
      contestant_2 = Fixtures.create_contestant(tournament, %{seed: 2, region: "East"})
      matchup = Fixtures.create_voting_matchup(tournament, contestant_1, contestant_2)

      # 3 votes for c1
      for _ <- 1..3 do
        user = Fixtures.create_user()
        Fixtures.create_submitted_bracket(user, tournament)
        Fixtures.create_vote(user, matchup, contestant_1)
      end

      # 2 votes for c2
      for _ <- 1..2 do
        user = Fixtures.create_user()
        Fixtures.create_submitted_bracket(user, tournament)
        Fixtures.create_vote(user, matchup, contestant_2)
      end

      counts = Voting.get_vote_counts(matchup.id)
      assert counts[contestant_1.id] == 3
      assert counts[contestant_2.id] == 2
    end
  end

  describe "has_voted?/2" do
    test "returns false when user has not voted" do
      user = Fixtures.create_user()
      tournament = Fixtures.create_tournament(%{status: "active"})
      contestant_1 = Fixtures.create_contestant(tournament, %{seed: 1, region: "East"})
      contestant_2 = Fixtures.create_contestant(tournament, %{seed: 2, region: "East"})
      matchup = Fixtures.create_voting_matchup(tournament, contestant_1, contestant_2)

      refute Voting.has_voted?(matchup.id, user.id)
    end

    test "returns true when user has voted" do
      user = Fixtures.create_user()
      tournament = Fixtures.create_tournament(%{status: "active"})
      contestant_1 = Fixtures.create_contestant(tournament, %{seed: 1, region: "East"})
      contestant_2 = Fixtures.create_contestant(tournament, %{seed: 2, region: "East"})
      matchup = Fixtures.create_voting_matchup(tournament, contestant_1, contestant_2)

      Fixtures.create_submitted_bracket(user, tournament)
      Fixtures.create_vote(user, matchup, contestant_1)

      assert Voting.has_voted?(matchup.id, user.id)
    end
  end
end
