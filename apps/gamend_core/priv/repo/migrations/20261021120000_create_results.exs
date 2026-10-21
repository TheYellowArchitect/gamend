defmodule Gamend.Repo.Migrations.CreateResults do
  @moduledoc """
  `results` and `result_events` (`Gamend.Results`): one row per play per
  player, and what happened in it, in order.

  `lobby_id` is not a foreign key: a lobby is deleted when its play ends,
  and its result is the record that outlives it. An event's order is its
  id (UUIDv7, strictly ordered on a node), so there is no sequence column
  and no writer has to hand out numbers.
  """

  use Ecto.Migration

  def change do
    create table(:results) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :lobby_id, :binary_id
      add :kind, :string, null: false
      add :visibility, :string, null: false, default: "owner_only"
      add :status, :string, null: false, default: "open"
      add :metadata, :map, null: false, default: %{}
      add :started_at, :utc_datetime_usec, null: false
      add :ended_at, :utc_datetime_usec
    end

    # A player's results, newest first, by kind (the reads, the admin filter).
    create index(:results, [:user_id, :kind, :started_at])
    # A lobby's open results (`record_lobby/4`), and the admin's lobby filter.
    create index(:results, [:lobby_id, :status])
    # The admin list and retention, by when a play began.
    create index(:results, [:started_at])
    create index(:results, [:kind, :started_at])

    create table(:result_events) do
      add :result_id, references(:results, on_delete: :delete_all), null: false
      add :elapsed_ms, :bigint, null: false
      add :key, :string, null: false
      add :value, :float
      add :metadata, :map, null: false, default: %{}
    end

    # A result's events in order (the id is the order), and its stats.
    create index(:result_events, [:result_id, :id])
    create index(:result_events, [:result_id, :key])
  end
end
