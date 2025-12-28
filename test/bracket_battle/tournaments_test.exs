defmodule BracketBattle.TournamentsTest do
  use BracketBattle.DataCase, async: true

  alias BracketBattle.Tournaments
  alias BracketBattle.Tournaments.Tournament
  alias BracketBattle.Fixtures

  describe "create_tournament/2" do
    test "creates tournament with valid attributes" do
      admin = Fixtures.create_user(%{is_admin: true})

      assert {:ok, tournament} =
               Tournaments.create_tournament(
                 %{"name" => "Test Tournament", "bracket_size" => 64},
                 admin
               )

      assert tournament.name == "Test Tournament"
      assert tournament.bracket_size == 64
      assert tournament.status == "draft"
      assert tournament.created_by_id == admin.id
    end

    test "fails without name" do
      admin = Fixtures.create_user(%{is_admin: true})

      assert {:error, changeset} =
               Tournaments.create_tournament(%{"bracket_size" => 64}, admin)

      assert "can't be blank" in errors_on(changeset).name
    end
  end

  describe "open_registration/1" do
    test "transitions from draft to registration when contestants complete" do
      tournament = Fixtures.create_tournament(%{status: "draft", bracket_size: 8, region_count: 2, region_names: ["East", "West"]})

      # Add all 8 contestants (4 per region)
      for region <- ["East", "West"], seed <- 1..4 do
        Fixtures.create_contestant(tournament, %{seed: seed, region: region})
      end

      assert {:ok, updated} = Tournaments.open_registration(tournament)
      assert updated.status == "registration"
    end

    test "fails when contestants incomplete" do
      tournament = Fixtures.create_tournament(%{status: "draft", bracket_size: 64})

      # Only add 10 contestants (need 64)
      for i <- 1..10 do
        region = Enum.at(["East", "West", "South", "Midwest"], rem(i - 1, 4))
        Fixtures.create_contestant(tournament, %{seed: rem(i - 1, 16) + 1, region: region})
      end

      assert {:error, :incomplete_contestants} = Tournaments.open_registration(tournament)
    end
  end

  describe "start_tournament/1" do
    setup do
      tournament = Fixtures.create_tournament(%{
        status: "registration",
        bracket_size: 8,
        region_count: 2,
        region_names: ["East", "West"]
      })

      # Add all 8 contestants
      contestants =
        for region <- ["East", "West"], seed <- 1..4 do
          Fixtures.create_contestant(tournament, %{seed: seed, region: region})
        end

      %{tournament: tournament, contestants: contestants}
    end

    test "generates all matchups", %{tournament: tournament} do
      {:ok, started} = Tournaments.start_tournament(tournament)

      matchups = Tournaments.get_all_matchups(started.id)

      # 8-bracket = 7 matchups total (4 + 2 + 1)
      assert length(matchups) == 7
    end

    test "activates round 1 voting", %{tournament: tournament} do
      {:ok, started} = Tournaments.start_tournament(tournament)

      round_1_matchups = Tournaments.get_matchups_by_round(started.id, 1)

      # All round 1 matchups should be voting
      assert Enum.all?(round_1_matchups, &(&1.status == "voting"))

      # Round 2+ should be pending
      round_2_matchups = Tournaments.get_matchups_by_round(started.id, 2)
      assert Enum.all?(round_2_matchups, &(&1.status == "pending"))
    end

    test "sets tournament status to active", %{tournament: tournament} do
      {:ok, started} = Tournaments.start_tournament(tournament)

      assert started.status == "active"
      assert started.current_round == 1
      assert started.started_at != nil
    end

    test "round 1 matchups have correct contestants", %{tournament: tournament} do
      {:ok, started} = Tournaments.start_tournament(tournament)

      round_1_matchups = Tournaments.get_matchups_by_round(started.id, 1)

      # Should have 4 matchups in round 1 (2 per region)
      assert length(round_1_matchups) == 4

      # Each matchup should have 2 contestants
      Enum.each(round_1_matchups, fn matchup ->
        assert matchup.contestant_1_id != nil
        assert matchup.contestant_2_id != nil
      end)
    end
  end

  describe "advance_round/1" do
    setup do
      tournament = Fixtures.create_tournament(%{
        status: "active",
        current_round: 1,
        bracket_size: 8,
        region_count: 2,
        region_names: ["East", "West"]
      })

      # Add all contestants
      contestants =
        for region <- ["East", "West"], seed <- 1..4 do
          Fixtures.create_contestant(tournament, %{seed: seed, region: region})
        end

      # Generate matchups manually for testing
      Tournaments.generate_matchups_for_tournament(tournament)

      %{tournament: tournament, contestants: contestants}
    end

    test "fails when matchups still pending", %{tournament: tournament} do
      # Don't decide any matchups - should fail
      assert {:error, :matchups_pending} = Tournaments.advance_round(tournament)
    end

    test "advances when all matchups decided", %{tournament: tournament} do
      # Decide all round 1 matchups
      round_1 = Tournaments.get_matchups_by_round(tournament.id, 1)

      Enum.each(round_1, fn matchup ->
        Tournaments.decide_matchup(matchup, matchup.contestant_1_id)
      end)

      {:ok, advanced} = Tournaments.advance_round(tournament)

      assert advanced.current_round == 2
    end

    test "populates next round with winners", %{tournament: tournament} do
      round_1 = Tournaments.get_matchups_by_round(tournament.id, 1)

      # Decide all round 1 matchups, keeping track of winners
      winners =
        Enum.map(round_1, fn matchup ->
          {:ok, decided} = Tournaments.decide_matchup(matchup, matchup.contestant_1_id)
          decided.winner_id
        end)

      {:ok, _advanced} = Tournaments.advance_round(tournament)

      # Check round 2 matchups have winners from round 1
      round_2 = Tournaments.get_matchups_by_round(tournament.id, 2)

      round_2_contestants =
        Enum.flat_map(round_2, fn m -> [m.contestant_1_id, m.contestant_2_id] end)
        |> Enum.filter(& &1)

      # All round 2 contestants should be from round 1 winners
      assert Enum.all?(round_2_contestants, &(&1 in winners))
    end

    test "activates voting for next round", %{tournament: tournament} do
      round_1 = Tournaments.get_matchups_by_round(tournament.id, 1)

      Enum.each(round_1, fn matchup ->
        Tournaments.decide_matchup(matchup, matchup.contestant_1_id)
      end)

      {:ok, _advanced} = Tournaments.advance_round(tournament)

      round_2 = Tournaments.get_matchups_by_round(tournament.id, 2)

      assert Enum.all?(round_2, &(&1.status == "voting"))
    end
  end

  describe "complete_tournament/1" do
    test "sets status to completed" do
      tournament = Fixtures.create_tournament(%{status: "active"})

      {:ok, completed} = Tournaments.complete_tournament(tournament)

      assert completed.status == "completed"
      assert completed.completed_at != nil
    end
  end

  describe "seeding_pattern/1" do
    test "returns correct pattern for 16 contestants" do
      pattern = Tournaments.seeding_pattern(16)

      # Standard NCAA seeding
      expected = [{1, 16}, {8, 9}, {5, 12}, {4, 13}, {6, 11}, {3, 14}, {7, 10}, {2, 15}]
      assert pattern == expected
    end

    test "returns correct pattern for 8 contestants" do
      pattern = Tournaments.seeding_pattern(8)

      expected = [{1, 8}, {4, 5}, {3, 6}, {2, 7}]
      assert pattern == expected
    end

    test "returns correct pattern for 4 contestants" do
      pattern = Tournaments.seeding_pattern(4)

      expected = [{1, 4}, {2, 3}]
      assert pattern == expected
    end

    test "returns correct pattern for 2 contestants" do
      pattern = Tournaments.seeding_pattern(2)

      expected = [{1, 2}]
      assert pattern == expected
    end

    test "generated pattern for 32 creates valid pairs" do
      pattern = Tournaments.seeding_pattern(32)

      # Should have 16 pairs
      assert length(pattern) == 16

      # All seeds 1-32 should appear exactly once
      all_seeds = Enum.flat_map(pattern, fn {a, b} -> [a, b] end)
      assert Enum.sort(all_seeds) == Enum.to_list(1..32)
    end
  end

  describe "decide_matchup/2" do
    test "sets winner and status to decided" do
      tournament = Fixtures.create_tournament(%{status: "active"})
      c1 = Fixtures.create_contestant(tournament, %{seed: 1, region: "East"})
      c2 = Fixtures.create_contestant(tournament, %{seed: 2, region: "East"})

      matchup = Fixtures.create_voting_matchup(tournament, c1, c2)

      {:ok, decided} = Tournaments.decide_matchup(matchup, c1.id)

      assert decided.winner_id == c1.id
      assert decided.status == "decided"
      assert decided.decided_at != nil
    end

    test "marks admin_decided when third param is true" do
      tournament = Fixtures.create_tournament(%{status: "active"})
      c1 = Fixtures.create_contestant(tournament, %{seed: 1, region: "East"})
      c2 = Fixtures.create_contestant(tournament, %{seed: 2, region: "East"})

      matchup = Fixtures.create_voting_matchup(tournament, c1, c2)

      {:ok, decided} = Tournaments.decide_matchup(matchup, c1.id, true)

      assert decided.admin_decided == true
    end
  end

  describe "default_round_names/1" do
    test "generates correct names for 64-bracket" do
      names = Tournaments.default_round_names(64)

      assert names[1] == "Round 1"
      assert names[2] == "Round 2"
      assert names[3] == "Sweet 16"
      assert names[4] == "Elite 8"
      assert names[5] == "Final Four"
      assert names[6] == "Championship"
    end

    test "generates correct names for 32-bracket" do
      names = Tournaments.default_round_names(32)

      assert names[1] == "Round 1"
      assert names[2] == "Sweet 16"
      assert names[3] == "Elite 8"
      assert names[4] == "Final Four"
      assert names[5] == "Championship"
    end

    test "generates correct names for 8-bracket" do
      names = Tournaments.default_round_names(8)

      assert names[1] == "Elite 8"
      assert names[2] == "Final Four"
      assert names[3] == "Championship"
    end
  end

  describe "Tournament computed properties" do
    test "total_rounds calculates correctly" do
      assert Tournament.total_rounds(%Tournament{bracket_size: 8}) == 3
      assert Tournament.total_rounds(%Tournament{bracket_size: 16}) == 4
      assert Tournament.total_rounds(%Tournament{bracket_size: 32}) == 5
      assert Tournament.total_rounds(%Tournament{bracket_size: 64}) == 6
      assert Tournament.total_rounds(%Tournament{bracket_size: 128}) == 7
    end

    test "contestants_per_region calculates correctly" do
      assert Tournament.contestants_per_region(%Tournament{bracket_size: 64, region_count: 4}) == 16
      assert Tournament.contestants_per_region(%Tournament{bracket_size: 32, region_count: 4}) == 8
      assert Tournament.contestants_per_region(%Tournament{bracket_size: 16, region_count: 4}) == 4
      assert Tournament.contestants_per_region(%Tournament{bracket_size: 8, region_count: 2}) == 4
    end

    test "total_matchups calculates correctly" do
      assert Tournament.total_matchups(%Tournament{bracket_size: 8}) == 7
      assert Tournament.total_matchups(%Tournament{bracket_size: 16}) == 15
      assert Tournament.total_matchups(%Tournament{bracket_size: 32}) == 31
      assert Tournament.total_matchups(%Tournament{bracket_size: 64}) == 63
      assert Tournament.total_matchups(%Tournament{bracket_size: 128}) == 127
    end
  end
end
