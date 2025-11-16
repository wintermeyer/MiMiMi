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
    Repo.transaction(fn ->
      # Update game state
      game =
        game
        |> Game.changeset(%{state: "game_running", started_at: DateTime.utc_now()})
        |> Repo.update!()

      # Generate rounds
      generate_rounds(game)

      game
    end)
    |> tap(fn
      {:ok, _game} -> broadcast_game_count_changed()
      _ -> :ok
    end)
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
  Restarts a game with the same settings.
  """
  def restart_game(%Game{} = old_game) do
    create_game(old_game.host_user_id, %{
      rounds_count: old_game.rounds_count,
      clues_interval: old_game.clues_interval,
      grid_size: old_game.grid_size
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
  Generates all rounds for a game.
  """
  def generate_rounds(%Game{} = game) do
    # Get words with sufficient keywords
    words_with_keywords =
      from(w in Word,
        join: k in assoc(w, :keywords),
        group_by: w.id,
        having: count(k.id) >= 2,
        select: w.id
      )
      |> Repo.all()

    if length(words_with_keywords) < game.rounds_count do
      raise "Not enough words with keywords to generate #{game.rounds_count} rounds"
    end

    # Get all words for distractors
    all_word_ids = Repo.all(from w in Word, select: w.id)

    # Generate each round
    Enum.each(1..game.rounds_count, fn position ->
      # Select a target word
      target_word_id = Enum.random(words_with_keywords)

      # Get keywords for this word
      keyword_ids =
        from(k in Keyword, where: k.word_id == ^target_word_id, select: k.id)
        |> Repo.all()
        |> Enum.shuffle()
        |> Enum.take(5)

      # Create possible words list (target + distractors)
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
    end)
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
    |> case do
      nil -> nil
      round -> Repo.preload(round, :word)
    end
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
  """
  def create_pick(round_id, player_id, attrs) do
    attrs =
      attrs
      |> Map.put(:round_id, round_id)
      |> Map.put(:player_id, player_id)

    %Pick{}
    |> Pick.changeset(attrs)
    |> Repo.insert()
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
  Formula: total_keywords - keywords_shown + 1
  """
  def calculate_points(keywords_shown, total_keywords \\ 5) do
    max(1, total_keywords - keywords_shown + 1)
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
end
