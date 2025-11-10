defmodule MimimiWeb.PageController do
  use MimimiWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
