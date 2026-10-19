defmodule Gamend.Repo.Migrations.IndexForeignKeys do
  @moduledoc """
  An index behind every foreign key that had none.

  Deleting a row makes the database find every row that references it, to
  cascade or null them. Without an index whose first column is the
  referencing column, that is a full scan of the referencing table per
  deleted row. Found at a million demo players (`mix demo.seed`):

    * `leaderboard_records.user_id` — every account deletion, and every guest
      the retention sweep removes, read every leaderboard record (2.5 million
      rows, 450 MB). `Leaderboards.merge_user_records/2` read them all too.
    * `chat_reports.message_id` — deleting a lobby's chat scanned the report
      queue once per message: 100,000 messages took minutes.

  The rest are the same shape on smaller tables. Each is partial on the
  column being set (a lookup by a value implies it), so the many NULLs cost
  nothing to write. Postgres builds them concurrently.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  @columns [
    {:leaderboard_records, :user_id},
    {:chat_reports, :message_id},
    {:chat_reports, :resolved_by},
    {:chat_read_cursors, :last_read_message_id},
    {:reports, :resolved_by},
    {:bans, :banned_by},
    {:bans, :lifted_by},
    {:lobby_snapshots, :user_id},
    {:lobby_events, :user_id},
    {:ready_checks, :opened_by},
    {:ready_check_participants, :ticket_id},
    {:matchmaking_tickets, :match_id},
    {:secrets, :created_by_id},
    {:tournament_matches, :a_entry_id},
    {:tournament_matches, :b_entry_id},
    {:tournament_matches, :winner_entry_id}
  ]

  def up do
    concurrently = repo().__adapter__() == Ecto.Adapters.Postgres

    for {table, column} <- @columns do
      create_if_not_exists index(table, [column],
                             where: "#{column} IS NOT NULL",
                             concurrently: concurrently
                           )
    end
  end

  def down do
    concurrently = repo().__adapter__() == Ecto.Adapters.Postgres

    for {table, column} <- @columns do
      drop_if_exists index(table, [column], concurrently: concurrently)
    end
  end
end
