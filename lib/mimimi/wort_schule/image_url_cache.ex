defmodule Mimimi.WortSchule.ImageUrlCache do
  @moduledoc """
  ETS-based cache for WortSchule image URLs with 24-hour expiration.
  Avoids repeated API calls for the same word images.
  """
  use GenServer
  require Logger

  @table_name :wortschule_image_urls
  @pending_table :wortschule_pending_fetches
  @cache_ttl :timer.hours(24)

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Get cached image URL for a word ID.
  Returns {:ok, url} if cached and not expired, :miss otherwise.
  """
  def get(word_id) do
    if table_exists?() do
      lookup_and_check(word_id)
    else
      :miss
    end
  end

  @doc """
  Try to acquire a lock for fetching a word's image URL.
  Returns :ok if lock acquired, {:waiting, ref} if another process is already fetching.
  """
  def try_fetch_lock(word_id) do
    GenServer.call(__MODULE__, {:try_fetch_lock, word_id, self()})
  end

  @doc """
  Release the fetch lock and notify any waiting processes.
  """
  def release_fetch_lock(word_id) do
    GenServer.cast(__MODULE__, {:release_fetch_lock, word_id})
  end

  defp lookup_and_check(word_id) do
    case :ets.lookup(@table_name, word_id) do
      [{^word_id, url, expires_at}] ->
        check_expiration(url, expires_at)

      [] ->
        :miss
    end
  end

  defp check_expiration(url, expires_at) do
    if System.monotonic_time(:millisecond) < expires_at do
      {:ok, url}
    else
      :miss
    end
  end

  @doc """
  Store image URL in cache with 24-hour expiration.
  """
  def put(word_id, url) do
    if table_exists?() do
      expires_at = System.monotonic_time(:millisecond) + @cache_ttl
      :ets.insert(@table_name, {word_id, url, expires_at})
    end

    :ok
  end

  @doc """
  Clear all cached entries (useful for testing or manual cache invalidation).
  """
  def clear do
    if table_exists?() do
      :ets.delete_all_objects(@table_name)
    end

    :ok
  end

  @doc """
  Get cache statistics: total entries and expired entries count.
  """
  def stats do
    if table_exists?() do
      now = System.monotonic_time(:millisecond)
      total = :ets.info(@table_name, :size)

      expired =
        :ets.select_count(@table_name, [
          {{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}
        ])

      %{total: total, expired: expired, active: total - expired}
    else
      %{total: 0, expired: 0, active: 0}
    end
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])
    :ets.new(@pending_table, [:named_table, :set, :public])
    Logger.info("[ImageUrlCache] Started with 24-hour TTL")

    schedule_cleanup()

    {:ok, %{}}
  end

  @impl true
  def handle_call({:try_fetch_lock, word_id, pid}, _from, state) do
    reply =
      if table_exists?(@pending_table) do
        case :ets.lookup(@pending_table, word_id) do
          [] ->
            :ets.insert(@pending_table, {word_id, pid})
            :ok

          [{^word_id, _other_pid}] ->
            :already_fetching
        end
      else
        :ok
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_cast({:release_fetch_lock, word_id}, state) do
    if table_exists?(@pending_table) do
      :ets.delete(@pending_table, word_id)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired_entries()
    schedule_cleanup()
    {:noreply, state}
  end

  # Private Functions

  defp table_exists? do
    table_exists?(@table_name)
  end

  defp table_exists?(table) do
    case :ets.whereis(table) do
      :undefined -> false
      _ -> true
    end
  end

  defp schedule_cleanup do
    # Run cleanup every 6 hours
    Process.send_after(self(), :cleanup, :timer.hours(6))
  end

  defp cleanup_expired_entries do
    now = System.monotonic_time(:millisecond)

    deleted =
      :ets.select_delete(@table_name, [
        {{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}
      ])

    if deleted > 0 do
      Logger.debug("[ImageUrlCache] Cleaned up #{deleted} expired entries")
    end

    deleted
  end
end
