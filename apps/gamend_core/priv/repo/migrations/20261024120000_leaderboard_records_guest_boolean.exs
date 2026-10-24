defmodule Gamend.Repo.Migrations.LeaderboardRecordsGuestBoolean do
  @moduledoc """
  `leaderboard_records.guest` as a boolean on SQLite.

  `20261019160000_leaderboard_records_guest` flagged the guests' records
  already written with an untyped `true`, which SQLite stored as the text
  'true'. Ecto cannot load that as a boolean, so reading such a record
  raised, and `guest = 1` missed it. This writes those rows' flag as 1;
  nothing else changes.

  No-op on Postgres, where the column only ever holds booleans.
  """
  use Ecto.Migration

  def up do
    if repo().__adapter__() == Ecto.Adapters.SQLite3, do: repair(repo())
  end

  def down, do: :ok

  @doc false
  # Public so its test can run it inside the SQL sandbox, which the migrator
  # cannot (see `Gamend.Repo.Migrations.StableStorageUrls.rewrite/1`).
  def repair(repo) do
    repo.query!("UPDATE leaderboard_records SET guest = 1 WHERE guest = 'true'", [],
      timeout: :infinity
    )
  end
end
