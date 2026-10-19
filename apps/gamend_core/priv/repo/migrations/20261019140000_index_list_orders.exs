defmodule Gamend.Repo.Migrations.IndexListOrders do
  @moduledoc """
  An index in the order the lists read, where there was none.

  A page of a list sorted by a column no index covers is a sort of the whole
  table, every page: at a million rows, 0.2 to 1 s per page of the admin
  notification, friend, chat and push lists, the admin player list, a
  group's member list (the public page and the admin modal) and a cup's
  entries. With the index, a page reads its rows in order and stops.

  Only columns that never change after insert: an index on `updated_at`
  (the admin KV and quest-progress lists sort by it) would make every write
  to those hot tables an index write as well, which costs more than an admin
  list is worth.
  """
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  @indexes [
    {:group_members, [:group_id, :inserted_at], []},
    {:tournament_entries, [:tournament_id, :inserted_at], []},
    # The cup page's order: drawn entries first (`Tournaments.list_entries/2`).
    {:tournament_entries,
     [:tournament_id, "coalesce(bracket_index, 2147483647)", :seed, :inserted_at],
     [name: :tournament_entries_bracket_order_index]},
    {:notifications, [:inserted_at, :id], []},
    {:push_tokens, [:inserted_at, :id], []},
    {:friendships, [:inserted_at], []},
    {:chat_messages, [:inserted_at], []},
    {:users, [:inserted_at], []}
  ]

  def up do
    concurrently = repo().__adapter__() == Ecto.Adapters.Postgres

    for {table, columns, opts} <- @indexes do
      create_if_not_exists index(table, columns, [concurrently: concurrently] ++ opts)
    end
  end

  def down do
    concurrently = repo().__adapter__() == Ecto.Adapters.Postgres

    for {table, columns, opts} <- @indexes do
      drop_if_exists index(table, columns, [concurrently: concurrently] ++ opts)
    end
  end
end
