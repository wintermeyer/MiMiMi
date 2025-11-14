# Exclude external database tests in CI environment
exclude =
  if System.get_env("CI") do
    [:external_db]
  else
    []
  end

ExUnit.start(exclude: exclude)
Ecto.Adapters.SQL.Sandbox.mode(Mimimi.Repo, :manual)
