defmodule Mix.Tasks.Gamend.Sitemap.Lastmod do
  @shortdoc "Regenerates the sitemap lastmod manifest from page content"

  @moduledoc """
  Rehashes every page the host's `GamendWeb.Sitemap.Source` reports and moves
  the `<lastmod>` date only for those whose content actually changed.

      mix gamend.sitemap.lastmod           # rewrite the manifest
      mix gamend.sitemap.lastmod --check   # fail if it is stale
      mix gamend.sitemap.lastmod --dry-run # report changes, write nothing

  Run it whenever content lands — after a translation sync, before a deploy —
  and commit the result. The manifest is data, not a build artifact: it is the
  only record of *when* a page reached its current state, so regenerating it
  from scratch on a fresh checkout would lose every date. Do not gitignore it.

  `--check` belongs in CI next to `mix gamend.settings.env_example --check`: it
  fails when content was edited without restamping, which is the mistake that
  leaves the sitemap advertising dates that no longer match the pages.
  """

  use Mix.Task

  alias GamendWeb.Sitemap.Lastmod
  alias GamendWeb.Sitemap.Source

  @impl true
  def run(argv) do
    # app.start, not app.config: a source reads the host's content, and that
    # content generally lives in whatever the application loads at boot —
    # dictionaries, metadata, parsed files. With only the config loaded, a
    # source sees an empty world and reports zero pages.
    Mix.Task.run("app.start")

    {opts, _rest} =
      OptionParser.parse!(argv,
        strict: [check: :boolean, dry_run: :boolean, output: :string]
      )

    source = Source.source() || Mix.raise(no_source())
    path = Keyword.get(opts, :output, Source.manifest_path())

    entries = source.entries()
    manifest = Lastmod.load(path)
    {next, changed} = Lastmod.stamp(manifest, entries, Date.utc_today())

    report(entries, changed)

    cond do
      Keyword.get(opts, :check, false) -> check(path, next)
      Keyword.get(opts, :dry_run, false) -> Mix.shell().info("dry run — #{path} not written")
      true -> write(path, next)
    end
  end

  defp write(path, manifest) do
    case Lastmod.save(path, manifest) do
      :ok -> Mix.shell().info("wrote #{path} (#{map_size(manifest)} pages)")
      {:error, reason} -> Mix.raise("could not write #{path}: #{:file.format_error(reason)}")
    end
  end

  # Compares the rendered form rather than the decoded map, so that a manifest
  # which is semantically right but differently formatted still counts as
  # stale — otherwise CI passes and the next run produces a spurious diff.
  defp check(path, manifest) do
    case File.read(path) do
      {:ok, body} ->
        if body == Lastmod.encode(manifest) do
          Mix.shell().info("#{path} is up to date")
        else
          Mix.raise("#{path} is out of date. Run: mix gamend.sitemap.lastmod")
        end

      {:error, _reason} ->
        Mix.raise("#{path} does not exist. Run: mix gamend.sitemap.lastmod")
    end
  end

  defp report(entries, []) do
    Mix.shell().info("#{length(entries)} pages, none changed")
  end

  defp report(entries, changed) do
    Mix.shell().info("#{length(entries)} pages, #{length(changed)} changed:")
    Enum.each(Enum.take(changed, 20), &Mix.shell().info("  #{&1}"))

    case length(changed) - 20 do
      remaining when remaining > 0 -> Mix.shell().info("  … and #{remaining} more")
      _ -> :ok
    end
  end

  defp no_source do
    """
    No sitemap source configured. Set one in config:

        config :gamend_web, GamendWeb.Sitemap,
          source: MyApp.Sitemap.Source,
          manifest: "priv/sitemap_lastmod.json"

    The module implements the GamendWeb.Sitemap.Source behaviour.
    """
  end
end
