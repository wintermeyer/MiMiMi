defmodule MimimiWeb.ActiveGamesHook do
  @moduledoc """
  LiveView hook that assigns the active games count and current user to all LiveViews.
  Individual LiveViews can subscribe to updates and handle :game_count_changed messages.
  """

  import Phoenix.Component
  alias Mimimi.Games
  alias Mimimi.Accounts

  def on_mount(:default, _params, session, socket) do
    socket =
      socket
      |> assign_current_user(session)
      |> assign(:active_games, Games.count_active_games())

    {:cont, socket}
  end

  defp assign_current_user(socket, session) do
    session_id = session["session_id"]

    case Accounts.get_or_create_user_by_session(session_id) do
      {:ok, user} ->
        assign(socket, :current_user, user)

      {:error, _} ->
        # If we can't get a user, we should probably handle this better
        # For now, we'll just not assign current_user
        socket
    end
  end
end
