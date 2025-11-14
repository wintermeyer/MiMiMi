defmodule Mimimi.WortSchuleRepo do
  @moduledoc """
  Read-only Ecto repository for accessing the external wort.schule database.

  This repository connects to a separate PostgreSQL database containing
  German word data, keywords, and images from wort.schule. It should only
  be used for read operations as the database is managed externally.

  ## Configuration

  Development: `wortschule_development` database
  Production: `wortschule_production` database (requires WORTSCHULE_DATABASE_PASSWORD env var)
  """
  use Ecto.Repo,
    otp_app: :mimimi,
    adapter: Ecto.Adapters.Postgres
end
