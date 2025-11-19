defmodule MimimiWeb.GameHelpers do
  @moduledoc """
  Shared helper functions for game-related LiveViews.

  This module contains common patterns used across game LiveViews,
  such as validating active games and redirecting users appropriately.
  """

  alias Mimimi.Games

  @doc """
  Checks if a user has an active game and redirects them if appropriate.

  Returns `{:ok, socket}` if no active game or game is not valid for joining,
  or `{:redirect, path}` if the user should be redirected to an active game.

  ## Examples

      case GameHelpers.check_active_game(socket, session) do
        {:ok, socket} ->
          # Continue with mount logic
        {:redirect, path} ->
          {:ok, push_navigate(socket, to: path)}
      end
  """
  def check_active_game(socket, session) do
    case Map.get(session, "active_game_id") do
      nil ->
        {:ok, socket}

      active_game_id ->
        case Games.get_game(active_game_id) do
          %{state: state} when state in ["waiting_for_players", "game_running"] ->
            {:redirect, determine_game_path(active_game_id, state)}

          _ ->
            {:ok, socket}
        end
    end
  end

  @doc """
  Determines the appropriate path for a game based on its state.
  """
  def determine_game_path(game_id, "waiting_for_players"), do: "/dashboard/#{game_id}"
  def determine_game_path(game_id, "game_running"), do: "/game/#{game_id}"
  def determine_game_path(game_id, _state), do: "/dashboard/#{game_id}"

  @doc """
  Returns a human-readable error message for game invitation errors.
  """
  def invitation_error_message(:not_found), do: "Dieser Code existiert nicht."
  def invitation_error_message(:expired), do: "Dieser Code ist abgelaufen."
  def invitation_error_message(:already_started), do: "Dieses Spiel hat bereits begonnen."
  def invitation_error_message(:game_over), do: "Dieses Spiel ist bereits beendet."

  def invitation_error_message(:lobby_timeout),
    do: "Die Lobby-Zeit für dieses Spiel ist abgelaufen."

  def invitation_error_message(:host_disconnected), do: "Der Host hat das Spiel verlassen."
  def invitation_error_message(_), do: "Ein Fehler ist aufgetreten."
end
