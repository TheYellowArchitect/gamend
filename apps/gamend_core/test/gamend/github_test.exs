defmodule Gamend.GitHubTest do
  @moduledoc """
  The App's credentials, the installations a user may use, and what its
  webhook means.

  GitHub is a stub throughout: what is worth knowing is which question is
  asked, with which token, and what is written down from the answer, not
  whether GitHub is up.
  """
  use Gamend.DataCase, async: false

  import Gamend.AccountsFixtures
  import Gamend.GitHubStub

  alias Gamend.GitHub
  alias Gamend.GitHub.API
  alias Gamend.GitHub.Manifest

  @redirect "http://localhost:4000/github/callback"

  setup do
    configure()
    start_token_cache()
  end

  describe "app_jwt/0" do
    test "is an RS256 JWT issued by the App with a short life" do
      {:ok, jwt} = GitHub.app_jwt()

      assert {true, %JOSE.JWT{fields: claims}, %JOSE.JWS{alg: {_, :RS256}}} =
               JOSE.JWT.verify(JOSE.JWK.from_pem(private_key()), jwt)

      assert claims["iss"] == "4242"
      assert claims["exp"] - claims["iat"] == 600
      assert claims["iat"] <= System.system_time(:second)
    end

    test "reads a key whose newlines were escaped in an env file" do
      escaped = String.replace(private_key(), "\n", "\\n")

      assert {:ok, jwt} = API.app_jwt("4242", escaped)
      assert is_binary(jwt)
    end

    # A key that cannot sign is the operator's to fix, and the job that
    # needed a token has to end rather than raise and stay running.
    test "answers an error for a key that is not an RSA private key in PEM" do
      truncated = "-----BEGIN RSA PRIVATE KEY-----\nabc\n-----END RSA PRIVATE KEY-----\n"

      for pem <- ["", "not a key", truncated, nil] do
        assert API.app_jwt("4242", pem) == {:error, :invalid_private_key}
      end
    end
  end

  describe "configured?/0" do
    test "needs the App's three settings and the client pair" do
      assert GitHub.configured?()

      configure(private_key: nil)
      refute GitHub.configured?()
    end
  end

  describe "installation_token/1" do
    test "mints a token for the installation with the App JWT" do
      test = self()

      stub(%{
        {"POST", "/app/installations/9001/access_tokens"} => fn conn ->
          send(test, {:auth, Plug.Conn.get_req_header(conn, "authorization")})

          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"token" => "ghs_abc", "expires_at" => "2999-01-01T00:00:00Z"})
        end
      })

      assert {:ok, "ghs_abc"} = GitHub.installation_token(9001)
      assert_received {:auth, ["Bearer " <> jwt]}
      assert {true, _, _} = JOSE.JWT.verify(JOSE.JWK.from_pem(private_key()), jwt)
    end

    test "answers GitHub's refusal as an error" do
      stub(%{
        {"POST", "/app/installations/9001/access_tokens"} => {404, %{"message" => "Not Found"}}
      })

      assert {:error, {:http, 404}} = GitHub.installation_token(9001)
    end

    test "answers a configured key that cannot sign as an error, without asking GitHub" do
      configure(private_key: "not a key")
      stub(%{})

      assert {:error, :invalid_private_key} = GitHub.installation_token(9001)
      assert {:error, :invalid_private_key} = GitHub.git_env(9001)
    end

    # Jobs for one installation run in parallel and each would otherwise mint one.
    test "reuses a token until it is about to expire" do
      counter = :counters.new(1, [])

      stub(%{
        {"POST", "/app/installations/9001/access_tokens"} => fn conn ->
          :counters.add(counter, 1, 1)

          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"token" => "ghs_once", "expires_at" => "2999-01-01T00:00:00Z"})
        end
      })

      assert {:ok, "ghs_once"} = GitHub.installation_token(9001)
      assert {:ok, "ghs_once"} = GitHub.installation_token(9001)
      assert :counters.get(counter, 1) == 1

      GitHub.forget_installation_token(9001)

      assert {:ok, "ghs_once"} = GitHub.installation_token(9001)
      assert :counters.get(counter, 1) == 2
    end

    test "does not cache a token that is already about to expire" do
      counter = :counters.new(1, [])

      stub(%{
        {"POST", "/app/installations/9001/access_tokens"} => fn conn ->
          :counters.add(counter, 1, 1)
          soon = DateTime.utc_now() |> DateTime.add(60, :second) |> DateTime.to_iso8601()

          conn
          |> Plug.Conn.put_status(201)
          |> Req.Test.json(%{"token" => "ghs_brief", "expires_at" => soon})
        end
      })

      assert {:ok, "ghs_brief"} = GitHub.installation_token(9001)
      assert {:ok, "ghs_brief"} = GitHub.installation_token(9001)
      assert :counters.get(counter, 1) == 2
    end
  end

  describe "git_env/1" do
    test "is empty without an installation" do
      assert {:ok, []} = GitHub.git_env(nil)
    end

    # The token has to reach git and nothing else: not the argv, not the URL
    # that lands in the clone's `.git/config`, not a log line.
    test "hands the token to git as an extra header for github.com, never in the URL" do
      stub(%{{"POST", "/app/installations/9001/access_tokens"} => token_json("ghs_secret")})

      assert {:ok, env} = GitHub.git_env(9001)

      assert {"GIT_TERMINAL_PROMPT", "0"} in env
      assert {"GIT_CONFIG_KEY_0", "http.https://github.com/.extraheader"} in env

      {_, value} = List.keyfind(env, "GIT_CONFIG_VALUE_0", 0)
      assert value == "AUTHORIZATION: basic " <> Base.encode64("x-access-token:ghs_secret")
    end
  end

  describe "link_installations/3" do
    test "records what GitHub says the user may see, and drops what it no longer does" do
      user = user_fixture()
      installation_fixture(user, %{installation_id: 1, account_login: "gone"})
      test = self()

      stub(%{
        {"POST", "/login/oauth/access_token"} => fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          send(test, {:exchange, URI.decode_query(body)})
          Req.Test.json(conn, %{"access_token" => "gho_user"})
        end,
        {"GET", "/user/installations"} => fn conn ->
          assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer gho_user"]

          Req.Test.json(conn, %{
            "installations" => [installation_json(9001), installation_json(9002, "dragos")]
          })
        end
      })

      assert {:ok, rows} = GitHub.link_installations(user, "the-code", @redirect)

      assert_received {:exchange, %{"code" => "the-code", "redirect_uri" => @redirect}}
      assert Enum.map(rows, & &1.installation_id) == [9001, 9002]
      assert Enum.map(rows, & &1.account_login) == ["appsinacup", "dragos"]
      assert GitHub.get_installation(user, 1) == nil
    end

    test "a second connect refreshes rather than duplicates" do
      user = user_fixture()

      stub(%{
        {"POST", "/login/oauth/access_token"} => %{"access_token" => "gho_user"},
        {"GET", "/user/installations"} => %{"installations" => [installation_json(9001)]}
      })

      assert {:ok, _} = GitHub.link_installations(user, "one", @redirect)
      assert {:ok, _} = GitHub.link_installations(user, "two", @redirect)

      assert GitHub.count_installations(user.id) == 1
    end

    test "one user's connect does not touch another's rows" do
      other = user_fixture()
      installation_fixture(other, %{installation_id: 5555})

      user = user_fixture()

      stub(%{
        {"POST", "/login/oauth/access_token"} => %{"access_token" => "gho_user"},
        {"GET", "/user/installations"} => %{"installations" => []}
      })

      assert {:ok, []} = GitHub.link_installations(user, "code", @redirect)
      assert GitHub.get_installation(other, 5555)
    end

    # GitHub answers a bad code with 200 and an error body.
    test "a code GitHub will not vouch for is an error" do
      user = user_fixture()

      stub(%{{"POST", "/login/oauth/access_token"} => %{"error" => "bad_verification_code"}})

      assert {:error, {:oauth, "bad_verification_code"}} =
               GitHub.link_installations(user, "x", @redirect)
    end
  end

  describe "repositories/2 and repository/3" do
    test "list an installation the user connected, through its token" do
      user = user_fixture()
      installation_fixture(user, %{installation_id: 9001})

      stub(%{
        {"POST", "/app/installations/9001/access_tokens"} => token_json("ghs_inst"),
        {"GET", "/installation/repositories"} => fn conn ->
          assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer ghs_inst"]

          Req.Test.json(conn, %{
            "repositories" => [
              repository_json(1, "appsinacup/gamend_starter"),
              repository_json(2, "appsinacup/other")
            ]
          })
        end
      })

      assert {:ok, [repo, _]} = GitHub.repositories(user, 9001)
      assert repo.full_name == "appsinacup/gamend_starter"
      assert repo.clone_url == "https://github.com/appsinacup/gamend_starter.git"
      assert repo.default_branch == "main"
      assert repo.private

      assert {:ok, %{id: 2}} = GitHub.repository(user, 9001, 2)
      assert {:error, :not_found} = GitHub.repository(user, 9001, 3)
    end

    # The whole point of the installations table: an id typed into a form is
    # not a grant.
    test "refuse an installation the user has not connected" do
      user = user_fixture()

      assert {:error, :not_linked} = GitHub.repositories(user, 9001)
      assert {:error, :not_linked} = GitHub.repository(user, 9001, 1)
    end
  end

  describe "list_all_installations/1" do
    test "carries who connected each, and the host's count when it keeps one" do
      user = user_fixture()
      installation_fixture(user, %{installation_id: 9001})

      assert [%{user: %{id: id}, uses: nil}] = GitHub.list_all_installations()
      assert id == user.id

      Application.put_env(:gamend_core, :github_usage, {__MODULE__, :usage})
      on_exit(fn -> Application.delete_env(:gamend_core, :github_usage) end)

      assert [%{uses: 3}] = GitHub.list_all_installations()
      assert GitHub.count_all_installations() == 1
    end
  end

  @doc false
  def usage, do: %{9001 => 3}

  describe "verify_webhook/2" do
    setup do
      configure(webhook_secret: "hook-secret")
    end

    test "accepts a signature over the raw body" do
      body = ~s({"zen":"hi"})
      hex = hmac("hook-secret", body)

      assert :ok = GitHub.verify_webhook(body, "sha256=" <> hex)
      assert :ok = GitHub.verify_webhook(body, "sha256=" <> String.upcase(hex))
    end

    test "refuses another body, another secret, or none" do
      body = ~s({"zen":"hi"})

      assert {:error, :bad_signature} =
               GitHub.verify_webhook(body <> " ", "sha256=" <> hmac("hook-secret", body))

      assert {:error, :bad_signature} =
               GitHub.verify_webhook(body, "sha256=" <> hmac("other", body))

      assert {:error, :bad_signature} = GitHub.verify_webhook(body, "sha1=abc")
      assert {:error, :missing_signature} = GitHub.verify_webhook(body, nil)
    end

    test "refuses everything while no secret is set" do
      configure(webhook_secret: nil)
      body = "{}"

      assert {:error, :not_configured} =
               GitHub.verify_webhook(body, "sha256=" <> hmac("", body))
    end
  end

  describe "push_event/1" do
    test "reads the branch, the commit and the repository" do
      payload = %{
        "ref" => "refs/heads/main",
        "after" => "abc123",
        "repository" => %{
          "id" => 7,
          "clone_url" => "https://github.com/a/b.git",
          "html_url" => "https://github.com/a/b"
        }
      }

      assert {:ok,
              %{
                ref: "main",
                branch: "main",
                sha: "abc123",
                repo_id: 7,
                repo_urls: ["https://github.com/a/b.git", "https://github.com/a/b"]
              }} = GitHub.push_event(payload)
    end

    test "a tag is not a branch, and a delete is nothing" do
      assert {:ok, %{ref: "v1", branch: nil}} =
               GitHub.push_event(%{"ref" => "refs/tags/v1", "after" => "abc"})

      assert {:error, :deleted} = GitHub.push_event(%{"deleted" => true})

      assert {:error, :no_commit} =
               GitHub.push_event(%{"ref" => "refs/heads/x", "after" => String.duplicate("0", 40)})

      assert {:error, :unsupported} = GitHub.push_event(%{})
    end
  end

  describe "installation_event/2" do
    setup do
      user = user_fixture()
      installation_fixture(user, %{installation_id: 9001})
      {:ok, user: user}
    end

    test "an uninstall forgets every row for it and tells the host", %{user: user} do
      other = user_fixture()
      installation_fixture(other, %{installation_id: 9001})

      assert {:deleted, 9001} =
               GitHub.installation_event("installation", %{
                 "action" => "deleted",
                 "installation" => %{"id" => 9001}
               })

      assert GitHub.get_installation(user, 9001) == nil
      assert GitHub.get_installation(other, 9001) == nil
    end

    test "a suspension is recorded, and lifted", %{user: user} do
      assert :ok =
               GitHub.installation_event("installation", %{
                 "action" => "suspend",
                 "installation" => %{"id" => 9001}
               })

      assert %{suspended_at: %DateTime{}} = GitHub.get_installation(user, 9001)

      assert :ok =
               GitHub.installation_event("installation", %{
                 "action" => "unsuspend",
                 "installation" => %{"id" => 9001}
               })

      assert %{suspended_at: nil} = GitHub.get_installation(user, 9001)
    end

    test "removed repositories are the host's to unbind", %{user: user} do
      assert {:repositories_removed, 9001, [1, 2]} =
               GitHub.installation_event("installation_repositories", %{
                 "action" => "removed",
                 "installation" => %{"id" => 9001},
                 "repositories_removed" => [%{"id" => 1}, %{"id" => 2}]
               })

      assert GitHub.get_installation(user, 9001)
    end

    test "anything else is nothing" do
      assert :ok = GitHub.installation_event("push", %{"ref" => "refs/heads/main"})
      assert :ok = GitHub.installation_event(nil, %{})

      assert :ok =
               GitHub.installation_event("installation_repositories", %{"action" => "added"})
    end
  end

  describe "Manifest" do
    test "builds every URL from the host, and the floor of permissions" do
      manifest =
        Manifest.build("https://example.org/", redirect_url: "http://localhost:4777/callback")

      assert manifest["name"] == "Gamend"
      assert manifest["url"] == "https://example.org"

      assert manifest["callback_urls"] == [
               "https://example.org/auth/github/callback",
               "https://example.org/github/callback"
             ]

      assert manifest["setup_url"] == "https://example.org/github/setup"
      assert manifest["redirect_url"] == "http://localhost:4777/callback"

      assert manifest["default_permissions"] == %{
               "contents" => "read",
               "metadata" => "read",
               "emails" => "read"
             }

      refute Map.has_key?(manifest, "hook_attributes")
      refute Map.has_key?(manifest, "default_events")
    end

    test "takes the host's name, webhook and permissions" do
      Application.put_env(:gamend_core, Manifest,
        name: "Gamend Cloud",
        webhook_path: "/cloud/hooks/github",
        permissions: %{"checks" => "write"}
      )

      on_exit(fn -> Application.delete_env(:gamend_core, Manifest) end)

      manifest = Manifest.build("https://gamend.org", redirect_url: "http://localhost/callback")

      assert manifest["name"] == "Gamend Cloud"
      assert manifest["hook_attributes"]["url"] == "https://gamend.org/cloud/hooks/github"
      assert manifest["default_events"] == ["push"]
      assert manifest["default_permissions"]["checks"] == "write"
      assert manifest["default_permissions"]["contents"] == "read"
      assert "https://gamend.org/cloud/hooks/github" in Manifest.urls(manifest)
    end

    test "the form posts to the account or to an organisation" do
      assert Manifest.form_action(nil, "s t") ==
               "https://github.com/settings/apps/new?state=s+t"

      assert Manifest.form_action("appsinacup", "s") ==
               "https://github.com/organizations/appsinacup/settings/apps/new?state=s"
    end

    test "converts a code into the App's settings" do
      stub(%{
        {"POST", "/app-manifests/the-code/conversions"} =>
          {201,
           %{
             "id" => 123,
             "slug" => "gamend-cloud",
             "client_id" => "Iv1.x",
             "client_secret" => "cs",
             "webhook_secret" => "ws",
             "pem" => "-----BEGIN RSA PRIVATE KEY-----\nabc\n-----END RSA PRIVATE KEY-----\n",
             "html_url" => "https://github.com/apps/gamend-cloud"
           }}
      })

      assert {:ok, app} = Manifest.convert("the-code")
      assert app.app_id == "123"

      assert Manifest.env_lines(app) == [
               "GAMEND_OAUTH_GITHUB_CLIENT_ID=Iv1.x",
               "GAMEND_OAUTH_GITHUB_CLIENT_SECRET=cs",
               "GAMEND_GITHUB_APP_ID=123",
               "GAMEND_GITHUB_APP_SLUG=gamend-cloud",
               ~s(GAMEND_GITHUB_PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----\\nabc\\n-----END RSA PRIVATE KEY-----"),
               "GAMEND_GITHUB_WEBHOOK_SECRET=ws"
             ]

      refute Enum.any?(Manifest.env_lines(%{app | webhook_secret: nil}), &(&1 =~ "WEBHOOK"))
    end
  end

  defp hmac(secret, body),
    do: :hmac |> :crypto.mac(:sha256, secret, body) |> Base.encode16(case: :lower)
end
