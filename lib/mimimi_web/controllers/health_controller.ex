defmodule MimimiWeb.HealthController do
  use MimimiWeb, :controller

  @moduledoc """
  Health check controller for deployment verification.

  This controller provides a `/health` endpoint that verifies:
  - Application is running
  - Database is connected
  - Essential services are operational
  """

  def index(conn, _params) do
    health_status = check_health()

    status_code = if health_status.healthy, do: 200, else: 503

    conn
    |> put_status(status_code)
    |> json(health_status)
  end

  defp check_health do
    checks = %{
      database: check_database(),
      application: check_application()
    }

    healthy = Enum.all?(checks, fn {_key, status} -> status == :ok end)

    %{
      healthy: healthy,
      checks: checks,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp check_database do
    try do
      # Simple database query to verify connectivity
      case Ecto.Adapters.SQL.query(Mimimi.Repo, "SELECT 1", []) do
        {:ok, _} -> :ok
        {:error, _} -> :error
      end
    rescue
      _ -> :error
    end
  end

  defp check_application do
    # Verify the application is running
    if Process.whereis(Mimimi.Repo) do
      :ok
    else
      :error
    end
  end
end
