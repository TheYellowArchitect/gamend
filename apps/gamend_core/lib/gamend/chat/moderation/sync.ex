defmodule Gamend.Chat.Moderation.Sync do
  @moduledoc """
  Keeps the node-local word blocklist (`Gamend.Chat.Moderation.Cache`) in sync
  with the database and the other app instances. Mutes are chat bans, kept in
  step by `Gamend.Bans.Sync`.

  After init it loads the blocklist into ETS; afterwards it applies changes
  broadcast by other instances on
  `Gamend.Chat.Moderation.Cache.topic/0`. Events originating on this node are
  skipped — the writer already applied them locally.

  The initial load runs in `handle_continue` and retries rather than failing the
  boot: `init/1` must not couple application startup to the database being
  reachable (e.g. during a rolling restart on an unmigrated table).
  """

  use GenServer

  require Logger

  alias Gamend.Chat.Moderation.Cache

  @retry_ms :timer.seconds(10)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(Gamend.PubSub, Cache.topic())

    if enabled?() do
      {:ok, %{loaded?: false}, {:continue, :load_persisted}}
    else
      # Supervised but idle: in tests there is no sandbox connection for this
      # process, and a boot-time read would starve the pool. Tests drive
      # Cache.load_persisted/0 directly.
      {:ok, %{loaded?: true}}
    end
  end

  @impl true
  def handle_continue(:load_persisted, state), do: {:noreply, attempt_load(state)}

  @impl true
  def handle_info({:chat_moderation, event, payload, from_node}, state) do
    if from_node != Node.self() do
      Cache.apply_remote(event, payload)
    end

    {:noreply, state}
  end

  def handle_info(:retry_load, state), do: {:noreply, attempt_load(state)}

  def handle_info(_message, state), do: {:noreply, state}

  defp attempt_load(%{loaded?: true} = state), do: state

  defp attempt_load(state) do
    Cache.load_persisted()
    %{state | loaded?: true}
  rescue
    e ->
      Logger.error(
        "could not load the chat blocklist (retrying in #{div(@retry_ms, 1000)}s): " <>
          Exception.message(e)
      )

      Process.send_after(self(), :retry_load, @retry_ms)
      state
  end

  defp enabled? do
    :gamend_core
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:enabled, true)
  end
end
