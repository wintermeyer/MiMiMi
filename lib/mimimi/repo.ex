defmodule Mimimi.Repo do
  use Ecto.Repo,
    otp_app: :mimimi,
    adapter: Ecto.Adapters.Postgres
end
