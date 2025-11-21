defmodule Mimimi.AnalyticsTest do
  use Mimimi.DataCase

  alias Mimimi.Analytics
  alias Mimimi.Analytics.KeywordEffectiveness
  alias Mimimi.WortSchuleRepo

  # These tests require the external WortSchule database with the keyword_effectiveness table
  @moduletag :external_db

  describe "record_pick_effectiveness/6" do
    test "creates one record per keyword shown" do
      round_id = Ecto.UUID.generate()
      pick_id = Ecto.UUID.generate()
      word_id = 123

      now = DateTime.utc_now()

      keywords_with_timestamps = [
        {101, 1, DateTime.add(now, -30, :second)},
        {102, 2, DateTime.add(now, -20, :second)},
        {103, 3, DateTime.add(now, -10, :second)}
      ]

      picked_at = now
      is_correct = true

      {count, _} =
        Analytics.record_pick_effectiveness(
          round_id,
          pick_id,
          word_id,
          keywords_with_timestamps,
          picked_at,
          is_correct
        )

      assert count == 3

      # Verify records were created correctly
      records =
        WortSchuleRepo.all(
          from ke in KeywordEffectiveness,
            where: ke.pick_id == ^pick_id,
            order_by: ke.keyword_position
        )

      assert length(records) == 3

      [first, second, third] = records

      assert first.keyword_id == 101
      assert first.keyword_position == 1
      assert first.led_to_correct == true
      assert first.word_id == word_id

      assert second.keyword_id == 102
      assert second.keyword_position == 2

      assert third.keyword_id == 103
      assert third.keyword_position == 3
    end

    test "records incorrect picks" do
      round_id = Ecto.UUID.generate()
      pick_id = Ecto.UUID.generate()
      word_id = 456

      now = DateTime.utc_now()

      keywords_with_timestamps = [
        {201, 1, DateTime.add(now, -10, :second)}
      ]

      {count, _} =
        Analytics.record_pick_effectiveness(
          round_id,
          pick_id,
          word_id,
          keywords_with_timestamps,
          now,
          false
        )

      assert count == 1

      [record] =
        WortSchuleRepo.all(
          from ke in KeywordEffectiveness,
            where: ke.pick_id == ^pick_id
        )

      assert record.led_to_correct == false
    end
  end

  describe "get_keyword_stats_for_word/1" do
    test "returns stats grouped by keyword" do
      word_id = 999
      round_id = Ecto.UUID.generate()
      now = DateTime.utc_now()

      # Insert test data - keyword 301 leads to correct, 302 does not
      WortSchuleRepo.insert_all(KeywordEffectiveness, [
        %{
          id: Ecto.UUID.generate(),
          word_id: word_id,
          keyword_id: 301,
          pick_id: Ecto.UUID.generate(),
          round_id: round_id,
          keyword_position: 1,
          revealed_at: DateTime.add(now, -30, :second),
          picked_at: now,
          led_to_correct: true,
          inserted_at: now
        },
        %{
          id: Ecto.UUID.generate(),
          word_id: word_id,
          keyword_id: 301,
          pick_id: Ecto.UUID.generate(),
          round_id: round_id,
          keyword_position: 1,
          revealed_at: DateTime.add(now, -20, :second),
          picked_at: now,
          led_to_correct: true,
          inserted_at: now
        },
        %{
          id: Ecto.UUID.generate(),
          word_id: word_id,
          keyword_id: 302,
          pick_id: Ecto.UUID.generate(),
          round_id: round_id,
          keyword_position: 2,
          revealed_at: DateTime.add(now, -10, :second),
          picked_at: now,
          led_to_correct: false,
          inserted_at: now
        }
      ])

      stats = Analytics.get_keyword_stats_for_word(word_id)

      assert length(stats) == 2

      keyword_301_stats = Enum.find(stats, &(&1.keyword_id == 301))
      keyword_302_stats = Enum.find(stats, &(&1.keyword_id == 302))

      assert keyword_301_stats.total_shown == 2
      assert keyword_301_stats.times_correct == 2
      assert keyword_301_stats.success_rate == 1.0

      assert keyword_302_stats.total_shown == 1
      assert keyword_302_stats.times_correct == 0
      assert keyword_302_stats.success_rate == 0.0
    end
  end
end
