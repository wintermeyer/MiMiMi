defmodule Mimimi.HotDeploy do
  @moduledoc """
  Filesystem-based hot code upgrade system inspired by FlyDeploy.

  Enables zero-downtime deployments by upgrading running BEAM processes
  while preserving their state, without requiring S3 storage.

  ## Usage

  Add to your application start before the supervision tree:

      def start(_type, _args) do
        Mimimi.HotDeploy.startup_reapply_current()

        children = [...]
        Supervisor.start_link(children, strategy: :one_for_one)
      end

  ## Deployment Flow

  1. New release is built and beam files extracted to staging directory
  2. Metadata file is written with deployment information
  3. Running application detects new deployment on next check
  4. Changed modules are identified
  5. Affected processes are suspended
  6. New code is loaded
  7. code_change/3 callbacks are triggered
  8. Processes resume execution

  ## Configuration

  Configure in config/runtime.exs:

      config :mimimi, Mimimi.HotDeploy,
        enabled: true,
        upgrades_dir: "/var/www/pmg/shared/hot-upgrades",
        check_interval: 10_000  # Check every 10 seconds

  ## Limitations

  Hot upgrades cannot handle:
  - Changes to supervision tree structure
  - Adding/removing supervised applications
  - Configuration changes requiring restart
  - Erlang VM or OTP version upgrades
  - Database migrations (these still run during deployment)

  For these cases, deployment will fall back to cold deploy (restart).
  """

  require Logger

  @doc """
  Startup function to reapply any pending hot upgrades.

  Should be called before starting the supervision tree to ensure
  the application starts with the latest code.
  """
  def startup_reapply_current do
    if enabled?() do
      Logger.info("[HotDeploy] Checking for pending upgrades on startup...")
      handle_startup_upgrade()
      start_upgrade_checker()
    else
      Logger.debug("[HotDeploy] Hot deploy disabled")
    end

    :ok
  end

  defp handle_startup_upgrade do
    case load_current_metadata() do
      {:ok, metadata} ->
        maybe_apply_upgrade(metadata)

      {:error, :not_found} ->
        Logger.debug("[HotDeploy] No previous upgrades found")

      {:error, reason} ->
        Logger.warning("[HotDeploy] Failed to load metadata: #{inspect(reason)}")
    end
  end

  defp maybe_apply_upgrade(metadata) do
    if should_apply_upgrade?(metadata) do
      Logger.info("[HotDeploy] Applying pending upgrade: #{metadata["version"]}")
      apply_upgrade(metadata)
    else
      Logger.debug("[HotDeploy] No pending upgrades")
    end
  end

  @doc """
  Manually trigger a hot code upgrade check.
  Returns {:ok, :upgraded} if upgrade was applied, {:ok, :no_upgrade} if none available.
  """
  def check_and_upgrade do
    if enabled?() do
      case load_current_metadata() do
        {:ok, metadata} -> process_upgrade(metadata)
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :disabled}
    end
  end

  defp process_upgrade(metadata) do
    if should_apply_upgrade?(metadata) do
      apply_upgrade(metadata)
      {:ok, :upgraded}
    else
      {:ok, :no_upgrade}
    end
  end

  # Private functions

  defp enabled? do
    Application.get_env(:mimimi, __MODULE__, [])
    |> Keyword.get(:enabled, false)
  end

  defp upgrades_dir do
    Application.get_env(:mimimi, __MODULE__, [])
    |> Keyword.get(:upgrades_dir, "/var/www/mimimi/shared/hot-upgrades")
  end

  defp check_interval do
    Application.get_env(:mimimi, __MODULE__, [])
    |> Keyword.get(:check_interval, 10_000)
  end

  defp start_upgrade_checker do
    spawn(fn ->
      Process.sleep(check_interval())
      check_loop()
    end)

    :ok
  end

  defp check_loop do
    case check_and_upgrade() do
      {:ok, :upgraded} ->
        Logger.info("[HotDeploy] Upgrade applied successfully")

      {:ok, :no_upgrade} ->
        Logger.debug("[HotDeploy] No new upgrades available")

      {:error, reason} ->
        Logger.warning("[HotDeploy] Upgrade check failed: #{inspect(reason)}")
    end

    Process.sleep(check_interval())
    check_loop()
  end

  defp load_current_metadata do
    metadata_path = Path.join(upgrades_dir(), "current.json")

    case File.read(metadata_path) do
      {:ok, content} ->
        Jason.decode(content)

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp should_apply_upgrade?(metadata) do
    current_version = Application.get_env(:mimimi, :hot_deploy_version)
    new_version = metadata["version"]

    cond do
      is_nil(new_version) ->
        false

      is_nil(current_version) ->
        true

      new_version != current_version ->
        true

      true ->
        false
    end
  end

  defp apply_upgrade(metadata) do
    version = metadata["version"]
    beams_dir = Path.join(upgrades_dir(), version)

    Logger.info("[HotDeploy] Starting hot code upgrade to #{version}")
    Logger.info("[HotDeploy] Loading beam files from: #{beams_dir}")

    try do
      # Step 1: Load all beam files from directory
      beam_files = find_beam_files(beams_dir)
      Logger.info("[HotDeploy] Found #{length(beam_files)} beam files")

      # Step 2: Load new code into memory (but don't switch yet)
      loaded_modules = load_beam_files(beam_files)
      Logger.info("[HotDeploy] Loaded #{length(loaded_modules)} modules")

      # Step 3: Identify changed modules
      changed_modules = :code.modified_modules()
      Logger.info("[HotDeploy] Detected #{length(changed_modules)} changed modules")

      if changed_modules != [] do
        # Step 4: Find all processes using changed modules
        affected_processes = find_affected_processes(changed_modules)
        Logger.info("[HotDeploy] Found #{length(affected_processes)} affected processes")

        # Step 5: Suspend all affected processes
        Logger.info("[HotDeploy] Suspending affected processes...")
        suspend_processes(affected_processes)

        # Step 6: Purge old code and make new code current
        Logger.info("[HotDeploy] Purging old code and activating new code...")

        Enum.each(changed_modules, fn module ->
          :code.purge(module)
          :code.delete(module)
        end)

        # Step 7: Trigger code_change callbacks
        Logger.info("[HotDeploy] Triggering code_change callbacks...")
        upgrade_processes(affected_processes, changed_modules)

        # Step 8: Resume all processes
        Logger.info("[HotDeploy] Resuming processes...")
        resume_processes(affected_processes)
      end

      # Step 9: Update version tracking
      Application.put_env(:mimimi, :hot_deploy_version, version)
      Logger.info("[HotDeploy] ✅ Hot upgrade completed successfully!")

      # Step 10: Trigger Phoenix LiveView re-renders
      broadcast_upgrade()

      {:ok, version}
    catch
      kind, reason ->
        Logger.error("[HotDeploy] ❌ Upgrade failed: #{inspect({kind, reason})}")
        Logger.error("[HotDeploy] Stack: #{inspect(__STACKTRACE__)}")
        {:error, reason}
    end
  end

  defp find_beam_files(beams_dir) do
    Path.join(beams_dir, "**/*.beam")
    |> Path.wildcard()
  end

  defp load_beam_files(beam_files) do
    beam_files
    |> Enum.flat_map(&load_single_beam_file/1)
    |> Enum.uniq()
  end

  defp load_single_beam_file(beam_file) do
    with {:ok, {module, _chunks}} <- :beam_lib.chunks(beam_file, [:atoms]),
         {:ok, binary} <- File.read(beam_file),
         {:module, ^module} <- :code.load_binary(module, beam_file, binary) do
      [module]
    else
      _ -> []
    end
  end

  defp find_affected_processes(modules) do
    module_set = MapSet.new(modules)

    Process.list()
    |> Enum.filter(fn pid ->
      case Process.info(pid, :current_function) do
        {:current_function, {module, _fun, _arity}} ->
          MapSet.member?(module_set, module)

        _ ->
          false
      end
    end)
  end

  defp suspend_processes(processes) do
    Enum.each(processes, fn pid ->
      try do
        :sys.suspend(pid)
      catch
        _, _ -> :ok
      end
    end)
  end

  defp resume_processes(processes) do
    Enum.each(processes, fn pid ->
      try do
        :sys.resume(pid)
      catch
        _, _ -> :ok
      end
    end)
  end

  defp upgrade_processes(processes, modules) do
    module_set = MapSet.new(modules)

    Enum.each(processes, fn pid ->
      try do
        case Process.info(pid, :current_function) do
          {:current_function, {module, _fun, _arity}} ->
            if MapSet.member?(module_set, module) do
              :sys.change_code(pid, module, :undefined, :undefined)
            end

          _ ->
            :ok
        end
      catch
        _, _ -> :ok
      end
    end)
  end

  defp broadcast_upgrade do
    # Broadcast to all LiveView processes to trigger re-render
    Phoenix.PubSub.broadcast(
      Mimimi.PubSub,
      "hot_deploy:upgrade",
      {:hot_deploy, :upgraded}
    )
  end
end
