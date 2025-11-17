defmodule Mimimi.Presence do
  @moduledoc """
  Phoenix Presence for tracking game hosts and players.

  Tracks:
  - Game hosts (to detect when host browser closes)
  - Players in games (to show host when players disconnect)
  """
  use Phoenix.Presence,
    otp_app: :mimimi,
    pubsub_server: Mimimi.PubSub
end
