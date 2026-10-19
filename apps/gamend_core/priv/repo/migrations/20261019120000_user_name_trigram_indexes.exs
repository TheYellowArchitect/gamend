defmodule Gamend.Repo.Migrations.UserNameTrigramIndexes do
  @moduledoc """
  Trigram indexes on the names (and email) every player search reads.

  A search is `lower(coalesce(name, '')) LIKE '%term%'`, which no B-tree can
  serve: at a million players each search read every user (and a leaderboard
  or member search read every row of the board as well, joined to them).
  `pg_trgm` indexes the same expressions, so `Gamend.Query.users_named/1`
  finds the few players a term names in a millisecond and the big table is
  then read by their ids, and the admin's player search
  (`Gamend.Accounts.Search`) finds a name or an email the same way.

  Postgres only, and only where the extension can be made: `pg_trgm` is a
  trusted extension (PostgreSQL 13+), so a database owner may create it, but
  a role without that right gets a warning here and keeps the scans. SQLite
  has no trigram index. Built concurrently, so an existing table stays
  writable while they build.
  """
  use Ecto.Migration

  require Logger

  @disable_ddl_transaction true
  @disable_migration_lock true

  # The expressions the searches read: email is citext on Postgres, which
  # the trigram operator class does not take, so it is read as text.
  @indexes [
    {"users_username_trgm_index", "username"},
    {"users_display_name_trgm_index", "display_name"},
    {"users_email_trgm_index", "CAST(email AS TEXT)"}
  ]

  def up do
    if repo().__adapter__() == Ecto.Adapters.Postgres do
      case repo().query("CREATE EXTENSION IF NOT EXISTS pg_trgm") do
        {:ok, _} ->
          for {name, column} <- @indexes do
            execute("""
            CREATE INDEX CONCURRENTLY IF NOT EXISTS #{name} ON users
            USING gin ((lower(coalesce(#{column}, ''))) gin_trgm_ops)
            """)
          end

        {:error, error} ->
          Logger.warning(
            "pg_trgm is not available (#{Exception.message(error)}): " <>
              "player searches keep reading every user"
          )
      end
    end
  end

  def down do
    if repo().__adapter__() == Ecto.Adapters.Postgres do
      for {name, _column} <- @indexes do
        execute("DROP INDEX CONCURRENTLY IF EXISTS #{name}")
      end
    end
  end
end
