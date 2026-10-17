defmodule Gamend.Bans.SyncTest do
  # The ban table kept in step with the other instances (`Gamend.Bans.Sync`):
  # a ban or lift broadcast from another node is applied here, one from this
  # node is not (the writer applied it already), and the persisted bans load.
  use Gamend.DataCase, async: false

  alias Gamend.Bans.Cache
  alias Gamend.Bans.Sync

  @key {:ip, "203.0.113.88"}

  setup do
    Cache.init_table()
    :ets.delete_all_objects(:bans)
    :ok
  end

  defp later, do: DateTime.utc_now() |> DateTime.add(3600, :second)

  test "a ban from another node is applied, and its lift removes it" do
    {:noreply, _} =
      Sync.handle_info({:bans, :put, {@key, later()}, :other@node}, %{loaded?: true})

    assert Cache.banned?(:ip, "203.0.113.88")

    {:noreply, _} = Sync.handle_info({:bans, :deleted, @key, :other@node}, %{loaded?: true})

    refute Cache.banned?(:ip, "203.0.113.88")
  end

  test "an event this node sent is not applied twice" do
    {:noreply, _} =
      Sync.handle_info({:bans, :put, {@key, later()}, Node.self()}, %{loaded?: true})

    refute Cache.banned?(:ip, "203.0.113.88")
  end

  test "the persisted bans load once; a later retry is a no-op" do
    assert {:noreply, %{loaded?: true}} = Sync.handle_continue(:load_persisted, %{loaded?: false})
    assert {:noreply, %{loaded?: true}} = Sync.handle_info(:retry_load, %{loaded?: true})
    assert {:noreply, %{loaded?: true}} = Sync.handle_info(:unrelated, %{loaded?: true})
  end
end
