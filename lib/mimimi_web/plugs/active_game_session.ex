defmodule MimimiWeb.Plugs.ActiveGameSession do
  @moduledoc """
  A LiveView hook that checks for active game sessions and redirects users accordingly.

  Provides two hooks:
  - `:check_active_game` - Checks if the user has an active game and redirects to it
  - `:set_active_game` - Sets a pending active game ID from route params
  """

  def on_mount(:check_active_game, _params, session, socket) do
    active_game_id = Map.get(session, "active_game_id")
    check_active_game(socket, active_game_id)
  end

  def on_mount(:set_active_game, params, _session, socket) do
    game_id = Map.get(params, "id") || Map.get(params, "short_code")

    if game_id do
      {:cont, Phoenix.Component.assign(socket, :pending_active_game_id, game_id)}
    else
      {:cont, socket}
    end
  end

  defp check_active_game(socket, nil), do: {:cont, socket}

  defp check_active_game(socket, active_game_id) do
    game = Mimimi.Games.get_game(active_game_id)
    user_id = socket.assigns.current_user.id

    cond do
      is_nil(game) ->
        {:cont, socket}

      game.state in ["waiting_for_players", "game_running"] ->
        redirect_if_in_game(socket, game, user_id)

      true ->
        {:cont, socket}
    end
  end

  defp redirect_if_in_game(socket, game, user_id) do
    player = Mimimi.Games.get_player_by_game_and_user(game.id, user_id)
    is_host = game.host_user_id == user_id

    cond do
      is_host ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(
           :info,
           "Du bist bereits in einem Spiel als Gastgeber."
         )
         |> Phoenix.LiveView.push_navigate(to: "/dashboard/#{game.id}")}

      player ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:info, "Du bist bereits in einem Spiel.")
         |> Phoenix.LiveView.push_navigate(to: "/games/#{game.id}/current")}

      true ->
        {:cont, socket}
    end
  end
end
