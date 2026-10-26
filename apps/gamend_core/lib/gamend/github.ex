defmodule Gamend.GitHub do
  @moduledoc """
  The server's GitHub App: who may use which installation, the credentials a
  job borrows from it, and what its webhook means.

  For a host that works on its customers' repositories: Forge builds them,
  Gamend Cloud builds a server from one. Core keeps what every such host
  needs (the App's settings, its tokens, the installations a user connected,
  the connect flow at `/github/*`, `/admin/github`, `mix gamend.github.app`);
  the host keeps what it binds to a repository (a project, a server) and the
  webhook route that acts on it.

  ## Two credentials, two owners

  The App's OAuth client id and secret are its identity to a *person*:
  `Gamend.OAuth.Providers` declares them as `github`, so "Log in with GitHub"
  is the same App, and the connect flow here reads the same pair. The App id,
  slug and private key are what mint installation tokens, and are declared on
  this module (`GAMEND_GITHUB_*`). Both are operator configuration; neither
  is a customer's, so neither lives in `Gamend.Secrets`.

  ## Who may use an installation

  GitHub decides. After the App is installed, `GET /user/installations` with
  the person's own token lists the installations that person may see, and
  those rows, only those, become theirs in `github_installations`. Trusting
  the `installation_id` GitHub appends to the setup redirect would let anyone
  type a number into a URL and claim somebody else's organisation. A host
  that binds something to an installation checks `get_installation/2` first.

  ## Where the token goes

  Into `git`'s environment (`git_env/1`), and nowhere else. A clone URL
  carrying it is written to the clone's `.git/config`, which a build may
  read; a log that prints the repository URL never had it.

  ## The webhook

  The App has one webhook URL, the host's route. The host verifies a delivery
  with `verify_webhook/2` over the raw body, hands every verified one to
  `installation_event/2` (which keeps this module's rows in step and says
  what the host has to unbind), and reads a push with `push_event/1`.
  """

  use Gamend.Settings.Provider,
    app: :gamend_core,
    group: :github,
    label: "GitHub App"

  import Ecto.Query

  alias Gamend.GitHub.API
  alias Gamend.GitHub.Installation
  alias Gamend.Repo

  require Logger

  @app [:app_id, :app_slug, :private_key]

  setting(:app_id, :string,
    required: :warn,
    with: @app,
    doc: "The GitHub App's numeric id, from its settings page."
  )

  setting(:app_slug, :string,
    required: :warn,
    with: @app,
    doc: "The App's URL name, `github.com/apps/<slug>`. Where a customer is sent to install it."
  )

  setting(:private_key, :string,
    secret: true,
    required: :warn,
    with: @app,
    doc: "The App's private key, PEM. Signs the JWT that mints installation tokens."
  )

  setting(:webhook_secret, :string,
    secret: true,
    doc:
      "The secret the App signs its webhook deliveries with. Unset refuses every delivery, which is the safe default for an endpoint anyone can POST to."
  )

  @doc "Read one of this group's settings."
  @spec config(atom()) :: term()
  def config(key) when is_atom(key), do: Gamend.Settings.get(__MODULE__, key)

  @doc """
  Whether the App is set up end to end: its own three settings, and the
  client pair that the connect flow and the login button both use.
  """
  @spec configured?() :: boolean()
  def configured? do
    Enum.all?(@app, &present?(config(&1))) and present?(client_id()) and
      present?(client_secret())
  end

  defp present?(value), do: is_binary(value) and value != ""

  @doc "Where a customer installs the App on their account or organisation."
  @spec install_url() :: String.t()
  def install_url, do: "https://github.com/apps/#{config(:app_slug)}/installations/new"

  ## The App's tokens

  @doc """
  A fresh App JWT. Never cached: it is cheap and ten minutes long. Logged at
  error level when the configured key cannot sign one, since nothing that
  asked for it can work until the operator fixes the setting.
  """
  @spec app_jwt() :: {:ok, String.t()} | {:error, :invalid_private_key}
  def app_jwt do
    case API.app_jwt(config(:app_id), config(:private_key)) do
      {:ok, jwt} ->
        {:ok, jwt}

      {:error, reason} ->
        Logger.error("github: GAMEND_GITHUB_PRIVATE_KEY is not an RSA private key in PEM")
        {:error, reason}
    end
  end

  @doc """
  An installation token, cached until five minutes before GitHub expires it.

  Cached under `Gamend.Cache` rather than in the process: jobs for one
  installation run in parallel and each would otherwise mint its own, and
  GitHub counts those against the App.
  """
  @spec installation_token(integer()) :: {:ok, String.t()} | {:error, term()}
  def installation_token(installation_id) when is_integer(installation_id) do
    key = token_key(installation_id)

    # `fetch/1`, not `get!/1`: a cache that cannot answer is a miss, and a
    # fresh token costs one request, where a raise here failed the checkout.
    case Gamend.Cache.fetch(key) do
      {:ok, token} when is_binary(token) -> {:ok, token}
      _miss -> mint_installation_token(key, installation_id)
    end
  end

  defp mint_installation_token(key, installation_id) do
    with {:ok, jwt} <- app_jwt(),
         {:ok, %{token: token, expires_at: expires_at}} <-
           API.installation_token(jwt, installation_id) do
      ttl = DateTime.diff(expires_at, DateTime.utc_now(), :millisecond) - :timer.minutes(5)
      if ttl > 0, do: Gamend.Cache.put(key, token, ttl: ttl)
      {:ok, token}
    end
  end

  @doc """
  Drop a cached installation token. An uninstalled App's token is dead on
  GitHub's side already; this stops a job in flight from trying it.
  """
  @spec forget_installation_token(integer()) :: :ok
  def forget_installation_token(installation_id) when is_integer(installation_id) do
    Gamend.Cache.invalidate(token_key(installation_id))
  end

  defp token_key(installation_id), do: {:github, :installation_token, installation_id}

  @doc """
  The environment a `git` needs to clone through an installation.

  Empty for none. Otherwise the token rides in as an `http.extraheader` for
  github.com only: `git` reads it, nothing the clone writes holds it, and
  `ps` shows only the variable names. Prompting is switched off so a token
  GitHub refuses fails the clone rather than hanging the job.
  """
  @spec git_env(integer() | nil) :: {:ok, [{String.t(), String.t()}]} | {:error, term()}
  def git_env(nil), do: {:ok, []}

  def git_env(installation_id) when is_integer(installation_id) do
    with {:ok, token} <- installation_token(installation_id) do
      basic = Base.encode64("x-access-token:" <> token)

      {:ok,
       [
         {"GIT_TERMINAL_PROMPT", "0"},
         {"GIT_CONFIG_COUNT", "1"},
         {"GIT_CONFIG_KEY_0", "http.https://github.com/.extraheader"},
         {"GIT_CONFIG_VALUE_0", "AUTHORIZATION: basic " <> basic}
       ]}
    end
  end

  ## The connect flow

  @doc """
  Where to send a person so GitHub can tell us which installations are
  theirs. `state` is the OAuth session id the callback consumes;
  `redirect_uri` is the callback, registered on the App.
  """
  @spec authorize_url(String.t(), String.t()) :: String.t()
  def authorize_url(state, redirect_uri) do
    query = URI.encode_query(client_id: client_id(), redirect_uri: redirect_uri, state: state)
    "https://github.com/login/oauth/authorize?" <> query
  end

  @doc """
  Turn the code a person brought back into their installations.

  The user token is used for exactly one request and dropped: nothing here
  needs to act as the person later, and a token that is not stored cannot
  leak. What is kept is GitHub's answer, the installations, written as this
  user's. Ones GitHub no longer lists are removed, so revoking access on
  GitHub's side is enough to revoke it here.
  """
  @spec link_installations(Gamend.Accounts.User.t(), String.t(), String.t()) ::
          {:ok, [Installation.t()]} | {:error, term()}
  def link_installations(%{id: user_id}, code, redirect_uri) when is_binary(code) do
    with {:ok, token} <- API.exchange_code(code, client_id(), client_secret(), redirect_uri),
         {:ok, rows} <- API.user_installations(token) do
      {:ok, replace_installations(user_id, rows)}
    end
  end

  defp replace_installations(user_id, rows) do
    now = DateTime.utc_now()

    entries =
      rows
      |> Enum.filter(&is_integer(&1["id"]))
      |> Enum.map(fn row ->
        %{
          id: Gamend.UUIDv7.generate(),
          user_id: user_id,
          installation_id: row["id"],
          account_login: get_in(row, ["account", "login"]),
          account_id: get_in(row, ["account", "id"]),
          account_type: get_in(row, ["account", "type"]),
          repository_selection: row["repository_selection"],
          suspended_at: parse_time(row["suspended_at"]),
          inserted_at: now,
          updated_at: now
        }
      end)

    ids = Enum.map(entries, & &1.installation_id)

    Gamend.AfterCommit.transaction(fn ->
      Installation
      |> where([i], i.user_id == ^user_id and i.installation_id not in ^ids)
      |> Repo.delete_all()

      # Upsert on the user × installation pair: a reconnect refreshes the
      # account name and suspension rather than failing on the row it made
      # last time.
      Repo.insert_all(Installation, entries,
        on_conflict:
          {:replace,
           [
             :account_login,
             :account_id,
             :account_type,
             :repository_selection,
             :suspended_at,
             :updated_at
           ]},
        conflict_target: [:user_id, :installation_id]
      )
    end)

    list_installations(user_id)
  end

  ## Installations

  @doc """
  Every installation on this server, newest first, for `/admin/github`.

  Each row carries the user who connected it and, when the host counts them
  (`config :gamend_core, :github_usage, {module, function}`, answering
  `%{installation_id => count}`), how many of the host's things use it in
  `uses` (`nil` when the host counts nothing). A suspended or unused
  installation is then visible as such: the first is GitHub's doing and the
  second is a customer who left.
  """
  @spec list_all_installations(keyword()) :: [map()]
  def list_all_installations(opts \\ []) do
    installations =
      Installation
      |> order_by([i], desc: i.inserted_at)
      |> Gamend.Query.page(opts)
      |> Repo.all()

    users =
      installations
      |> Enum.map(& &1.user_id)
      |> Enum.uniq()
      |> then(&Repo.all(from u in Gamend.Accounts.User, where: u.id in ^&1))
      |> Map.new(&{&1.id, &1})

    usage = usage()

    Enum.map(installations, fn i ->
      %{
        installation: i,
        user: Map.get(users, i.user_id),
        uses: usage && Map.get(usage, i.installation_id, 0)
      }
    end)
  end

  @doc "How many installations the server holds, across every user."
  @spec count_all_installations() :: non_neg_integer()
  def count_all_installations, do: Repo.aggregate(Installation, :count)

  @doc """
  What the host's usage callback answers, or `nil` when it counts nothing
  (`list_all_installations/1`).
  """
  @spec usage() :: %{integer() => non_neg_integer()} | nil
  def usage do
    case Application.get_env(:gamend_core, :github_usage) do
      {module, function} -> apply(module, function, [])
      nil -> nil
    end
  end

  @doc "The installations a user connected, by account name."
  @spec list_installations(String.t()) :: [Installation.t()]
  def list_installations(user_id) when is_binary(user_id) do
    Installation
    |> where([i], i.user_id == ^user_id)
    |> order_by([i], asc: i.account_login)
    |> Repo.all()
  end

  @doc "Count for `list_installations/1`."
  @spec count_installations(String.t()) :: non_neg_integer()
  def count_installations(user_id) when is_binary(user_id) do
    Repo.aggregate(where(Installation, [i], i.user_id == ^user_id), :count)
  end

  @doc "One of a user's installations, by GitHub's id. `nil` if it is not theirs."
  @spec get_installation(Gamend.Accounts.User.t(), integer()) :: Installation.t() | nil
  def get_installation(%{id: user_id}, installation_id) when is_integer(installation_id) do
    Repo.get_by(Installation, user_id: user_id, installation_id: installation_id)
  end

  def get_installation(_user, _id), do: nil

  @doc "Forget one of a user's installations. The App stays installed on GitHub."
  @spec unlink_installation(Gamend.Accounts.User.t(), integer()) :: :ok
  def unlink_installation(%{id: user_id}, installation_id) when is_integer(installation_id) do
    Installation
    |> where([i], i.user_id == ^user_id and i.installation_id == ^installation_id)
    |> Repo.delete_all()

    :ok
  end

  @doc """
  The App was uninstalled: every user's row for it goes, and its cached token.
  What the host bound to it is the host's to unbind (`installation_event/2`
  answers `{:deleted, id}`).
  """
  @spec installation_deleted(integer()) :: :ok
  def installation_deleted(installation_id) when is_integer(installation_id) do
    forget_installation_token(installation_id)

    Installation
    |> where([i], i.installation_id == ^installation_id)
    |> Repo.delete_all()

    :ok
  end

  @doc "Record that GitHub suspended, or reinstated, an installation."
  @spec installation_suspended(integer(), DateTime.t() | nil) :: :ok
  def installation_suspended(installation_id, at) when is_integer(installation_id) do
    Installation
    |> where([i], i.installation_id == ^installation_id)
    |> Repo.update_all(set: [suspended_at: at, updated_at: DateTime.utc_now()])

    :ok
  end

  ## Repositories

  @doc """
  The repositories a user's installation may reach, for a picker. Only the
  fields a form needs, so a GitHub response shape change stays out here.
  """
  @spec repositories(Gamend.Accounts.User.t(), integer()) ::
          {:ok, [map()]} | {:error, :not_linked | term()}
  def repositories(user, installation_id) do
    with %Installation{} <- get_installation(user, installation_id) || {:error, :not_linked},
         {:ok, token} <- installation_token(installation_id),
         {:ok, rows} <- API.installation_repositories(token) do
      {:ok, Enum.map(rows, &repository/1)}
    end
  end

  @doc """
  One repository of a user's installation, by GitHub's id: GitHub's answer,
  so a host binds only a repository the installation really reaches.
  """
  @spec repository(Gamend.Accounts.User.t(), integer(), integer()) ::
          {:ok, map()} | {:error, :not_linked | :not_found | term()}
  def repository(user, installation_id, repo_id) when is_integer(repo_id) do
    with {:ok, repos} <- repositories(user, installation_id) do
      case Enum.find(repos, &(&1.id == repo_id)) do
        nil -> {:error, :not_found}
        repo -> {:ok, repo}
      end
    end
  end

  defp repository(row) do
    %{
      id: row["id"],
      full_name: row["full_name"],
      clone_url: row["clone_url"],
      html_url: row["html_url"],
      default_branch: row["default_branch"] || "main",
      private: row["private"] == true
    }
  end

  ## The webhook

  @doc """
  Verify a delivery's `X-Hub-Signature-256` against the raw request body.

  Over the raw body, in constant time, and never over the parsed params,
  which are a re-encoding and would let a crafted payload pass a check its
  own bytes would fail. Refuses when no secret is configured: an endpoint
  anyone can POST to and that starts work must not be open by default.
  """
  @spec verify_webhook(binary(), String.t() | nil) :: :ok | {:error, atom()}
  def verify_webhook(_raw_body, nil), do: {:error, :missing_signature}

  def verify_webhook(raw_body, "sha256=" <> provided) when is_binary(raw_body) do
    case config(:webhook_secret) do
      secret when is_binary(secret) and secret != "" ->
        expected =
          :hmac
          |> :crypto.mac(:sha256, secret, raw_body)
          |> Base.encode16(case: :lower)

        # Constant time: a byte-by-byte compare leaks the prefix length of a
        # correct guess, which is enough to forge a signature given attempts.
        if Plug.Crypto.secure_compare(expected, String.downcase(provided)) do
          :ok
        else
          {:error, :bad_signature}
        end

      _unset ->
        Logger.warning("github: refusing a webhook, GAMEND_GITHUB_WEBHOOK_SECRET is unset")
        {:error, :not_configured}
    end
  end

  def verify_webhook(_raw_body, _malformed), do: {:error, :bad_signature}

  @doc """
  What a `push` payload means: the ref and commit pushed, the branch when it
  is one, and the repository by GitHub's id and its URLs.

  A delete carries no commit and is `{:error, :deleted}`.
  """
  @spec push_event(map()) ::
          {:ok,
           %{
             ref: String.t(),
             branch: String.t() | nil,
             sha: String.t(),
             repo_id: integer() | nil,
             repo_urls: [String.t()]
           }}
          | {:error, atom()}
  def push_event(%{"deleted" => true}), do: {:error, :deleted}

  def push_event(%{"ref" => "refs/" <> _ = ref} = payload) do
    sha = payload["after"] || get_in(payload, ["head_commit", "id"])

    if is_binary(sha) and sha != "" and sha != String.duplicate("0", 40) do
      {:ok,
       %{
         ref: short_ref(ref),
         branch: branch(ref),
         sha: sha,
         repo_id: repo_id(payload),
         repo_urls: repo_urls(payload)
       }}
    else
      {:error, :no_commit}
    end
  end

  def push_event(_payload), do: {:error, :unsupported}

  defp short_ref("refs/heads/" <> name), do: name
  defp short_ref("refs/tags/" <> name), do: name
  defp short_ref(ref), do: ref

  defp branch("refs/heads/" <> name), do: name
  defp branch(_ref), do: nil

  defp repo_id(%{"repository" => %{"id" => id}}) when is_integer(id), do: id
  defp repo_id(_payload), do: nil

  defp repo_urls(%{"repository" => repository}) when is_map(repository) do
    Enum.filter(
      [repository["clone_url"], repository["html_url"], repository["ssh_url"]],
      &is_binary/1
    )
  end

  defp repo_urls(_payload), do: []

  @doc """
  The App's own lifecycle, from a verified delivery's `X-GitHub-Event` and
  payload. This module's rows follow it here; the answer is what the host
  has to unbind:

    * `{:deleted, installation_id}`: the App was uninstalled;
    * `{:repositories_removed, installation_id, repo_ids}`: the installation
      no longer reaches those repositories;
    * `:ok`: nothing for the host (a suspension, any other event).

  An uninstall is the customer withdrawing access, so what borrowed it stops
  the moment GitHub says so rather than at the next failed clone.
  """
  @spec installation_event(String.t() | nil, map()) ::
          {:deleted, integer()} | {:repositories_removed, integer(), [integer()]} | :ok
  def installation_event("installation", %{"action" => action} = payload) do
    case {action, installation_id(payload)} do
      {"deleted", id} when is_integer(id) ->
        installation_deleted(id)
        {:deleted, id}

      {"suspend", id} when is_integer(id) ->
        installation_suspended(id, DateTime.utc_now())

      {"unsuspend", id} when is_integer(id) ->
        installation_suspended(id, nil)

      _other ->
        :ok
    end
  end

  def installation_event("installation_repositories", %{"action" => "removed"} = payload) do
    with id when is_integer(id) <- installation_id(payload),
         [_ | _] = repos <- List.wrap(payload["repositories_removed"]) do
      {:repositories_removed, id, repos |> Enum.map(& &1["id"]) |> Enum.filter(&is_integer/1)}
    else
      _ -> :ok
    end
  end

  def installation_event(_event, _payload), do: :ok

  defp installation_id(%{"installation" => %{"id" => id}}) when is_integer(id), do: id
  defp installation_id(_payload), do: nil

  ## The client pair, `Gamend.OAuth.Providers`'s

  @doc false
  def client_id, do: Gamend.Settings.get(Gamend.OAuth.Providers, :github_client_id)

  @doc false
  def client_secret, do: Gamend.Settings.get(Gamend.OAuth.Providers, :github_client_secret)

  defp parse_time(nil), do: nil

  defp parse_time(iso) when is_binary(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, at, _} -> at
      _ -> nil
    end
  end
end
