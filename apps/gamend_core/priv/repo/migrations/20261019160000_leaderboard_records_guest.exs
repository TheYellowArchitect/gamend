defmodule Gamend.Repo.Migrations.LeaderboardRecordsGuest do
  @moduledoc """
  `leaderboard_records.guest`: whether the record's player is a guest, an
  account with no email and no provider (`Gamend.Accounts.User.anonymous?/1`).

  A host that lists registered players only (`Gamend.AccountRequired`,
  `:leaderboards`) kept guests off its public boards by joining every record
  to its user. At a million records a board that read a user row per record:
  a rank, a search or a cold count took 0.6 to 1.5 s, and Postgres could not
  turn the join into a hash of the registered users. With the flag on the
  record, a listed read is `NOT guest` on the record itself, served by its
  own partial rank index.

  The database keeps the flag, so no writer can miss it:

    * a record inserted (a submit, a merge, the all-time fill, a bulk seed)
      takes it from its user (`leaderboard_records_guest`);
    * a user who gains or loses their last identity moves every record of
      theirs (`users_leaderboard_guest`, an update of the identity columns
      that changes whether the account is a guest).

  A label's record has no user and is never a guest. The identity columns
  are `User.identity_fields/0`; a new one needs these triggers made again.

  The records already written are flagged in batches of 10,000 by id, each
  committed on its own: one statement over a million guests' records took
  20 minutes and more and held each of them locked until it ended, so their
  submits waited as long. A batch is about 3 s on a laptop with Postgres'
  default 128 MB of shared buffers (every index of the table takes the new
  row), so ten million records take an hour or two, the site up meanwhile;
  a few thousand take a second. On Postgres the migration can be run again
  after it stops part way, and the index is built concurrently.
  """
  use Ecto.Migration

  import Ecto.Query, only: [from: 2]

  @disable_ddl_transaction true
  @disable_migration_lock true

  @identity ~w(email discord_id apple_id steam_id google_id facebook_id github_id)a
  @batch 10_000

  def up do
    alter table(:leaderboard_records) do
      if postgres?(),
        do: add_if_not_exists(:guest, :boolean, null: false, default: false),
        else: add(:guest, :boolean, null: false, default: false)
    end

    if postgres?(), do: postgres_triggers(), else: sqlite_triggers()

    # The column and the triggers first: from here on every new record and
    # every registration keeps the flag, and the backfill reads the column.
    flush()
    backfill(nil)

    create_if_not_exists index(
                           :leaderboard_records,
                           [:leaderboard_id, :key, :score, :inserted_at],
                           name: :leaderboard_records_listed_rank_index,
                           where: if(postgres?(), do: "NOT guest", else: "guest = 0"),
                           concurrently: postgres?()
                         )
  end

  def down do
    drop_if_exists index(:leaderboard_records, [:leaderboard_id, :key, :score, :inserted_at],
                     name: :leaderboard_records_listed_rank_index,
                     concurrently: postgres?()
                   )

    if postgres?() do
      execute("DROP TRIGGER IF EXISTS users_leaderboard_guest ON users")
      execute("DROP TRIGGER IF EXISTS leaderboard_records_guest ON leaderboard_records")
      execute("DROP FUNCTION IF EXISTS users_leaderboard_guest()")
      execute("DROP FUNCTION IF EXISTS leaderboard_records_guest()")
    else
      execute("DROP TRIGGER IF EXISTS users_leaderboard_guest")
      execute("DROP TRIGGER IF EXISTS leaderboard_records_guest")
    end

    alter table(:leaderboard_records) do
      remove :guest
    end
  end

  defp postgres?, do: repo().__adapter__() == Ecto.Adapters.Postgres

  # Every record already written, from its user as they are now: the next
  # `@batch` ids (UUIDv7, so in the order they were written) per statement.
  defp backfill(after_id) do
    bound =
      from(r in "leaderboard_records",
        select: r.id,
        order_by: r.id,
        offset: ^(@batch - 1),
        limit: 1
      )
      |> after_id(after_id)
      |> repo().one(timeout: :infinity)

    from(r in "leaderboard_records",
      where: r.guest == false and r.user_id in subquery(anonymous_users())
    )
    |> after_id(after_id)
    |> up_to(bound)
    |> repo().update_all([set: [guest: true]], timeout: :infinity)

    if bound, do: backfill(bound)
  end

  defp after_id(query, nil), do: query
  defp after_id(query, id), do: from(r in query, where: r.id > ^id)

  defp up_to(query, nil), do: query
  defp up_to(query, id), do: from(r in query, where: r.id <= ^id)

  defp anonymous_users do
    Enum.reduce(@identity, from(u in "users", select: u.id), fn column, query ->
      from(u in query, where: is_nil(field(u, ^column)))
    end)
  end

  # Set before the row is written, so an upsert's conflict check and its
  # `excluded` row see it too (the row it updates keeps its own).
  defp postgres_triggers do
    execute("""
    CREATE OR REPLACE FUNCTION leaderboard_records_guest() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      NEW.guest := NEW.user_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM users WHERE users.id = NEW.user_id AND #{anonymous("users")}
      );
      RETURN NEW;
    END
    $$
    """)

    execute("""
    CREATE OR REPLACE TRIGGER leaderboard_records_guest
    BEFORE INSERT OR UPDATE OF user_id ON leaderboard_records
    FOR EACH ROW EXECUTE FUNCTION leaderboard_records_guest()
    """)

    execute("""
    CREATE OR REPLACE FUNCTION users_leaderboard_guest() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      UPDATE leaderboard_records SET guest = (#{anonymous("NEW")})
      WHERE user_id = NEW.id AND guest IS DISTINCT FROM (#{anonymous("NEW")});
      RETURN NULL;
    END
    $$
    """)

    execute("""
    CREATE OR REPLACE TRIGGER users_leaderboard_guest
    AFTER UPDATE OF #{Enum.join(@identity, ", ")} ON users
    FOR EACH ROW
    WHEN ((#{anonymous("OLD")}) IS DISTINCT FROM (#{anonymous("NEW")}))
    EXECUTE FUNCTION users_leaderboard_guest()
    """)
  end

  # SQLite's triggers cannot change NEW, so the inserted row is updated
  # after it lands.
  defp sqlite_triggers do
    execute("""
    CREATE TRIGGER IF NOT EXISTS leaderboard_records_guest
    AFTER INSERT ON leaderboard_records
    FOR EACH ROW WHEN NEW.user_id IS NOT NULL
    BEGIN
      UPDATE leaderboard_records SET guest = EXISTS (
        SELECT 1 FROM users WHERE users.id = NEW.user_id AND #{anonymous("users")}
      )
      WHERE id = NEW.id;
    END
    """)

    execute("""
    CREATE TRIGGER IF NOT EXISTS users_leaderboard_guest
    AFTER UPDATE OF #{Enum.join(@identity, ", ")} ON users
    FOR EACH ROW WHEN (#{anonymous("OLD")}) IS NOT (#{anonymous("NEW")})
    BEGIN
      UPDATE leaderboard_records SET guest = (#{anonymous("NEW")}) WHERE user_id = NEW.id;
    END
    """)
  end

  defp anonymous(row), do: Enum.map_join(@identity, " AND ", &"#{row}.#{&1} IS NULL")
end
