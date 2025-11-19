defmodule Mimimi.Games do
  @moduledoc """
  The Games context.
  """

  import Ecto.Query, warn: false
  alias Mimimi.Repo
  alias Mimimi.Games.{Game, GameInvite, Player, Round, Pick, Word, Keyword}

  # Constants
  @lobby_timeout_seconds 15 * 60

  # Compile-time environment check
  # IMPORTANT: Mix is not available in production releases, so we check at compile time
  @test_env Mix.env() == :test

  # Game functions

  @doc """
  Creates a game with a unique invitation_id, host_token, and short invitation code.
  """
  def create_game(host_user_id, attrs \\ %{}) do
    invitation_id = Ecto.UUID.generate()
    host_token = generate_host_token()

    attrs =
      attrs
      |> Map.put(:host_user_id, host_user_id)
      |> Map.put(:invitation_id, invitation_id)
      |> Map.put(:host_token, host_token)

    Repo.transaction(fn ->
      game =
        %Game{}
        |> Game.changeset(attrs)
        |> Repo.insert!()

      # Create game invite with short code
      case create_game_invite(game.id) do
        {:ok, _invite} -> game
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> tap(fn
      {:ok, _game} -> broadcast_game_count_changed()
      _ -> :ok
    end)
  end

  # Generates a cryptographically secure host token
  defp generate_host_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  @doc """
  Creates a new game with the same settings as the original game and copies all players.
  This is used to start a new round with the same participants.
  """
  def create_new_game_with_players(%Game{} = original_game, online_user_ids \\ nil) do
    players_with_avatars =
      from(p in Player,
        where: p.game_id == ^original_game.id,
        select: %{user_id: p.user_id, avatar: p.avatar}
      )
      |> Repo.all()

    players_to_add =
      if online_user_ids do
        Enum.filter(players_with_avatars, fn p ->
          to_string(p.user_id) in online_user_ids
        end)
      else
        players_with_avatars
      end

    game_attrs = %{
      rounds_count: original_game.rounds_count,
      grid_size: original_game.grid_size,
      clues_interval: original_game.clues_interval,
      word_types: original_game.word_types
    }

    case create_game(original_game.host_user_id, game_attrs) do
      {:ok, new_game} -> add_players_to_new_game(new_game, players_to_add, original_game)
      {:error, reason} -> {:error, reason}
    end
  end

  # Helper function to add players to a new game
  defp add_players_to_new_game(new_game, players_to_add, original_game) do
    player_results =
      Enum.map(players_to_add, fn player_data ->
        create_player(player_data.user_id, new_game.id, %{avatar: player_data.avatar})
      end)

    case Enum.all?(player_results, fn result -> match?({:ok, _}, result) end) do
      true ->
        broadcast_to_game(original_game.id, {:new_game_started, new_game.id})
        {:ok, new_game}

      false ->
        {:error, :failed_to_create_players}
    end
  end

  @doc """
  Validates if there are enough words available for the given game configuration.
  Returns {:ok, %{target_words: count, total_words: count}} if valid,
  or {:error, reason} if insufficient words are available.

  ## Examples

      iex> validate_word_availability(%{word_types: ["Noun"], rounds_count: 3, grid_size: 9})
      {:ok, %{target_words: 150, total_words: 500}}

      iex> validate_word_availability(%{word_types: ["InvalidType"], rounds_count: 10, grid_size: 16})
      {:error, :insufficient_target_words}
  """
  def validate_word_availability(attrs) do
    alias Mimimi.WortSchule

    word_types = Map.get(attrs, :word_types, [])
    rounds_count = Map.get(attrs, :rounds_count, 1)
    grid_size = Map.get(attrs, :grid_size, 9)

    target_word_ids =
      WortSchule.get_word_ids_with_keywords_and_images(min_keywords: 3, types: word_types)

    all_word_ids =
      WortSchule.get_word_ids_with_keywords_and_images(min_keywords: 1, types: word_types)

    target_count = length(target_word_ids)
    total_count = length(all_word_ids)

    required_target = rounds_count
    required_total = rounds_count * (grid_size - 1)

    cond do
      target_count < required_target ->
        {:error, :insufficient_target_words}

      total_count < required_total ->
        {:error, :insufficient_distractor_words}

      true ->
        {:ok, %{target_words: target_count, total_words: total_count}}
    end
  end

  @doc """
  Generates a random 6-digit short code for game invitations.
  """
  def generate_short_code do
    # Generate a random 6-digit number (100000 to 999999)
    min = 100_000
    max = 999_999
    Enum.random(min..max) |> Integer.to_string()
  end

  @doc """
  Creates a game invite with a short code that expires after the configured time.
  Returns {:ok, game_invite} or {:error, changeset}.
  """
  def create_game_invite(game_id) do
    # Get expiration minutes from config (default to 15 minutes)
    expiration_minutes = Application.get_env(:mimimi, :invitation_expiration_minutes, 15)
    expires_at = DateTime.utc_now() |> DateTime.add(expiration_minutes * 60, :second)

    # Try up to 10 times to generate a unique code
    result =
      Enum.reduce_while(1..10, nil, fn _attempt, _acc ->
        try_insert_game_invite(game_id, expires_at)
      end)

    result || {:error, :failed_to_generate_unique_code}
  end

  defp try_insert_game_invite(game_id, expires_at) do
    short_code = generate_short_code()

    case %GameInvite{}
         |> GameInvite.changeset(%{
           short_code: short_code,
           game_id: game_id,
           expires_at: expires_at
         })
         |> Repo.insert() do
      {:ok, invite} ->
        {:halt, {:ok, invite}}

      {:error, changeset} ->
        # If it's a unique constraint error, try again
        if changeset.errors[:short_code] do
          {:cont, nil}
        else
          {:halt, {:error, changeset}}
        end
    end
  end

  @doc """
  Gets the short code for a game.
  Returns the short code string or nil if not found.
  """
  def get_short_code_for_game(game_id) do
    now = DateTime.utc_now()

    from(gi in GameInvite,
      where: gi.game_id == ^game_id and gi.expires_at > ^now,
      select: gi.short_code,
      order_by: [desc: gi.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Gets a game by short invitation code.
  Returns nil if not found or expired.
  """
  def get_game_by_short_code(short_code) do
    now = DateTime.utc_now()

    from(gi in GameInvite,
      where: gi.short_code == ^short_code and gi.expires_at > ^now,
      join: g in assoc(gi, :game),
      select: g
    )
    |> Repo.one()
  end

  @doc """
  Validates a short code invitation and returns appropriate error if invalid.
  """
  def validate_short_code(short_code) do
    now = DateTime.utc_now()

    case from(gi in GameInvite,
           where: gi.short_code == ^short_code,
           preload: [game: :players]
         )
         |> Repo.one() do
      nil ->
        {:error, :not_found}

      %GameInvite{expires_at: expires_at, game: game} ->
        cond do
          DateTime.compare(expires_at, now) in [:lt, :eq] ->
            {:error, :expired}

          game.state == "game_running" ->
            {:error, :already_started}

          game.state == "game_over" ->
            {:error, :game_over}

          game.state == "lobby_timeout" ->
            {:error, :lobby_timeout}

          game.state == "host_disconnected" ->
            {:error, :host_disconnected}

          true ->
            {:ok, game}
        end
    end
  end

  @doc """
  Gets a game by invitation_id.
  """
  def get_game_by_invitation(invitation_id) do
    Repo.get_by(Game, invitation_id: invitation_id)
  end

  @doc """
  Gets a game with preloaded players.
  """
  def get_game_with_players(game_id) do
    Repo.get(Game, game_id)
    |> Repo.preload(players: from(p in Player, order_by: [asc: p.inserted_at]))
  end

  @doc """
  Validates an invitation and returns appropriate error if invalid.
  """
  def validate_invitation(invitation_id) do
    case get_game_by_invitation(invitation_id) do
      nil ->
        {:error, :not_found}

      %Game{state: "game_running"} ->
        {:error, :already_started}

      %Game{state: "game_over"} ->
        {:error, :game_over}

      %Game{state: "lobby_timeout"} ->
        {:error, :lobby_timeout}

      game ->
        # Check if lobby has timed out (15 minutes)
        if lobby_timeout?(game) do
          {:error, :lobby_timeout}
        else
          {:ok, game}
        end
    end
  end

  @doc """
  Checks if the lobby has exceeded 15 minutes.
  """
  def lobby_timeout?(%Game{inserted_at: inserted_at, state: "waiting_for_players"}) do
    timeout_seconds = @lobby_timeout_seconds
    # Convert NaiveDateTime to DateTime for comparison
    inserted_at_utc = DateTime.from_naive!(inserted_at, "Etc/UTC")
    DateTime.diff(DateTime.utc_now(), inserted_at_utc, :second) >= timeout_seconds
  end

  def lobby_timeout?(_game), do: false

  @doc """
  Calculates seconds remaining until lobby timeout.
  """
  def calculate_lobby_time_remaining(%Game{inserted_at: inserted_at}) do
    timeout_seconds = @lobby_timeout_seconds
    # Convert NaiveDateTime to DateTime for comparison
    inserted_at_utc = DateTime.from_naive!(inserted_at, "Etc/UTC")
    elapsed = DateTime.diff(DateTime.utc_now(), inserted_at_utc, :second)
    max(0, timeout_seconds - elapsed)
  end

  @doc """
  Starts a game and generates rounds.

  By default, rounds are generated asynchronously in production for better performance.
  In test environment, rounds are generated synchronously to avoid database ownership issues.

  The game state is immediately set to "game_running", and rounds are generated either
  synchronously (tests) or in the background (production).
  Once rounds are ready, the first round is activated and :round_started is broadcast.
  """
  def start_game(%Game{} = game) do
    # Update game state immediately
    result =
      game
      |> Game.changeset(%{state: "game_running", started_at: DateTime.utc_now()})
      |> Repo.update()

    case result do
      {:ok, game} ->
        broadcast_game_count_changed()
        broadcast_to_game(game.id, :game_started)
        generate_game_rounds(game)
        {:ok, game}

      error ->
        error
    end
  end

  # Helper to generate rounds - async in production, sync in test
  # Uses @test_env compile-time check because Mix is not available in production releases
  defp generate_game_rounds(game) do
    if @test_env do
      generate_rounds_sync(game)
    else
      generate_rounds_async_task(game)
    end
  end

  # Async round generation for production
  defp generate_rounds_async_task(game) do
    require Logger
    caller_pid = self()

    # Start a monitored task so we can detect if it crashes
    result =
      Task.Supervisor.start_child(
        Mimimi.TaskSupervisor,
        fn ->
          # Ensure this process has access to the database connection pools
          # This is important for async tasks in production
          setup_sandbox_access(caller_pid)

          # Log the process details for debugging
          Logger.info(
            "Async round generation task started for game #{game.id}, pid: #{inspect(self())}"
          )

          # Execute round generation with comprehensive error handling
          try do
            result = generate_rounds_async(game)

            Logger.info(
              "Async round generation completed for game #{game.id}: #{inspect(result)}"
            )

            result
          catch
            kind, reason ->
              Logger.error(
                "Async round generation crashed for game #{game.id}, kind: #{kind}, reason: #{inspect(reason)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
              )

              broadcast_to_game(game.id, :round_generation_failed)
              reraise reason, __STACKTRACE__
          end
        end,
        restart: :temporary
      )

    case result do
      {:ok, pid} ->
        Logger.info(
          "Successfully started async round generation task for game #{game.id}, task pid: #{inspect(pid)}"
        )

      {:error, reason} ->
        Logger.error(
          "Failed to start async round generation task for game #{game.id}: #{inspect(reason)}"
        )

        broadcast_to_game(game.id, :round_generation_failed)
    end

    result
  end

  # Setup database sandbox access for async task
  defp setup_sandbox_access(caller_pid) do
    try do
      if function_exported?(Ecto.Adapters.SQL.Sandbox, :allow, 3) do
        Ecto.Adapters.SQL.Sandbox.allow(Mimimi.Repo, caller_pid, self())
        Ecto.Adapters.SQL.Sandbox.allow(Mimimi.WortSchuleRepo, caller_pid, self())
      end
    rescue
      _ -> :ok
    end
  end

  # Synchronous round generation for tests
  defp generate_rounds_sync(game) do
    try do
      generate_rounds(game)

      case advance_to_next_round(game.id) do
        {:ok, _round} ->
          broadcast_to_game(game.id, :round_started)
          :ok

        {:error, reason} ->
          require Logger
          Logger.error("Failed to advance to first round for game #{game.id}: #{inspect(reason)}")
          :error
      end
    rescue
      error ->
        require Logger

        Logger.error(
          "Failed to generate rounds for game #{game.id}: #{inspect(error)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
        )

        update_game_state(game, "game_over")
        broadcast_to_game(game.id, :round_generation_failed)
        :error
    end
  end

  # Async round generation with error handling
  # Optimized: generate first round immediately, rest in background
  defp generate_rounds_async(game) do
    require Logger
    Logger.info("Starting async round generation for game #{game.id}")

    try do
      # Generate only the first round immediately for faster game start
      generate_single_round_fast(game, 1)
      Logger.info("First round generated for game #{game.id}")

      # Activate the first round
      case advance_to_next_round(game.id) do
        {:ok, round} ->
          Logger.info("Advanced to first round #{round.id} for game #{game.id}")
          # Broadcast that the first round is ready - game can start NOW
          Logger.info("Broadcasting :round_started to game #{game.id}")
          broadcast_to_game(game.id, :round_started)
          Logger.info("Broadcast :round_started completed for game #{game.id}")

          # Generate remaining rounds in the background while players are playing
          if game.rounds_count > 1 do
            Enum.each(2..game.rounds_count, fn position ->
              generate_single_round_fast(game, position)
            end)

            Logger.info(
              "Generated #{game.rounds_count - 1} additional rounds for game #{game.id}"
            )
          end

          :ok

        {:error, reason} ->
          Logger.error("Failed to advance to first round for game #{game.id}: #{inspect(reason)}")
          broadcast_to_game(game.id, :round_generation_failed)
          :error
      end
    rescue
      error ->
        Logger.error(
          "Failed to generate rounds for game #{game.id}: #{inspect(error)}\n#{Exception.format_stacktrace(__STACKTRACE__)}"
        )

        # Update game state to indicate failure
        try do
          update_game_state(game, "game_over")
        rescue
          _ -> :ok
        end

        broadcast_to_game(game.id, :round_generation_failed)
        :error
    end
  end

  # Fast single round generation - reuses the same word pool lookup
  defp generate_single_round_fast(game, position) do
    require Logger
    alias Mimimi.WortSchule

    Logger.info("Generating round #{position} for game #{game.id}")

    # Get word pools (this is cached by the database for subsequent calls)
    target_word_ids =
      WortSchule.get_word_ids_with_keywords_and_images(min_keywords: 3, types: game.word_types)

    Logger.info(
      "Found #{length(target_word_ids)} target words for game #{game.id} round #{position}"
    )

    all_word_ids =
      WortSchule.get_word_ids_with_keywords_and_images(min_keywords: 1, types: game.word_types)

    Logger.info("Found #{length(all_word_ids)} total words for game #{game.id} round #{position}")

    # Get already used target words from existing rounds to ensure uniqueness
    used_target_word_ids =
      from(r in Round,
        where: r.game_id == ^game.id,
        select: r.word_id
      )
      |> Repo.all()

    # Remove already used target words from the pool
    available_target_word_ids = target_word_ids -- used_target_word_ids

    # Validate we have enough words
    if Enum.empty?(available_target_word_ids) do
      raise "No available target words for game #{game.id} round #{position}. Total target words: #{length(target_word_ids)}, used: #{length(used_target_word_ids)}"
    end

    if Enum.empty?(all_word_ids) do
      raise "No words available in word pool for game #{game.id} round #{position}"
    end

    Logger.info(
      "Available target words: #{length(available_target_word_ids)} for game #{game.id} round #{position}"
    )

    # Generate single round by creating a temporary game with rounds_count = position
    # This ensures generate_rounds_data stops after generating just this one round
    temp_game = %{game | rounds_count: position}

    rounds_data =
      generate_rounds_data(temp_game, available_target_word_ids, all_word_ids, [], position)

    # Extract the round data for this position (it will be the last in the list)
    round_data = List.last(rounds_data)

    # Insert with timestamps
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    round_with_timestamps =
      round_data
      |> Map.put(:inserted_at, now)
      |> Map.put(:updated_at, now)

    Repo.insert_all(Round, [round_with_timestamps])
  end

  @doc """
  Times out a lobby game.
  """
  def timeout_lobby(%Game{} = game) do
    game
    |> Game.changeset(%{state: "lobby_timeout"})
    |> Repo.update()
    |> tap(fn
      {:ok, _game} -> broadcast_game_count_changed()
      _ -> :ok
    end)
  end

  @doc """
  Updates game state.
  """
  def update_game_state(%Game{} = game, new_state) do
    game
    |> Game.changeset(%{state: new_state})
    |> Repo.update()
    |> tap(fn
      {:ok, _game} -> broadcast_game_count_changed()
      _ -> :ok
    end)
  end

  @doc """
  Counts active games (waiting_for_players or game_running).
  """
  def count_active_games do
    from(g in Game,
      where: g.state in ["waiting_for_players", "game_running"]
    )
    |> Repo.aggregate(:count)
  end

  @doc """
  Counts games waiting for players (only waiting_for_players state).
  Excludes games that have timed out (older than 15 minutes).
  """
  def count_waiting_games do
    timeout_seconds = @lobby_timeout_seconds
    timeout_threshold = DateTime.add(DateTime.utc_now(), -timeout_seconds, :second)

    from(g in Game,
      where: g.state == "waiting_for_players" and g.inserted_at > ^timeout_threshold
    )
    |> Repo.aggregate(:count)
  end

  @doc """
  Restarts a game with the same settings.
  """
  def restart_game(%Game{} = old_game) do
    create_game(old_game.host_user_id, %{
      rounds_count: old_game.rounds_count,
      clues_interval: old_game.clues_interval,
      grid_size: old_game.grid_size,
      word_types: old_game.word_types
    })
  end

  # Player functions

  @doc """
  Creates a player.
  """
  def create_player(user_id, game_id, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.put(:user_id, user_id)
      |> Map.put(:game_id, game_id)

    %Player{}
    |> Player.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Lists available avatars for a game.
  """
  def list_available_avatars(game_id) do
    all_avatars = [
      "🐻",
      "🐘",
      "🦉",
      "🐸",
      "🦊",
      "🐰",
      "🦛",
      "🐱",
      "🦁",
      "🐼",
      "🐯",
      "🦒",
      "🦓",
      "🐄",
      "🐷",
      "🐵",
      "🐶",
      "🐺",
      "🦝",
      "🐨",
      "🐹",
      "🐭",
      "🐮",
      "🦌",
      "🐴",
      "🐗",
      "🦘",
      "🦙",
      "🐪",
      "🐧",
      "🦆",
      "🦅",
      "🦜",
      "🐢",
      "🦎",
      "🦈"
    ]

    taken_avatars =
      from(p in Player,
        where: p.game_id == ^game_id and not is_nil(p.avatar),
        select: p.avatar
      )
      |> Repo.all()
      |> MapSet.new()

    Enum.map(all_avatars, fn avatar ->
      {avatar, not MapSet.member?(taken_avatars, avatar)}
    end)
  end

  @doc """
  Adds points to a player.
  """
  def add_points(%Player{} = player, points) do
    player
    |> Player.changeset(%{points: player.points + points})
    |> Repo.update()
  end

  @doc """
  Gets the leaderboard for a game.
  """
  def get_leaderboard(game_id) do
    from(p in Player,
      where: p.game_id == ^game_id,
      order_by: [desc: p.points, asc: p.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Lists all players for a game.
  """
  def list_players_for_game(game_id) do
    from(p in Player,
      where: p.game_id == ^game_id,
      order_by: [asc: p.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets a player by game and user.
  """
  def get_player_by_game_and_user(game_id, user_id) do
    Repo.get_by(Player, game_id: game_id, user_id: user_id)
  end

  @doc """
  Gets the online status for all players in a game using Phoenix Presence.
  Returns a MapSet of user IDs that are currently online.
  """
  def get_players_online_status(game_id) do
    presence = Mimimi.Presence.list("game:#{game_id}:players")

    presence
    |> Map.keys()
    |> Enum.map(fn "player_" <> user_id -> user_id end)
    |> MapSet.new()
  end

  @doc """
  Removes a player when they disconnect during the waiting phase.
  This frees up their avatar for other players to use.
  """
  def remove_player_on_disconnect(game_id, user_id) do
    case get_player_by_game_and_user(game_id, user_id) do
      nil ->
        :ok

      player ->
        # Delete the player
        Repo.delete(player)

        # Broadcast that a player left
        broadcast_to_game(game_id, :player_left)

        :ok
    end
  end

  # Round functions

  @doc """
  Generates all rounds for a game using WortSchule data.
  Fetches words with images and keywords from the external WortSchule database.
  Filters words by the configured word types.
  """
  def generate_rounds(%Game{} = game) do
    alias Mimimi.WortSchule

    # Get words with at least 3 keywords for target words, filtered by word types
    target_word_ids =
      WortSchule.get_word_ids_with_keywords_and_images(min_keywords: 3, types: game.word_types)

    if length(target_word_ids) < game.rounds_count do
      raise "Not enough words with 3+ keywords to generate #{game.rounds_count} rounds for word types: #{Enum.join(game.word_types, ", ")}"
    end

    # Get all words with at least 1 keyword for distractors, filtered by word types
    all_word_ids =
      WortSchule.get_word_ids_with_keywords_and_images(min_keywords: 1, types: game.word_types)

    if length(all_word_ids) < game.rounds_count * (game.grid_size - 1) do
      raise "Not enough words available to generate rounds with grid size #{game.grid_size} for word types: #{Enum.join(game.word_types, ", ")}"
    end

    # Generate all rounds data first, then batch insert
    rounds_data = generate_rounds_data(game, target_word_ids, all_word_ids, [])

    # Batch insert all rounds at once with timestamps
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rounds_with_timestamps =
      Enum.map(rounds_data, fn round_data ->
        round_data
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    Repo.insert_all(Round, rounds_with_timestamps)
  end

  defp generate_rounds_data(game, target_word_ids, all_word_ids, acc, position \\ 1)

  defp generate_rounds_data(game, _target_ids, _all_ids, acc, position)
       when position > game.rounds_count do
    Enum.reverse(acc)
  end

  defp generate_rounds_data(game, available_targets, all_word_ids, acc, position) do
    alias Mimimi.WortSchule

    target_word_id = Enum.random(available_targets)

    case WortSchule.get_complete_word(target_word_id) do
      {:ok, word_data} ->
        keyword_ids =
          word_data.keywords
          |> Enum.shuffle()
          |> Enum.take(5)
          |> Enum.map(& &1.id)

        distractor_ids =
          (all_word_ids -- [target_word_id])
          |> Enum.shuffle()
          |> Enum.take(game.grid_size - 1)

        possible_words_ids = Enum.shuffle([target_word_id | distractor_ids])

        round_data = %{
          game_id: game.id,
          word_id: target_word_id,
          keyword_ids: keyword_ids,
          possible_words_ids: possible_words_ids,
          position: position,
          state: "on_hold"
        }

        # Remove the used target word from available targets to ensure uniqueness
        new_targets = available_targets -- [target_word_id]

        generate_rounds_data(
          game,
          new_targets,
          all_word_ids,
          [round_data | acc],
          position + 1
        )

      {:error, :not_found} ->
        new_targets = available_targets -- [target_word_id]

        if new_targets == [] do
          raise "Failed to fetch keyword data for all available target words"
        end

        generate_rounds_data(game, new_targets, all_word_ids, acc, position)
    end
  end

  @doc """
  Gets the current round for a game.
  """
  def get_current_round(game_id) do
    from(r in Round,
      where: r.game_id == ^game_id and r.state in ["playing", "on_hold"],
      order_by: [asc: r.position],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Finishes a round.
  """
  def finish_round(%Round{} = round) do
    round
    |> Round.changeset(%{state: "finished"})
    |> Repo.update()
  end

  @doc """
  Advances to the next round.
  """
  def advance_to_next_round(game_id) do
    from(r in Round,
      where: r.game_id == ^game_id and r.state == "on_hold",
      order_by: [asc: r.position],
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :no_more_rounds}
      round -> round |> Round.changeset(%{state: "playing"}) |> Repo.update()
    end
  end

  # Pick functions

  @doc """
  Creates a pick for a player in a round.
  Returns {:ok, pick, all_picked?} where all_picked? indicates if this was the last pick.
  This check is done atomically within a transaction to prevent race conditions.
  """
  def create_pick(round_id, player_id, attrs) do
    attrs =
      attrs
      |> Map.put(:round_id, round_id)
      |> Map.put(:player_id, player_id)

    Repo.transaction(fn ->
      # Insert the pick
      pick =
        %Pick{}
        |> Pick.changeset(attrs)
        |> Repo.insert!()

      # Check if all players have now picked (atomically within this transaction)
      round = Repo.get!(Round, round_id) |> Repo.preload(:game)
      game_id = round.game.id

      player_count = from(p in Player, where: p.game_id == ^game_id) |> Repo.aggregate(:count)
      pick_count = from(p in Pick, where: p.round_id == ^round_id) |> Repo.aggregate(:count)

      all_picked = player_count == pick_count

      {pick, all_picked}
    end)
  end

  @doc """
  Checks if all players have picked for a round.
  """
  def all_players_picked?(round_id) do
    round = Repo.get!(Round, round_id) |> Repo.preload(:game)
    game_id = round.game.id

    player_count = from(p in Player, where: p.game_id == ^game_id) |> Repo.aggregate(:count)
    pick_count = from(p in Pick, where: p.round_id == ^round_id) |> Repo.aggregate(:count)

    player_count == pick_count
  end

  @doc """
  Calculates points for a pick based on percentage of keywords revealed.

  Formula: max(1, 6 - ceil(keywords_shown / total_keywords * 5))

  Examples:
  - 5-keyword word: 5→4→3→2→1 points (20%, 40%, 60%, 80%, 100%)
  - 4-keyword word: 4→3→2→1 points (25%, 50%, 75%, 100%)
  - 3-keyword word: 4→2→1 points (33%, 67%, 100%)
  """
  def calculate_points(keywords_shown, total_keywords) do
    max(1, 6 - ceil(keywords_shown / total_keywords * 5))
  end

  # Word and Keyword functions

  @doc """
  Gets a word by ID with preloaded keywords.
  """
  def get_word_with_keywords(word_id) do
    Repo.get(Word, word_id)
    |> Repo.preload(:keywords)
  end

  @doc """
  Gets words by IDs.
  """
  def get_words_by_ids(word_ids) do
    from(w in Word, where: w.id in ^word_ids)
    |> Repo.all()
  end

  @doc """
  Gets keywords by IDs.
  """
  def get_keywords_by_ids(keyword_ids) do
    from(k in Keyword, where: k.id in ^keyword_ids)
    |> Repo.all()
  end

  @doc """
  Fetches words for display from WortSchule, handling missing data gracefully.

  Returns a list of word maps with fallback data for missing words.

  ## Examples

      iex> fetch_words_for_display([123, 456])
      [
        %{id: 123, name: "Apfel", image_url: "https://..."},
        %{id: 456, name: "?", image_url: nil}
      ]
  """
  def fetch_words_for_display(word_ids) when is_list(word_ids) do
    alias Mimimi.WortSchule

    words_map = WortSchule.get_complete_words_batch(word_ids)

    Enum.map(word_ids, fn word_id ->
      case Map.get(words_map, word_id) do
        nil -> %{id: word_id, name: "?", image_url: nil}
        word_data -> %{id: word_data.id, name: word_data.name, image_url: word_data.image_url}
      end
    end)
  end

  @doc """
  Fetches keywords for display from WortSchule, handling missing data gracefully.

  Returns a list of keyword maps with fallback data for missing keywords.

  ## Examples

      iex> fetch_keywords_for_display([123, 456])
      [
        %{id: 123, name: "rot"},
        %{id: 456, name: "?"}
      ]
  """
  def fetch_keywords_for_display(keyword_ids) when is_list(keyword_ids) do
    alias Mimimi.WortSchule

    keywords_map = WortSchule.get_words_batch(keyword_ids)

    Enum.map(keyword_ids, fn keyword_id ->
      case Map.get(keywords_map, keyword_id) do
        nil -> %{id: keyword_id, name: "?"}
        keyword_data -> %{id: keyword_data.id, name: keyword_data.name}
      end
    end)
  end

  # PubSub functions

  defp broadcast_game_count_changed do
    Phoenix.PubSub.broadcast(
      Mimimi.PubSub,
      "active_games",
      :game_count_changed
    )
  end

  @doc """
  Broadcasts a message to a game's topic.
  """
  def broadcast_to_game(game_id, message) do
    Phoenix.PubSub.broadcast(
      Mimimi.PubSub,
      "games_id_#{game_id}",
      message
    )
  end

  @doc """
  Subscribes to a game's topic.
  """
  def subscribe_to_game(game_id) do
    Phoenix.PubSub.subscribe(Mimimi.PubSub, "games_id_#{game_id}")
  end

  @doc """
  Subscribes to active games count updates.
  """
  def subscribe_to_active_games do
    Phoenix.PubSub.subscribe(Mimimi.PubSub, "active_games")
  end

  # GameServer functions

  @doc """
  Starts a GameServer for a game and begins the round timer.
  """
  def start_game_server(game_id, round_id, clues_interval) do
    case DynamicSupervisor.start_child(
           Mimimi.GameServerSupervisor,
           {Mimimi.GameServer, game_id}
         ) do
      {:ok, _pid} ->
        Mimimi.GameServer.start_round_timer(game_id, round_id, clues_interval)
        :ok

      {:error, {:already_started, _pid}} ->
        # Server already running, just start the timer
        Mimimi.GameServer.start_round_timer(game_id, round_id, clues_interval)
        :ok

      error ->
        error
    end
  end

  @doc """
  Stops the GameServer for a game.
  """
  def stop_game_server(game_id) do
    case Registry.lookup(Mimimi.GameRegistry, game_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(Mimimi.GameServerSupervisor, pid)
        :ok

      [] ->
        :ok
    end
  end

  @doc """
  Gets the current state of a game server.
  """
  def get_game_server_state(game_id) do
    Mimimi.GameServer.get_state(game_id)
  end

  # Host Dashboard Analytics

  @doc """
  Gets detailed round analytics for the host dashboard.
  Returns information about player picks, timing, and correctness for the current round.
  """
  def get_round_analytics(round_id) do
    # Optimized query with explicit joins to avoid N+1
    round =
      from(r in Round,
        where: r.id == ^round_id,
        join: g in assoc(r, :game),
        left_join: p in assoc(r, :picks),
        left_join: player in assoc(p, :player),
        preload: [game: g, picks: {p, player: player}]
      )
      |> Repo.one!()

    # Batch fetch all word data at once using helper function
    word_ids = Enum.map(round.picks, & &1.word_id)
    words_map = fetch_words_for_display(word_ids) |> Map.new(&{&1.id, &1})

    players_with_picks =
      Enum.map(round.picks, fn pick ->
        # Get word data from the fetched map
        word_data =
          Map.get(words_map, pick.word_id, %{id: pick.word_id, name: "?", image_url: nil})

        %{
          player: pick.player,
          is_correct: pick.is_correct,
          keywords_shown: pick.keywords_shown,
          time: pick.time,
          picked_at: pick.inserted_at,
          picked_word: word_data
        }
      end)

    player_ids_picked = Enum.map(round.picks, & &1.player_id) |> MapSet.new()

    all_players = list_players_for_game(round.game.id)

    players_not_picked =
      all_players
      |> Enum.reject(&MapSet.member?(player_ids_picked, &1.id))

    %{
      total_players: length(all_players),
      picked_count: length(players_with_picks),
      not_picked_count: length(players_not_picked),
      players_picked: players_with_picks,
      players_not_picked: players_not_picked,
      correct_count: Enum.count(players_with_picks, & &1.is_correct),
      wrong_count: Enum.count(players_with_picks, &(not &1.is_correct)),
      average_time: calculate_average_time(players_with_picks),
      fastest_correct_time: fastest_correct_pick_time(players_with_picks)
    }
  end

  defp calculate_average_time([]), do: nil

  defp calculate_average_time(picks) do
    total_time = Enum.reduce(picks, 0, fn pick, acc -> acc + pick.time end)
    div(total_time, length(picks))
  end

  defp fastest_correct_pick_time(picks) do
    picks
    |> Enum.filter(& &1.is_correct)
    |> Enum.map(& &1.time)
    |> Enum.min(fn -> nil end)
  end

  @doc """
  Gets game-wide performance statistics for teacher insights.
  """
  def get_game_performance_stats(game_id) do
    game = Repo.get!(Game, game_id) |> Repo.preload([:players, rounds: :picks])

    completed_rounds = Enum.filter(game.rounds, &(&1.state == "finished"))
    all_picks = Enum.flat_map(completed_rounds, & &1.picks)

    build_game_stats(game_id, game, length(game.rounds), length(completed_rounds), all_picks)
  end

  defp build_game_stats(game_id, _game, total_rounds, _played_rounds, []) do
    %{
      game_id: game_id,
      total_rounds: total_rounds,
      played_rounds: 0,
      average_accuracy: 0.0,
      total_correct: 0,
      total_wrong: 0,
      player_stats: []
    }
  end

  defp build_game_stats(game_id, game, total_rounds, played_rounds, all_picks) do
    correct_picks = Enum.count(all_picks, & &1.is_correct)
    wrong_picks = length(all_picks) - correct_picks
    average_accuracy = correct_picks / length(all_picks) * 100

    player_stats =
      game.players
      |> Enum.map(&build_player_stats(&1, all_picks))
      |> Enum.sort_by(& &1.accuracy, :desc)

    %{
      game_id: game_id,
      total_rounds: total_rounds,
      played_rounds: played_rounds,
      average_accuracy: Float.round(average_accuracy, 1),
      total_correct: correct_picks,
      total_wrong: wrong_picks,
      player_stats: player_stats
    }
  end

  defp build_player_stats(player, all_picks) do
    player_picks = Enum.filter(all_picks, &(&1.player_id == player.id))
    correct = Enum.count(player_picks, & &1.is_correct)
    total = length(player_picks)
    accuracy = if total > 0, do: correct / total * 100, else: 0.0
    avg_keywords = calculate_average_keywords(player_picks, total)

    %{
      player: player,
      picks_made: total,
      correct: correct,
      wrong: total - correct,
      accuracy: Float.round(accuracy, 1),
      average_keywords_used: avg_keywords,
      points: player.points
    }
  end

  defp calculate_average_keywords([], _total), do: 0.0

  defp calculate_average_keywords(player_picks, total) do
    total_kw = Enum.reduce(player_picks, 0, fn p, acc -> acc + p.keywords_shown end)
    Float.round(total_kw / total, 1)
  end

  @doc """
  Gets picks for the current round with player information.
  """
  def get_round_picks_with_players(round_id) do
    from(p in Pick,
      where: p.round_id == ^round_id,
      join: player in assoc(p, :player),
      preload: [player: player],
      order_by: [asc: p.inserted_at]
    )
    |> Repo.all()
  end

  # Game cleanup functions

  @doc """
  Stops and cleans up a game when the host disconnects.
  This prevents zombie games from staying in the system.
  """
  def cleanup_game_on_host_disconnect(game_id) do
    case Repo.get(Game, game_id) do
      nil ->
        :ok

      game ->
        # Stop the game server if running
        stop_game_server(game_id)

        # Update game state to indicate host disconnected
        game
        |> Game.changeset(%{state: "host_disconnected"})
        |> Repo.update()

        # Broadcast to all players that the game was stopped
        broadcast_to_game(game_id, :host_disconnected)
        broadcast_game_count_changed()

        :ok
    end
  end

  @doc """
  Manually stops a game and transitions it to game_over state.
  Used when the host explicitly clicks "Stop this game" button.
  """
  def stop_game_manually(game_id) do
    case Repo.get(Game, game_id) do
      nil ->
        {:error, :not_found}

      game ->
        # Stop the game server if running
        stop_game_server(game_id)

        # Update game state to game_over
        result =
          game
          |> Game.changeset(%{state: "game_over"})
          |> Repo.update()

        # Broadcast to all players that the game was stopped
        case result do
          {:ok, updated_game} ->
            broadcast_to_game(game_id, :game_stopped_by_host)
            broadcast_game_count_changed()
            {:ok, updated_game}

          error ->
            error
        end
    end
  end

  @doc """
  Cancels a game in the waiting_for_players state.
  Removes all players and deletes the game and its invitation.
  Used when the host wants to cancel the game before it starts.
  """
  def cancel_game(game_id) do
    with {:ok, game} <- fetch_game(game_id),
         :ok <- validate_game_can_be_cancelled(game),
         {:ok, _} <- delete_game_and_related_data(game_id, game) do
      broadcast_to_game(game_id, :game_cancelled)
      broadcast_game_count_changed()
      {:ok, :cancelled}
    end
  end

  defp fetch_game(game_id) do
    case Repo.get(Game, game_id) do
      nil -> {:error, :not_found}
      game -> {:ok, game}
    end
  end

  defp validate_game_can_be_cancelled(game) do
    if game.state == "waiting_for_players" do
      :ok
    else
      {:error, :game_already_started}
    end
  end

  defp delete_game_and_related_data(game_id, game) do
    Repo.transaction(fn ->
      # Delete all players in this game
      from(p in Player, where: p.game_id == ^game_id)
      |> Repo.delete_all()

      # Delete the game invitation
      from(i in GameInvite, where: i.game_id == ^game_id)
      |> Repo.delete_all()

      # Delete the game itself
      Repo.delete!(game)
    end)
  end

  @doc """
  Gets a game by ID.
  """
  def get_game(game_id) do
    Repo.get(Game, game_id)
  end

  @doc """
  Gets all correct picks with word images for each player in a game.
  Returns a map where keys are player IDs and values are lists of word data.

  ## Examples

      iex> Games.get_correct_picks_by_player(game_id)
      %{
        "player_1_id" => [
          %{id: 123, name: "Affe", image_url: "https://..."},
          %{id: 456, name: "Baum", image_url: "https://..."}
        ],
        "player_2_id" => [
          %{id: 789, name: "Haus", image_url: "https://..."}
        ]
      }
  """
  def get_correct_picks_by_player(game_id) do
    # Get all picks for this game across all rounds
    picks =
      from(p in Pick,
        join: r in Round,
        on: p.round_id == r.id,
        join: player in Player,
        on: p.player_id == player.id,
        where: r.game_id == ^game_id and p.is_correct == true,
        select: %{player_id: player.id, word_id: p.word_id},
        order_by: [asc: p.inserted_at]
      )
      |> Repo.all()

    # Group picks by player and fetch word data
    picks
    |> Enum.group_by(& &1.player_id, & &1.word_id)
    |> Enum.map(&fetch_words_for_player/1)
    |> Enum.into(%{})
  end

  defp fetch_words_for_player({player_id, word_ids}) do
    words = fetch_words_for_display(word_ids)
    {player_id, words}
  end
end
