defmodule Gamend.Lobbies.SpectatorTracker do
  @moduledoc """
  Who is watching a lobby without being a member.

  Backed by `Gamend.Presence`, so counts are cluster-wide. The previous ETS
  version was node-local: with more than one node every lobby undercounted,
  silently and by an amount nobody could see.

  Entries follow the watching channel process, so a disconnect — or a whole
  node going down — removes them with no cleanup path to forget.
  """

  alias Gamend.Presence

  @doc false
  @spec topic(Ecto.UUID.t()) :: String.t()
  def topic(lobby_id), do: "lobby_spectators:#{lobby_id}"

  @doc """
  Tracks the calling process as a spectator.

  Call from the channel process: presence follows that process's lifetime.
  """
  @spec track(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def track(lobby_id, user_id) do
    case Presence.track(self(), topic(lobby_id), user_id, %{}) do
      {:ok, _ref} -> :ok
      {:error, {:already_tracked, _, _, _}} -> :ok
    end
  end

  @spec untrack(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def untrack(lobby_id, user_id), do: Presence.untrack(self(), topic(lobby_id), user_id)

  @spec count(Ecto.UUID.t()) :: non_neg_integer()
  def count(lobby_id), do: lobby_id |> topic() |> Presence.keys() |> length()

  @doc "Spectator counts for several lobbies, as `%{lobby_id => count}`."
  @spec counts(list(Ecto.UUID.t())) :: %{Ecto.UUID.t() => non_neg_integer()}
  def counts(lobby_ids) when is_list(lobby_ids) do
    Map.new(lobby_ids, fn id -> {id, count(id)} end)
  end

  @spec list(Ecto.UUID.t()) :: list(Ecto.UUID.t())
  def list(lobby_id), do: lobby_id |> topic() |> Presence.keys()
end
