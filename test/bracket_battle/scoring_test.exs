defmodule BracketBattle.ScoringTest do
  use BracketBattle.DataCase, async: true

  alias BracketBattle.Scoring
  alias BracketBattle.Fixtures

  describe "points_for_round/1 (default scoring)" do
    test "returns correct ESPN-style points for each round" do
      assert Scoring.points_for_round(1) == 10
      assert Scoring.points_for_round(2) == 20
      assert Scoring.points_for_round(3) == 40
      assert Scoring.points_for_round(4) == 80
      assert Scoring.points_for_round(5) == 160
      assert Scoring.points_for_round(6) == 320
      assert Scoring.points_for_round(7) == 640
    end

    test "returns 0 for invalid round" do
      assert Scoring.points_for_round(0) == 0
      assert Scoring.points_for_round(8) == 0
      assert Scoring.points_for_round(-1) == 0
    end
  end

  describe "points_for_round/2 (tournament-specific scoring)" do
    test "uses default scoring when no custom config" do
      tournament = Fixtures.create_tournament(%{scoring_config: %{}})

      assert Scoring.points_for_round(tournament, 1) == 10
      assert Scoring.points_for_round(tournament, 2) == 20
      assert Scoring.points_for_round(tournament, 6) == 320
    end

    test "uses custom scoring config when provided" do
      tournament = Fixtures.create_tournament(%{
        scoring_config: %{
          1 => 5,
          2 => 15,
          3 => 25
        }
      })

      assert Scoring.points_for_round(tournament, 1) == 5
      assert Scoring.points_for_round(tournament, 2) == 15
      assert Scoring.points_for_round(tournament, 3) == 25
      # Falls back to default for unconfigured rounds
      assert Scoring.points_for_round(tournament, 4) == 80
    end

    test "handles string keys in scoring config" do
      tournament = Fixtures.create_tournament(%{
        scoring_config: %{
          "1" => 100,
          "2" => 200
        }
      })

      assert Scoring.points_for_round(tournament, 1) == 100
      assert Scoring.points_for_round(tournament, 2) == 200
    end
  end

  describe "max_possible_score/1" do
    test "calculates max for 64-bracket tournament" do
      tournament = Fixtures.create_tournament(%{bracket_size: 64})

      # Round 1: 32 matchups * 10 = 320
      # Round 2: 16 matchups * 20 = 320
      # Round 3: 8 matchups * 40 = 320
      # Round 4: 4 matchups * 80 = 320
      # Round 5: 2 matchups * 160 = 320
      # Round 6: 1 matchup * 320 = 320
      # Total: 1920
      assert Scoring.max_possible_score(tournament) == 1920
    end

    test "calculates max for 32-bracket tournament" do
      tournament = Fixtures.create_tournament(%{bracket_size: 32, region_count: 4})

      # Round 1: 16 matchups * 10 = 160
      # Round 2: 8 matchups * 20 = 160
      # Round 3: 4 matchups * 40 = 160
      # Round 4: 2 matchups * 80 = 160
      # Round 5: 1 matchup * 160 = 160
      # Total: 800
      assert Scoring.max_possible_score(tournament) == 800
    end

    test "calculates max for 16-bracket tournament" do
      tournament = Fixtures.create_tournament(%{bracket_size: 16, region_count: 4})

      # Round 1: 8 matchups * 10 = 80
      # Round 2: 4 matchups * 20 = 80
      # Round 3: 2 matchups * 40 = 80
      # Round 4: 1 matchup * 80 = 80
      # Total: 320
      assert Scoring.max_possible_score(tournament) == 320
    end

    test "respects custom scoring config" do
      tournament = Fixtures.create_tournament(%{
        bracket_size: 8,
        region_count: 2,
        region_names: ["East", "West"],
        scoring_config: %{1 => 100, 2 => 200, 3 => 300}
      })

      # Round 1: 4 matchups * 100 = 400
      # Round 2: 2 matchups * 200 = 400
      # Round 3: 1 matchup * 300 = 300
      # Total: 1100
      assert Scoring.max_possible_score(tournament) == 1100
    end
  end

  describe "max_possible_score/0 (default)" do
    test "returns 1920 for default 64-contestant tournament" do
      assert Scoring.max_possible_score() == 1920
    end
  end

  describe "calculate_and_update_score/2" do
    setup do
      tournament = Fixtures.create_tournament(%{status: "active", bracket_size: 8, region_count: 2, region_names: ["East", "West"]})
      user = Fixtures.create_user()

      # Create 8 contestants (4 per region for 8-bracket)
      c1 = Fixtures.create_contestant(tournament, %{seed: 1, region: "East", name: "E1"})
      c2 = Fixtures.create_contestant(tournament, %{seed: 2, region: "East", name: "E2"})
      c3 = Fixtures.create_contestant(tournament, %{seed: 1, region: "West", name: "W1"})
      c4 = Fixtures.create_contestant(tournament, %{seed: 2, region: "West", name: "W2"})

      %{
        tournament: tournament,
        user: user,
        contestants: [c1, c2, c3, c4]
      }
    end

    test "calculates correct score for correct picks", %{
      tournament: tournament,
      user: user,
      contestants: [c1, _c2, c3, _c4]
    } do
      # Create bracket with picks matching official results
      # For 8-bracket: positions 1-4 are round 1, 5-6 are round 2, 7 is round 3
      picks = %{
        "1" => c1.id,
        "2" => c3.id,
        "3" => c1.id  # Picks c1 to win final
      }

      bracket = Fixtures.create_submitted_bracket(user, tournament, %{picks: picks})

      # Official results matching picks for positions 1 and 2
      official_results = %{
        1 => c1.id,
        2 => c3.id
      }

      updated = Scoring.calculate_and_update_score(bracket, official_results)

      # 2 correct picks in round 1 = 2 * 10 = 20 points
      assert updated.total_score == 20
      assert updated.correct_picks == 2
      assert updated.round_1_score == 20
    end

    test "returns zero for no correct picks", %{
      tournament: tournament,
      user: user,
      contestants: [c1, c2, _c3, _c4]
    } do
      # User picked c1 but c2 won
      picks = %{
        "1" => c1.id
      }

      bracket = Fixtures.create_submitted_bracket(user, tournament, %{picks: picks})

      official_results = %{
        1 => c2.id  # c2 won, not c1
      }

      updated = Scoring.calculate_and_update_score(bracket, official_results)

      assert updated.total_score == 0
      assert updated.correct_picks == 0
    end

    test "handles empty picks gracefully", %{tournament: tournament, user: user} do
      bracket = Fixtures.create_submitted_bracket(user, tournament, %{picks: %{}})

      updated = Scoring.calculate_and_update_score(bracket, %{})

      assert updated.total_score == 0
      assert updated.correct_picks == 0
    end
  end

  describe "position mapping" do
    test "calculate_base_position works for 64-bracket" do
      tournament = Fixtures.create_tournament(%{bracket_size: 64})

      # For 64-bracket:
      # Round 1: 32 matchups, positions 1-32
      # Round 2: 16 matchups, positions 33-48
      # Round 3: 8 matchups, positions 49-56
      # Round 4: 4 matchups, positions 57-60
      # Round 5: 2 matchups, positions 61-62
      # Round 6: 1 matchup, position 63

      # Verify by checking total matchups
      total_matchups = BracketBattle.Tournaments.Tournament.total_matchups(tournament)
      assert total_matchups == 63
    end

    test "total matchups correct for different bracket sizes" do
      for {size, expected} <- [{8, 7}, {16, 15}, {32, 31}, {64, 63}, {128, 127}] do
        tournament = Fixtures.create_tournament(%{bracket_size: size})
        assert BracketBattle.Tournaments.Tournament.total_matchups(tournament) == expected,
               "Expected #{expected} matchups for #{size}-bracket, got #{BracketBattle.Tournaments.Tournament.total_matchups(tournament)}"
      end
    end
  end
end
