defmodule Gamend.Repo.Migrations.DropLobbySnapshots do
  @moduledoc """
  Lobby snapshots are gone (2026-10-21): what a play leaves is its result
  (`Gamend.Results`, `20261021120000_create_results`), written by the game as
  things happen, not captured after every hook. Their three tables go with
  their rows, which held lobby metadata and KV and were off by default.
  """

  use Ecto.Migration

  def up do
    drop_if_exists table(:lobby_events)
    drop_if_exists table(:lobby_snapshots)
    drop_if_exists table(:lobby_snapshot_blobs)
  end

  def down do
    raise Ecto.MigrationError,
          "lobby snapshots were removed; restore 20260719120000_create_lobby_snapshots from git to bring them back"
  end
end
