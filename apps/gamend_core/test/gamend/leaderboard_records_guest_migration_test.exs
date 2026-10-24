defmodule Gamend.LeaderboardRecordsGuestMigrationTest do
  use Gamend.DataCase, async: false

  alias Gamend.Accounts
  alias Gamend.Leaderboards
  alias Gamend.Leaderboards.Record

  @backfill Gamend.Repo.Migrations.LeaderboardRecordsGuest
  @repair Gamend.Repo.Migrations.LeaderboardRecordsGuestBoolean

  # The test run migrated the database already, so the modules are usually in
  # memory; requiring a file again would redefine its module.
  setup_all do
    for {module, file} <- [
          {@backfill, "20261019160000_leaderboard_records_guest.exs"},
          {@repair, "20261024120000_leaderboard_records_guest_boolean.exs"}
        ],
        not Code.ensure_loaded?(module) do
      Code.require_file("priv/repo/migrations/" <> file)
    end

    # Handed to the tests rather than called as `@backfill.backfill/1`: the
    # modules are loaded from their files at runtime, so the compiler cannot
    # see them.
    %{backfill: @backfill, repair: @repair}
  end

  setup do
    {:ok, guest} =
      Accounts.find_or_create_from_device("device-#{System.unique_integer([:positive])}")

    {:ok, lb} = Leaderboards.create_leaderboard(%{slug: "guest_flag", title: "Guests"})
    {:ok, _} = Leaderboards.submit_score(lb.id, guest.id, 100, %{})
    {:ok, record} = Leaderboards.get_user_record(lb.id, guest.id)

    %{record: record}
  end

  test "the backfill flags a guest's record as a boolean", %{backfill: backfill, record: record} do
    # The record as the migration found it: the column added, at its default.
    Repo.update_all(from(r in Record, where: r.id == ^record.id), set: [guest: false])

    backfill.backfill(Repo)

    assert_guest(record)
  end

  @tag :sqlite_only
  test "the repair makes SQLite's text 'true' a boolean", %{repair: repair, record: record} do
    Repo.query!("UPDATE leaderboard_records SET guest = 'true' WHERE id = ?", [record.id])
    assert_raise ArgumentError, fn -> Repo.get!(Record, record.id) end

    repair.repair(Repo)

    assert_guest(record)
  end

  defp assert_guest(record) do
    assert Repo.get!(Record, record.id).guest == true
    assert Repo.exists?(from(r in Record, where: r.id == ^record.id and r.guest == true))
    refute Repo.exists?(from(r in Record, where: r.id == ^record.id and r.guest == false))
  end
end
