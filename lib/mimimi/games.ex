defmodule Mimimi.Games do
  @moduledoc """
  The Games context.
  """

  import Ecto.Query, warn: false
  alias Mimimi.Repo
  alias Mimimi.Games.{Game, GameInvite, Player, Round, Pick, Word, Keyword}

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
    timeout_seconds = 15 * 60
    # Convert NaiveDateTime to DateTime for comparison
    inserted_at_utc = DateTime.from_naive!(inserted_at, "Etc/UTC")
    DateTime.diff(DateTime.utc_now(), inserted_at_utc, :second) >= timeout_seconds
  end

  def lobby_timeout?(_game), do: false

  @doc """
  Calculates seconds remaining until lobby timeout.
  """
  def calculate_lobby_time_remaining(%Game{inserted_at: inserted_at}) do
    timeout_seconds = 15 * 60
    # Convert NaiveDateTime to DateTime for comparison
    inserted_at_utc = DateTime.from_naive!(inserted_at, "Etc/UTC")
    elapsed = DateTime.diff(DateTime.utc_now(), inserted_at_utc, :second)
    max(0, timeout_seconds - elapsed)
  end

  @doc """
  Starts a game and generates rounds.
  """
  def start_game(%Game{} = game) do
    result =
      Repo.transaction(fn ->
        # Update game state
        game =
          game
          |> Game.changeset(%{state: "game_running", started_at: DateTime.utc_now()})
          |> Repo.update!()

        # Generate rounds
        generate_rounds(game)

        # Activate the first round
        case advance_to_next_round(game.id) do
          {:ok, _round} -> :ok
          {:error, _} -> :ok
        end

        game
      end)

    case result do
      {:ok, game} ->
        broadcast_game_count_changed()
        broadcast_to_game(game.id, :round_started)
        {:ok, game}

      error ->
        error
    end
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
    timeout_seconds = 15 * 60
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

    # Generate each round
    Enum.each(1..game.rounds_count, fn position ->
      generate_single_round(game, position, target_word_ids, all_word_ids)
    end)
  end

  defp generate_single_round(game, position, available_targets, all_word_ids) do
    alias Mimimi.WortSchule

    target_word_id = Enum.random(available_targets)

    case WortSchule.get_complete_word(target_word_id) do
      {:ok, word_data} ->
        keyword_ids =
          word_data.keywords
          |> Enum.shuffle()
          |> Enum.take(3)
          |> Enum.map(& &1.id)

        distractor_ids =
          (all_word_ids -- [target_word_id])
          |> Enum.shuffle()
          |> Enum.take(game.grid_size - 1)

        possible_words_ids = Enum.shuffle([target_word_id | distractor_ids])

        %Round{}
        |> Round.changeset(%{
          game_id: game.id,
          word_id: target_word_id,
          keyword_ids: keyword_ids,
          possible_words_ids: possible_words_ids,
          position: position,
          state: "on_hold"
        })
        |> Repo.insert!()

      {:error, :not_found} ->
        new_targets = available_targets -- [target_word_id]

        if new_targets == [] do
          raise "Failed to fetch keyword data for all available target words"
        end

        generate_single_round(game, position, new_targets, all_word_ids)
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
  Calculates points for a pick.
  Formula:
  - 1 keyword = 5 points
  - 2 keywords = 3 points
  - 3 keywords = 1 point
  """
  def calculate_points(keywords_shown, _total_keywords \\ 5) do
    case keywords_shown do
      1 -> 5
      2 -> 3
      _ -> 1
    end
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
    alias Mimimi.WortSchule

    round = Repo.get!(Round, round_id) |> Repo.preload([:game, picks: :player])

    players_with_picks =
      Enum.map(round.picks, fn pick ->
        # Fetch the word data including image
        word_data =
          case WortSchule.get_complete_word(pick.word_id) do
            {:ok, data} -> %{id: data.id, name: data.name, image_url: data.image_url}
            {:error, _} -> %{id: pick.word_id, name: "?", image_url: nil}
          end

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
  Gets a game by ID.
  """
  def get_game(game_id) do
    Repo.get(Game, game_id)
  end
end
