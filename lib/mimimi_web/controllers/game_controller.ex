defmodule MimimiWeb.GameController do
  use MimimiWeb, :controller
  alias Mimimi.Games

  @doc """
  Sets the host token cookie and redirects to the dashboard.
  This is used after creating a new game to establish host authentication.
  """
  def set_host_token(conn, %{"game_id" => game_id}) do
    # Get the game to retrieve the host token
    game = Games.get_game_with_players(game_id)

    # Set the host token in a signed session cookie (expires in 24 hours)
    conn
    |> put_session("host_token_#{game_id}", game.host_token)
    |> redirect(to: ~p"/dashboard/#{game_id}")
  end
end
