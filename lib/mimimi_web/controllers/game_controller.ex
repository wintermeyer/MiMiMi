defmodule MimimiWeb.GameController do
  use MimimiWeb, :controller
  alias Mimimi.Games

  @doc """
  Sets the host token cookie and redirects to the dashboard.
  This is used after creating a new game to establish host authentication.
  """
  def set_host_token(conn, %{"game_id" => game_id}) do
    game = Games.get_game_with_players(game_id)

    conn
    |> cleanup_old_host_tokens()
    |> put_session("host_token_#{game_id}", game.host_token)
    |> put_session("active_game_id", game_id)
    |> redirect(to: ~p"/dashboard/#{game_id}")
  end

  @doc """
  Sets the active game ID and redirects to the game play page.
  Called after a player joins a game by selecting an avatar.
  """
  def join_game(conn, %{"game_id" => game_id}) do
    conn
    |> put_session("active_game_id", game_id)
    |> redirect(to: ~p"/games/#{game_id}/current")
  end

  @doc """
  Clears the active game from session when a game ends or player leaves.
  """
  def leave_game(conn, _params) do
    conn
    |> delete_session("active_game_id")
    |> redirect(to: ~p"/")
  end

  defp cleanup_old_host_tokens(conn) do
    session_keys = conn.private.plug_session |> Map.keys()

    host_token_keys =
      session_keys
      |> Enum.filter(&String.starts_with?(&1, "host_token_"))

    if length(host_token_keys) > 10 do
      oldest_keys = host_token_keys |> Enum.sort() |> Enum.take(length(host_token_keys) - 10)

      Enum.reduce(oldest_keys, conn, fn key, acc_conn ->
        Plug.Conn.delete_session(acc_conn, key)
      end)
    else
      conn
    end
  end
end
