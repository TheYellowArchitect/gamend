defmodule Gamend.Repo.Migrations.DropLobbySnapshots do
  @moduledoc """
  Lobby snapshots are gone (2026-10-21): what a play leaves is its result
  (`Gamend.Results`, `20261021120000_create_results`), written by the game as
  things happen, not captured after every hook. Their three tables go with
  their rows, which held lobby metadata and KV and were off by default.

  Rolling back brings the tables back empty, as
  `20260719120000_create_lobby_snapshots` and the `user_id` indexes of
  `20261019130000_index_foreign_keys` left them, so `db.rollback` works and an
  earlier migration's own `down` finds what it drops. The rows do not return.
  """

  use Ecto.Migration

  def up do
    drop_if_exists table(:lobby_events)
    drop_if_exists table(:lobby_snapshots)
    drop_if_exists table(:lobby_snapshot_blobs)
  end

  def down do
    create table(:lobby_snapshot_blobs, primary_key: false) do
      add :hash, :string, primary_key: true
      add :content, :map, null: false
      add :byte_size, :integer, null: false
      add :last_referenced_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:lobby_snapshot_blobs, [:last_referenced_at])

    create table(:lobby_snapshots, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :lobby_id, :binary_id, null: false
      add :trigger, :string, null: false
      add :section_hashes, :map, null: false, default: "{}"
      add :flagged, :boolean, null: false, default: false
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:lobby_snapshots, [:lobby_id, :inserted_at])
    create index(:lobby_snapshots, [:inserted_at])
    create index(:lobby_snapshots, [:flagged, :inserted_at])
    create index(:lobby_snapshots, [:user_id], where: "user_id IS NOT NULL")

    create table(:lobby_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :lobby_id, :binary_id, null: false
      add :kind, :string, null: false
      add :payload, :map, null: false, default: "{}"
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:lobby_events, [:lobby_id, :inserted_at])
    create index(:lobby_events, [:inserted_at])
    create index(:lobby_events, [:user_id], where: "user_id IS NOT NULL")
  end
end
