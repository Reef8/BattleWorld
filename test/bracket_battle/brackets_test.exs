defmodule BracketBattle.BracketsTest do
  use BracketBattle.DataCase, async: true

  alias BracketBattle.Brackets
  alias BracketBattle.Fixtures

  describe "get_or_create_bracket/2" do
    test "creates new bracket if none exists" do
      user = Fixtures.create_user()
      tournament = Fixtures.create_tournament()

      assert {:ok, bracket} = Brackets.get_or_create_bracket(tournament.id, user.id)
      assert bracket.user_id == user.id
      assert bracket.tournament_id == tournament.id
      assert bracket.picks == %{}
      assert bracket.is_complete == false
    end

    test "returns existing bracket if one exists" do
      user = Fixtures.create_user()
      tournament = Fixtures.create_tournament()

      {:ok, bracket1} = Brackets.get_or_create_bracket(tournament.id, user.id)
      {:ok, bracket2} = Brackets.get_or_create_bracket(tournament.id, user.id)

      assert bracket1.id == bracket2.id
    end
  end

  describe "update_picks/2" do
    test "saves picks to bracket" do
      user = Fixtures.create_user()
      tournament = Fixtures.create_tournament()
      bracket = Fixtures.create_bracket(user, tournament)

      picks = %{"1" => "contestant_a", "2" => "contestant_b"}

      {:ok, updated} = Brackets.update_picks(bracket, picks)

      assert updated.picks == picks
    end

    test "marks bracket complete at 63 picks for 64-bracket" do
      user = Fixtures.create_user()
      tournament = Fixtures.create_tournament(%{bracket_size: 64})
      bracket = Fixtures.create_bracket(user, tournament)

      # Create 63 picks
      picks = for pos <- 1..63, into: %{} do
        {to_string(pos), Ecto.UUID.generate()}
      end

      {:ok, updated} = Brackets.update_picks(bracket, picks)

      assert updated.is_complete == true
    end

    test "does NOT mark complete with fewer than 63 picks" do
      user = Fixtures.create_user()
      tournament = Fixtures.create_tournament(%{bracket_size: 64})
      bracket = Fixtures.create_bracket(user, tournament)

      # Only 50 picks
      picks = for pos <- 1..50, into: %{} do
        {to_string(pos), Ecto.UUID.generate()}
      end

      {:ok, updated} = Brackets.update_picks(bracket, picks)

      assert updated.is_complete == false
    end

    test "does NOT mark complete if any pick is nil" do
      user = Fixtures.create_user()
      tournament = Fixtures.create_tournament(%{bracket_size: 64})
      bracket = Fixtures.create_bracket(user, tournament)

      # 63 picks but one is nil
      picks = for pos <- 1..63, into: %{} do
        if pos == 30 do
          {to_string(pos), nil}
        else
          {to_string(pos), Ecto.UUID.generate()}
        end
      end

      {:ok, updated} = Brackets.update_picks(bracket, picks)

      assert updated.is_complete == false
    end
  end

  describe "submit_bracket/1" do
    test "succeeds for complete bracket during registration" do
      user = Fixtures.create_user()
      tournament = Fixtures.create_tournament(%{status: "registration", bracket_size: 64})

      picks = for pos <- 1..63, into: %{} do
        {to_string(pos), Ecto.UUID.generate()}
      end

      bracket = Fixtures.create_bracket(user, tournament, %{picks: picks, is_complete: true})

      {:ok, submitted} = Brackets.submit_bracket(bracket)

      assert submitted.submitted_at != nil
    end

    test "fails after registration closes" do
      user = Fixtures.create_user()
      tournament = Fixtures.create_tournament(%{status: "active", bracket_size: 64})

      picks = for pos <- 1..63, into: %{} do
        {to_string(pos), Ecto.UUID.generate()}
      end

      bracket = Fixtures.create_bracket(user, tournament, %{picks: picks, is_complete: true})

      assert {:error, :registration_closed} = Brackets.submit_bracket(bracket)
    end

    test "fails if bracket incomplete" do
      user = Fixtures.create_user()
      tournament = Fixtures.create_tournament(%{status: "registration"})
      bracket = Fixtures.create_bracket(user, tournament, %{is_complete: false})

      assert {:error, :incomplete_bracket} = Brackets.submit_bracket(bracket)
    end
  end

  describe "has_submitted_bracket?/2" do
    test "returns false for unsubmitted bracket" do
      user = Fixtures.create_user()
      tournament = Fixtures.create_tournament()
      Fixtures.create_bracket(user, tournament)

      refute Brackets.has_submitted_bracket?(tournament.id, user.id)
    end

    test "returns true for submitted bracket" do
      user = Fixtures.create_user()
      tournament = Fixtures.create_tournament()
      Fixtures.create_submitted_bracket(user, tournament)

      assert Brackets.has_submitted_bracket?(tournament.id, user.id)
    end

    test "returns false when no bracket exists" do
      user = Fixtures.create_user()
      tournament = Fixtures.create_tournament()

      refute Brackets.has_submitted_bracket?(tournament.id, user.id)
    end
  end

  describe "get_leaderboard/2" do
    test "returns brackets ordered by score then correct_picks" do
      tournament = Fixtures.create_tournament()
      now = DateTime.utc_now()

      # Create 3 users with different scores
      user1 = Fixtures.create_user()
      user2 = Fixtures.create_user()
      user3 = Fixtures.create_user()

      # User2 has highest score (submitted first)
      Fixtures.create_submitted_bracket(user2, tournament, %{
        total_score: 100,
        correct_picks: 5,
        submitted_at: DateTime.add(now, -3, :hour)
      })

      # User1 has medium score (submitted second)
      Fixtures.create_submitted_bracket(user1, tournament, %{
        total_score: 50,
        correct_picks: 3,
        submitted_at: DateTime.add(now, -2, :hour)
      })

      # User3 has same score as user1 but more correct picks (submitted last)
      Fixtures.create_submitted_bracket(user3, tournament, %{
        total_score: 50,
        correct_picks: 8,
        submitted_at: DateTime.add(now, -1, :hour)
      })

      leaderboard = Brackets.get_leaderboard(tournament.id)

      assert length(leaderboard) == 3

      [first, second, third] = leaderboard
      assert first.user_id == user2.id
      assert first.rank == 1

      # user3 should be ahead of user1 due to more correct_picks (same score)
      assert second.user_id == user3.id
      assert second.rank == 2

      assert third.user_id == user1.id
      assert third.rank == 3
    end

    test "respects limit and offset" do
      tournament = Fixtures.create_tournament()

      for i <- 1..10 do
        user = Fixtures.create_user()
        Fixtures.create_submitted_bracket(user, tournament, %{total_score: 100 - i})
      end

      page_1 = Brackets.get_leaderboard(tournament.id, limit: 3, offset: 0)
      page_2 = Brackets.get_leaderboard(tournament.id, limit: 3, offset: 3)

      assert length(page_1) == 3
      assert length(page_2) == 3

      # Pages should have different users
      page_1_ids = Enum.map(page_1, & &1.user_id)
      page_2_ids = Enum.map(page_2, & &1.user_id)

      assert Enum.empty?(page_1_ids -- page_1_ids -- page_2_ids)
    end

    test "only includes submitted brackets" do
      tournament = Fixtures.create_tournament()

      user1 = Fixtures.create_user()
      user2 = Fixtures.create_user()

      # Submitted
      Fixtures.create_submitted_bracket(user1, tournament)
      # Not submitted
      Fixtures.create_bracket(user2, tournament)

      leaderboard = Brackets.get_leaderboard(tournament.id)

      assert length(leaderboard) == 1
      assert hd(leaderboard).user_id == user1.id
    end
  end

  describe "get_user_rank/2" do
    test "returns correct rank for user" do
      tournament = Fixtures.create_tournament()

      user1 = Fixtures.create_user()
      user2 = Fixtures.create_user()
      user3 = Fixtures.create_user()

      # User2 leads
      Fixtures.create_submitted_bracket(user2, tournament, %{total_score: 100})
      # User1 is second
      Fixtures.create_submitted_bracket(user1, tournament, %{total_score: 50})
      # User3 is third
      Fixtures.create_submitted_bracket(user3, tournament, %{total_score: 25})

      assert Brackets.get_user_rank(tournament.id, user2.id) == 1
      assert Brackets.get_user_rank(tournament.id, user1.id) == 2
      assert Brackets.get_user_rank(tournament.id, user3.id) == 3
    end

    test "returns nil if user has no submitted bracket" do
      tournament = Fixtures.create_tournament()
      user = Fixtures.create_user()

      assert Brackets.get_user_rank(tournament.id, user.id) == nil
    end

    test "handles ties correctly - same rank for same score and correct_picks" do
      tournament = Fixtures.create_tournament()

      user1 = Fixtures.create_user()
      user2 = Fixtures.create_user()
      user3 = Fixtures.create_user()

      # User1 and User2 tied
      Fixtures.create_submitted_bracket(user1, tournament, %{total_score: 100, correct_picks: 10})
      Fixtures.create_submitted_bracket(user2, tournament, %{total_score: 100, correct_picks: 10})
      # User3 behind
      Fixtures.create_submitted_bracket(user3, tournament, %{total_score: 50, correct_picks: 5})

      # Both tied users should be rank 1 (no one ahead of them)
      assert Brackets.get_user_rank(tournament.id, user1.id) == 1
      assert Brackets.get_user_rank(tournament.id, user2.id) == 1
      assert Brackets.get_user_rank(tournament.id, user3.id) == 3
    end
  end

  describe "expected_picks_for_bracket_size (fixture helper)" do
    test "calculates correctly for all sizes" do
      assert Fixtures.expected_picks_for_bracket_size(8) == 7
      assert Fixtures.expected_picks_for_bracket_size(16) == 15
      assert Fixtures.expected_picks_for_bracket_size(32) == 31
      assert Fixtures.expected_picks_for_bracket_size(64) == 63
      assert Fixtures.expected_picks_for_bracket_size(128) == 127
    end
  end

  describe "dynamic picks count based on bracket size" do
    test "32-bracket marks complete at 31 picks (bracket_size - 1)" do
      user = Fixtures.create_user()
      tournament = Fixtures.create_tournament(%{bracket_size: 32, region_count: 4})
      bracket = Fixtures.create_bracket(user, tournament)

      # Create 31 picks (correct for 32-bracket)
      picks = for pos <- 1..31, into: %{} do
        {to_string(pos), Ecto.UUID.generate()}
      end

      {:ok, updated} = Brackets.update_picks(bracket, picks)

      # Fixed: now correctly uses tournament bracket_size
      assert updated.is_complete == true
    end

    test "16-bracket marks complete at 15 picks (bracket_size - 1)" do
      user = Fixtures.create_user()
      tournament = Fixtures.create_tournament(%{bracket_size: 16, region_count: 4})
      bracket = Fixtures.create_bracket(user, tournament)

      picks = for pos <- 1..15, into: %{} do
        {to_string(pos), Ecto.UUID.generate()}
      end

      {:ok, updated} = Brackets.update_picks(bracket, picks)

      assert updated.is_complete == true
    end

    test "8-bracket marks complete at 7 picks (bracket_size - 1)" do
      user = Fixtures.create_user()
      tournament = Fixtures.create_tournament(%{bracket_size: 8, region_count: 2, region_names: ["East", "West"]})
      bracket = Fixtures.create_bracket(user, tournament)

      picks = for pos <- 1..7, into: %{} do
        {to_string(pos), Ecto.UUID.generate()}
      end

      {:ok, updated} = Brackets.update_picks(bracket, picks)

      assert updated.is_complete == true
    end
  end
end
