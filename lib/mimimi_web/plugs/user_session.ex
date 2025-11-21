defmodule MimimiWeb.Plugs.UserSession do
  @moduledoc """
  Plug to automatically create or fetch a user based on session ID.
  """

  import Plug.Conn
  alias Mimimi.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    session_id = get_session(conn, :session_id) || generate_session_id()

    conn = put_session(conn, :session_id, session_id)

    # Read show_markers preference from cookie and put in session
    conn = read_show_markers_cookie(conn)

    case Accounts.get_or_create_user_by_session(session_id) do
      {:ok, user} ->
        assign(conn, :current_user, user)

      {:error, _} ->
        conn
    end
  end

  defp read_show_markers_cookie(conn) do
    conn = fetch_cookies(conn)

    show_markers =
      case Map.get(conn.cookies, "show_markers") do
        "true" -> true
        _ -> false
      end

    # Read game settings cookies
    rounds_count = Map.get(conn.cookies, "game_rounds_count", "3")
    clues_interval = Map.get(conn.cookies, "game_clues_interval", "9")
    grid_size = Map.get(conn.cookies, "game_grid_size", "9")

    word_types =
      case Map.get(conn.cookies, "game_word_types") do
        nil -> ["Noun", "Verb", "Adjective", "Adverb", "Other"]
        "" -> ["Noun", "Verb", "Adjective", "Adverb", "Other"]
        types_string -> String.split(types_string, ",", trim: true)
      end

    conn
    |> put_session("show_markers", show_markers)
    |> put_session("game_rounds_count", rounds_count)
    |> put_session("game_clues_interval", clues_interval)
    |> put_session("game_grid_size", grid_size)
    |> put_session("game_word_types", word_types)
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
