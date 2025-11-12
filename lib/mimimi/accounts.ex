defmodule Mimimi.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Mimimi.Repo
  alias Mimimi.Accounts.User

  @doc """
  Gets or creates a user by session_id.
  """
  def get_or_create_user_by_session(session_id) do
    case Repo.get_by(User, session_id: session_id) do
      nil ->
        %User{}
        |> User.changeset(%{session_id: session_id})
        |> Repo.insert()

      user ->
        {:ok, user}
    end
  end

  @doc """
  Gets a single user.
  """
  def get_user!(id), do: Repo.get!(User, id)
end
