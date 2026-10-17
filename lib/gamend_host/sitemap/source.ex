defmodule GamendHost.Sitemap.Source do
  @moduledoc """
  What each dated public page is made of, for `GamendWeb.Sitemap.Lastmod`.

  Content is the rendered page, never the bytes of the file behind it. That is
  deliberate: the docs and the changelog are edited constantly for wording that
  never reaches a reader — a reflowed paragraph, a moved heading level, a
  trailing newline — and a date taken from the file would move on every one of
  them. Hashing what renders makes that churn invisible, so `<lastmod>` keeps
  meaning "the page changed" rather than "the repo was touched".

  Only pages whose content lives in markdown are here. The rest of the site is
  rendered from code, which the manifest cannot see, so they carry no date at
  all rather than a misleading one. Blog posts are absent for the opposite
  reason: each one already states its own date in front matter, and the
  controller uses that directly.

  ## Keys

  A key names the content, not the URL: `docs/payments` stays put if the route
  is ever renamed. Locales are not part of a key — every translation of a page
  shares one date, because they share one source of truth.

  The `docs` hub is a roll-up: its content is the hashes of its guides, so it
  moves exactly when one of them does, at the cost of one extra hash rather
  than a second walk of the markdown.
  """

  @behaviour GamendWeb.Sitemap.Source

  alias Gamend.Content
  alias GamendWeb.Sitemap.Lastmod

  @impl true
  def entries do
    guides = guide_entries()

    [
      %{key: "docs", content: Enum.map(guides, &Lastmod.hash(&1.content))},
      %{key: "changelog", content: [Content.changelog_html() || ""]},
      %{key: "roadmap", content: [Content.roadmap_html() || ""]}
    ] ++ guides
  end

  # Title and summary are hashed alongside the body because both are visible —
  # on the guide's own page and in its card on the hub.
  defp guide_entries do
    Enum.map(Content.list_docs(), fn doc ->
      %{
        key: "docs/#{doc.slug}",
        content: [doc.title, doc.summary || "", Content.doc_html(doc.slug) || ""]
      }
    end)
  end
end
