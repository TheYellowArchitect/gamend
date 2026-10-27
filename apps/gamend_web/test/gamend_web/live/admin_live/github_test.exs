defmodule GamendWeb.AdminLive.GitHubTest do
  @moduledoc """
  The operator's view of GitHub installations: every user's, with what a
  customer's own page cannot show, what GitHub suspended and what nothing
  uses.
  """
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Gamend.GitHubStub, only: [installation_fixture: 2]

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Repo

  setup %{conn: conn} do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    {:ok, conn: log_in_user(conn, admin)}
  end

  test "lists installations across users", %{conn: conn} do
    alice = AccountsFixtures.user_fixture()
    bob = AccountsFixtures.user_fixture()
    installation_fixture(alice, %{installation_id: 9001, account_login: "appsinacup"})
    installation_fixture(bob, %{installation_id: 9002, account_login: "someone-else"})

    {:ok, _view, html} = live(conn, ~p"/admin/github")

    assert html =~ "appsinacup"
    assert html =~ "someone-else"
    assert html =~ "9001"
    assert html =~ alice.email
    assert html =~ "2 installations"
    refute html =~ "In use"
    assert html =~ "not configured"
  end

  test "counts what the host binds to each, when it counts", %{conn: conn} do
    installation_fixture(AccountsFixtures.user_fixture(), %{installation_id: 9001})
    Application.put_env(:gamend_core, :github_usage, {__MODULE__, :usage})
    on_exit(fn -> Application.delete_env(:gamend_core, :github_usage) end)

    {:ok, view, _html} = live(conn, ~p"/admin/github")

    assert render(view) =~ "In use"
    assert view |> element("#installations tr td .badge") |> render() =~ "4"
  end

  @doc false
  def usage, do: %{9001 => 4}

  test "says so when nobody has connected one", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/github")

    assert html =~ "Nobody has connected a GitHub installation yet"
  end

  test "marks a suspended installation", %{conn: conn} do
    installation_fixture(AccountsFixtures.user_fixture(), %{
      installation_id: 9003,
      account_login: "paused-org",
      suspended_at: DateTime.utc_now()
    })

    {:ok, _view, html} = live(conn, ~p"/admin/github")

    assert html =~ "paused-org"
    assert html =~ "suspended"
  end
end
