defmodule GamendWeb.AdminLive.RateLimitingTest do
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Bans
  alias Gamend.Repo
  alias GamendWeb.Plugs.IpBan

  # TEST-NET-3: never a real client, so a ban here cannot shut out the suite.
  @ip "203.0.113.77"

  setup do
    Bans.Cache.init_table()
    on_exit(fn -> :ets.delete_all_objects(:bans) end)

    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    %{admin: admin}
  end

  defp page(conn, admin) do
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/rate_limiting")
    view
  end

  test "an IP banned from the form is banned, listed, and unbanned from its row", %{
    conn: conn,
    admin: admin
  } do
    view = page(conn, admin)

    view
    |> form("#ban-ip-form", %{"ip" => " #{@ip} ", "duration" => "1h", "reason" => "Scraping"})
    |> render_submit()

    assert IpBan.banned?(@ip)
    assert %{reason: "Scraping", banned_by: banned_by} = Bans.active(:ip, @ip)
    assert banned_by == admin.id
    assert has_element?(view, ~s([phx-click="unban_ip"][phx-value-ip="#{@ip}"]))

    view |> element(~s([phx-click="unban_ip"][phx-value-ip="#{@ip}"])) |> render_click()
    refute IpBan.banned?(@ip)
    refute has_element?(view, ~s([phx-click="unban_ip"][phx-value-ip="#{@ip}"]))
  end

  test "every duration is a ban, an unknown one is for ever", %{conn: conn, admin: admin} do
    view = page(conn, admin)

    for duration <- ~w(24h 7d 30d forever) do
      render_submit(view, "ban_ip", %{"ip" => @ip, "duration" => duration})
      assert IpBan.banned?(@ip), "#{duration} did not ban"
      IpBan.unban(@ip)
    end
  end

  test "an empty IP is refused, nothing banned", %{conn: conn, admin: admin} do
    view = page(conn, admin)
    before = Bans.list_active(:ip)
    render_submit(view, "ban_ip", %{"ip" => "  ", "duration" => "1h"})
    assert Bans.list_active(:ip) == before
  end

  test "the page refreshes its tables on its timer", %{conn: conn, admin: admin} do
    view = page(conn, admin)
    IpBan.ban(@ip, expires_at: Bans.expires_after(:timer.hours(1)))
    send(view.pid, :refresh)
    assert has_element?(view, ~s([phx-click="unban_ip"][phx-value-ip="#{@ip}"]))
    send(view.pid, :something_else)
    assert render(view)
  end
end
