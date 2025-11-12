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

    case Accounts.get_or_create_user_by_session(session_id) do
      {:ok, user} ->
        assign(conn, :current_user, user)

      {:error, _} ->
        conn
    end
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
