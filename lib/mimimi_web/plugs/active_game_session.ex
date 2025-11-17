defmodule MimimiWeb.Plugs.ActiveGameSession do
  import Plug.Conn
  import Phoenix.Controller

  def on_mount(:check_active_game, _params, session, socket) do
    active_game_id = Map.get(session, "active_game_id")

    if active_game_id do
      game = Mimimi.Games.get_game(active_game_id)
      user_id = socket.assigns.current_user.id

      cond do
        is_nil(game) ->
          {:cont, socket}

        game.state in ["waiting_for_players", "game_running"] ->
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

        true ->
          {:cont, socket}
      end
    else
      {:cont, socket}
    end
  end

  def on_mount(:set_active_game, params, _session, socket) do
    game_id = Map.get(params, "id") || Map.get(params, "short_code")

    if game_id do
      {:cont, Phoenix.Component.assign(socket, :pending_active_game_id, game_id)}
    else
      {:cont, socket}
    end
  end
end
