defmodule Gamend.GitHubStub do
  @moduledoc """
  A fake api.github.com for the tests, and the settings that point at it.

  Every request the App makes lands on `Req.Test` with `Gamend.GitHub` as the
  stub name (`config/test.exs`), so a test says what GitHub would answer and
  nothing reaches the network. The private key is generated once per test
  run: a checked-in key would be a key somebody could copy, even a test one.
  """

  alias Gamend.Accounts.User
  alias Gamend.GitHub.Installation
  alias Gamend.Repo

  @doc "A PEM the App can sign with, made once per run."
  def private_key do
    case :persistent_term.get({__MODULE__, :pem}, nil) do
      nil ->
        {_, pem} = {:rsa, 2048} |> JOSE.JWK.generate_key() |> JOSE.JWK.to_pem()
        :persistent_term.put({__MODULE__, :pem}, pem)
        pem

      pem ->
        pem
    end
  end

  @doc """
  Configure the App and its client pair for the rest of the test, and restore
  whatever was there on exit.
  """
  def configure(attrs \\ []) do
    app = Application.get_env(:gamend_core, Gamend.GitHub, [])
    oauth = Application.get_env(:gamend_core, Gamend.OAuth.Providers, [])

    Application.put_env(
      :gamend_core,
      Gamend.GitHub,
      app
      |> Keyword.merge(app_id: "4242", app_slug: "gamend-test", private_key: private_key())
      |> Keyword.merge(attrs)
    )

    Application.put_env(
      :gamend_core,
      Gamend.OAuth.Providers,
      Keyword.merge(oauth, github_client_id: "Iv1.client", github_client_secret: "shh")
    )

    ExUnit.Callbacks.on_exit(fn ->
      Application.put_env(:gamend_core, Gamend.GitHub, app)
      Application.put_env(:gamend_core, Gamend.OAuth.Providers, oauth)
    end)

    :ok
  end

  @doc """
  A token cache of the test's own. The app cache is bypassed under test, and
  a test of the token's caching needs a real one, fresh, without whatever an
  earlier test minted.
  """
  def start_token_cache do
    name = :"github_cache_#{System.unique_integer([:positive])}"

    ExUnit.Callbacks.start_supervised!(
      {Gamend.Cache,
       name: name,
       bypass_mode: false,
       inclusion_policy: :inclusive,
       levels: [{Gamend.Cache.L1, [name: :"#{name}_l1"]}]}
    )

    _ = Gamend.Cache.put_dynamic_cache(name)
    :ok
  end

  @doc """
  Answer GitHub's routes from a map of `{method, path} => response`, where a
  response is a body (JSON-encoded at 200), `{status, body}`, or a function
  of the conn. Unknown routes answer 404 with the path, which is what a wrong
  URL in the client should look like.
  """
  def stub(routes) when is_map(routes) do
    Req.Test.stub(Gamend.GitHub, fn conn ->
      key = {conn.method, conn.request_path}

      case Map.get(routes, key) do
        nil ->
          conn
          |> Plug.Conn.put_status(404)
          |> Req.Test.json(%{"message" => "no stub for #{inspect(key)}"})

        fun when is_function(fun, 1) ->
          fun.(conn)

        {status, body} ->
          conn |> Plug.Conn.put_status(status) |> Req.Test.json(body)

        body ->
          Req.Test.json(conn, body)
      end
    end)
  end

  @doc "An installation row for `user`, as `Gamend.GitHub.link_installations/3` would write it."
  def installation_fixture(%User{} = user, attrs \\ %{}) do
    %Installation{user_id: user.id}
    |> Installation.changeset(
      Map.merge(
        %{
          installation_id: 9001,
          account_login: "appsinacup",
          account_id: 77,
          account_type: "Organization",
          repository_selection: "selected"
        },
        attrs
      )
    )
    |> Repo.insert!()
  end

  @doc "What `GET /user/installations` answers for one installation."
  def installation_json(id, login \\ "appsinacup") do
    %{
      "id" => id,
      "account" => %{"login" => login, "id" => 77, "type" => "Organization"},
      "repository_selection" => "selected",
      "suspended_at" => nil
    }
  end

  @doc "What `GET /installation/repositories` answers for one repository."
  def repository_json(id, full_name) do
    %{
      "id" => id,
      "full_name" => full_name,
      "clone_url" => "https://github.com/#{full_name}.git",
      "html_url" => "https://github.com/#{full_name}",
      "default_branch" => "main",
      "private" => true
    }
  end

  @doc "A minted installation token, for the `access_tokens` route."
  def token_json(token), do: {201, %{"token" => token, "expires_at" => "2999-01-01T00:00:00Z"}}
end
