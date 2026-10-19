defmodule Mix.Tasks.Demo.Bench do
  @shortdoc "Times every page of a running server against the demo data"

  @moduledoc """
  Runs the page bench (`stress/pages/bench.mjs`) against a server that is
  already running on the same database, signed in as a bench admin and as the
  heavy demo player (`Gamend.DemoSeed.bench_context/0`).

      mix demo.seed --count 100000
      mix demo.bench --base-url http://localhost:4091 --label 100k

  Every page loads (the HTTP render), joins its LiveView socket, and fires the
  pagination, sort and search events found on it; each step is timed and
  checked. Options, passed through to the client:

    * `--base-url` — the running server (default `http://localhost:4000`)
    * `--label` — names the run in the report (`10k`, `100k`, …)
    * `--out` — where the JSON result goes (default `stress/results/pages/<label>.json`)
    * `--spec` — another page list to run after core's, repeatable (a host's
      pages)
    * `--only` — a substring: only the pages whose path holds it
    * `--repeat` — runs per page; the report keeps the median (default 3)

  The server must run without the per-IP rate limit
  (`GAMEND_RATELIMIT_ENABLED=false`), or the bench meets 429s. Needs `node`
  (22 or later, for its WebSocket) and a gamend checkout: the client is not in
  the Hex package. Compare runs with
  `node stress/pages/bench.mjs --compare a.json b.json …`.
  """

  use Mix.Task

  alias GamendWeb.UserAuth

  @switches [
    base_url: :string,
    label: :string,
    out: :string,
    spec: :keep,
    only: :string,
    repeat: :integer
  ]

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} = OptionParser.parse(args, strict: @switches)
    client = Path.expand("../../../../../stress/pages/bench.mjs", __DIR__)

    unless File.exists?(client) do
      Mix.raise("the page bench client is not here (#{client}): it needs a gamend checkout")
    end

    context = bench_context()
    {name, admin} = UserAuth.remember_me_cookie(context.admin_token)
    {^name, player} = UserAuth.remember_me_cookie(context.player_token)

    env = [
      {"BENCH_ADMIN_COOKIE", "#{name}=#{admin}"},
      {"BENCH_PLAYER_COOKIE", "#{name}=#{player}"},
      {"BENCH_PARAMS", Jason.encode!(context.params)}
    ]

    {_out, status} =
      System.cmd("node", [client | client_args(opts)],
        env: env,
        into: IO.stream(),
        stderr_to_stdout: true
      )

    if status != 0, do: Mix.raise("page bench failed (exit #{status})")
  end

  # Only the database: the server under test is a separate node, and this one
  # must not boot a second copy of the application next to it.
  defp bench_context do
    Mix.Task.run("app.config")
    Logger.configure(level: :info)
    # Signing a cookie caches its derived key in plug_crypto's table.
    {:ok, _} = Application.ensure_all_started([:plug_crypto, :ecto_sql])
    {:ok, _} = Gamend.Repo.__adapter__().ensure_all_started(Gamend.Repo.config(), :temporary)
    {:ok, _} = Gamend.Repo.start_link(pool_size: 2)
    Gamend.DemoSeed.bench_context()
  rescue
    error in ArgumentError -> Mix.raise(Exception.message(error))
  end

  defp client_args(opts) do
    base = Keyword.get(opts, :base_url, "http://localhost:4000")
    label = Keyword.get(opts, :label, "run")
    core_spec = Path.expand("../../../../../stress/pages/core_pages.mjs", __DIR__)
    specs = [core_spec | Keyword.get_values(opts, :spec) |> Enum.map(&Path.expand/1)]

    ["--base", base, "--label", label] ++
      Enum.flat_map(specs, &["--spec", &1]) ++
      optional("--out", opts[:out] && Path.expand(opts[:out])) ++
      optional("--only", opts[:only]) ++
      optional("--repeat", opts[:repeat] && Integer.to_string(opts[:repeat]))
  end

  defp optional(_flag, nil), do: []
  defp optional(flag, value), do: [flag, value]
end
