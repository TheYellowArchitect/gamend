defmodule GamendWeb.GitHubManifestPage do
  @moduledoc """
  The two pages `mix gamend.github.app` serves on localhost: the form that
  posts the manifest (`Gamend.GitHub.Manifest`) to GitHub, and the address
  GitHub sends the code back to. The code goes to the task's process; nothing
  is stored.
  """

  @behaviour Plug

  import Plug.Conn

  alias Gamend.GitHub.Manifest

  @impl true
  def init(opts), do: Map.new(opts)

  @impl true
  def call(%Plug.Conn{method: "GET", request_path: "/"} = conn, opts) do
    html(conn, 200, form(opts))
  end

  # GitHub redirects here with `code` and the `state` the form carried. A
  # code arriving with someone else's state is not this run's, and is not
  # forwarded: it would register whatever manifest that other form held.
  def call(%Plug.Conn{method: "GET", request_path: "/callback"} = conn, opts) do
    conn = fetch_query_params(conn)

    case conn.query_params do
      %{"code" => code, "state" => state}
      when is_binary(code) and code != "" and state == opts.state ->
        send(opts.owner, {:manifest_code, code})

        html(
          conn,
          200,
          page("<h1>Registered.</h1><p>Back to the terminal: it has the rest.</p>")
        )

      _ ->
        html(
          conn,
          400,
          page("<h1>Not this run.</h1><p>The state does not match. Start over.</p>")
        )
    end
  end

  def call(conn, _opts), do: html(conn, 404, page("<h1>Not found.</h1>"))

  defp html(conn, status, body) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(status, body)
  end

  # The manifest rides in a hidden field, escaped; what the person sees is
  # the App's name, every URL it will be created with and what it may do, so
  # the button is pressed knowing what it does.
  defp form(opts) do
    manifest = opts.manifest
    json = Plug.HTML.html_escape(Jason.encode!(manifest))

    owner =
      case Map.get(opts, :org) do
        nil ->
          "<strong>your personal account</strong> (rerun with <code>--org &lt;name&gt;</code> for an organisation)"

        org ->
          "the organisation <strong>#{Plug.HTML.html_escape(org)}</strong>"
      end

    permissions =
      manifest["default_permissions"]
      |> Enum.sort()
      |> Enum.map_join(", ", fn {name, access} -> "#{name} #{access}" end)

    events =
      case manifest["default_events"] do
        [_ | _] = events -> "Events: " <> Enum.join(events, ", ") <> "."
        _ -> "No webhook."
      end

    page("""
    <h1>Register #{Plug.HTML.html_escape(manifest["name"])}</h1>
    <p>Under #{owner}.</p>
    <p>GitHub will create the App with these URLs:</p>
    <ul>#{Enum.map_join(Manifest.urls(manifest), "", &"<li><code>#{Plug.HTML.html_escape(&1)}</code></li>")}</ul>
    <p>Permissions: #{Plug.HTML.html_escape(permissions)}. #{events}</p>
    <form method="post" action="#{Plug.HTML.html_escape(opts.action)}">
      <input type="hidden" name="manifest" value="#{json}">
      <button type="submit">Create it on github.com</button>
    </form>
    <p>GitHub shows the App once more and asks you to confirm. It then sends
    you back here, and the terminal finishes.</p>
    """)
  end

  defp page(body) do
    """
    <!doctype html>
    <meta charset="utf-8">
    <title>GitHub App</title>
    <style>
      body { font: 16px/1.5 system-ui, sans-serif; max-width: 40rem; margin: 3rem auto; padding: 0 1rem; }
      code { font-size: .9em; }
      button { font: inherit; padding: .5rem 1rem; }
    </style>
    #{body}
    """
  end
end
