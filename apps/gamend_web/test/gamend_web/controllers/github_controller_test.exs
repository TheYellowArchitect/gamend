defmodule GamendWeb.GitHubControllerTest do
  @moduledoc """
  The connect round-trip: out to GitHub with a state, back with a code, and
  the one question asked with it.
  """
  use GamendWeb.ConnCase, async: false

  import Gamend.AccountsFixtures
  import Gamend.GitHubStub

  alias Gamend.GitHub
  alias Gamend.OAuthSessions

  setup %{conn: conn} do
    configure()
    user = user_fixture()
    {:ok, conn: log_in_user(conn, user), user: user}
  end

  describe "GET /github/connect" do
    test "sends the user to GitHub with a state that is theirs", %{conn: conn, user: user} do
      conn = get(conn, ~p"/github/connect")

      assert redirected_to(conn) =~ "https://github.com/login/oauth/authorize?"

      %{"state" => state, "client_id" => client_id, "redirect_uri" => redirect_uri} = query(conn)

      assert client_id == "Iv1.client"
      assert redirect_uri =~ "/github/callback"

      assert %{data: %{"user_id" => user_id}} =
               OAuthSessions.get_pending_session(state, "github_app")

      assert user_id == user.id
    end

    test "keeps a same-site return path and drops anything else", %{conn: conn} do
      kept = get(conn, ~p"/github/connect?return_to=/servers/new")

      assert %{data: %{"return_to" => "/servers/new"}} =
               OAuthSessions.get_pending_session(query(kept)["state"], "github_app")

      for evil <- ["https://evil.example/", "//evil.example/"] do
        dropped = get(conn, ~p"/github/connect?return_to=#{evil}")

        assert %{data: %{"return_to" => nil}} =
                 OAuthSessions.get_pending_session(query(dropped)["state"], "github_app")
      end
    end

    test "requires a signed-in user" do
      conn = get(build_conn(), ~p"/github/connect")

      assert redirected_to(conn) =~ "/users/log_in"
    end

    test "says so when the App is not configured, back where it was asked", %{conn: conn} do
      configure(app_id: nil)

      conn = get(conn, ~p"/github/connect?return_to=/servers")

      assert redirected_to(conn) == "/servers"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "not set up"
    end
  end

  describe "GET /github/callback" do
    test "links the installations GitHub lists and lands where asked", %{
      conn: conn,
      user: user
    } do
      stub(%{
        {"POST", "/login/oauth/access_token"} => %{"access_token" => "gho_user"},
        {"GET", "/user/installations"} => %{"installations" => [installation_json(9001)]}
      })

      state = start(conn, "/servers/new")

      conn = get(conn, ~p"/github/callback?code=abc&state=#{state}")

      assert redirected_to(conn) == "/servers/new"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "1 installation"
      assert GitHub.get_installation(user, 9001)
    end

    test "lands on the host's page when none was asked", %{conn: conn} do
      Application.put_env(:gamend_web, :github_return_to, "/projects")
      on_exit(fn -> Application.delete_env(:gamend_web, :github_return_to) end)

      stub(%{
        {"POST", "/login/oauth/access_token"} => %{"access_token" => "gho_user"},
        {"GET", "/user/installations"} => %{"installations" => []}
      })

      conn = get(conn, ~p"/github/callback?code=abc&state=#{start(conn)}")

      assert redirected_to(conn) == "/projects"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "not installed anywhere"
    end

    test "a state is redeemed once", %{conn: conn} do
      stub(%{
        {"POST", "/login/oauth/access_token"} => %{"access_token" => "gho_user"},
        {"GET", "/user/installations"} => %{"installations" => []}
      })

      state = start(conn)

      assert conn |> get(~p"/github/callback?code=abc&state=#{state}") |> redirected_to()

      replay = get(conn, ~p"/github/callback?code=abc&state=#{state}")

      assert Phoenix.Flash.get(replay.assigns.flash, :error) =~ "expired"
    end

    # A state minted in one browser session and redeemed in another would
    # hand the second account the first one's installations.
    test "a state issued to another user is refused", %{conn: conn, user: user} do
      other = user_fixture()
      state = start(log_in_user(build_conn(), other))

      stub(%{{"POST", "/login/oauth/access_token"} => %{"access_token" => "gho_user"}})

      conn = get(conn, ~p"/github/callback?code=abc&state=#{state}")

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expired"
      assert GitHub.list_installations(user.id) == []
    end

    test "a refusal from GitHub carries no code and is reported", %{conn: conn} do
      conn = get(conn, ~p"/github/callback?error=access_denied&state=whatever")

      assert redirected_to(conn) == "/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "did not complete"
    end

    test "a code GitHub rejects is reported without linking anything", %{
      conn: conn,
      user: user
    } do
      stub(%{{"POST", "/login/oauth/access_token"} => %{"error" => "bad_verification_code"}})

      conn = get(conn, ~p"/github/callback?code=abc&state=#{start(conn)}")

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "did not accept"
      assert GitHub.list_installations(user.id) == []
    end
  end

  describe "GET /github/setup" do
    # GitHub's `installation_id` and `setup_action` are ignored on purpose:
    # what the person may see is re-asked, not taken from the URL.
    test "goes round the connect flow", %{conn: conn} do
      conn = get(conn, ~p"/github/setup?installation_id=9001&setup_action=install")

      assert redirected_to(conn) == "/github/connect"
    end
  end

  defp query(conn) do
    conn |> redirected_to() |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
  end

  # Begin a connect on `conn` and answer the state GitHub would carry back.
  defp start(conn, return_to \\ nil) do
    path = if return_to, do: "/github/connect?return_to=#{return_to}", else: "/github/connect"
    conn |> get(path) |> query() |> Map.fetch!("state")
  end
end
