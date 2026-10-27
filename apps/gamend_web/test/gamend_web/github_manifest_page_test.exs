defmodule GamendWeb.GitHubManifestPageTest do
  @moduledoc """
  The two pages `mix gamend.github.app` serves on localhost: the form says
  what it creates before the button is pressed, and the code GitHub sends
  back is accepted only with this run's state.
  """

  use ExUnit.Case, async: true

  import Plug.Test

  alias Gamend.GitHub.Manifest
  alias GamendWeb.GitHubManifestPage

  @host "https://example.org"

  setup do
    manifest = Manifest.build(@host, redirect_url: "http://localhost:4777/callback")

    opts =
      GitHubManifestPage.init(
        owner: self(),
        state: "s3cret",
        manifest: manifest,
        org: nil,
        action: Manifest.form_action(nil, "s3cret")
      )

    %{opts: opts}
  end

  test "the form carries the manifest and says what it creates", %{opts: opts} do
    conn = :get |> conn("/") |> GitHubManifestPage.call(opts)

    assert conn.status == 200
    assert conn.resp_body =~ ~s(action="https://github.com/settings/apps/new?state=s3cret")
    assert conn.resp_body =~ ~s(name="manifest")
    assert conn.resp_body =~ "example.org/github/callback"
    assert conn.resp_body =~ "Register Gamend"
    assert conn.resp_body =~ "contents read"
    assert conn.resp_body =~ "No webhook."
    assert conn.resp_body =~ "your personal account"
  end

  test "the form names the organisation it registers under", %{opts: opts} do
    opts = %{opts | org: "appsinacup", action: Manifest.form_action("appsinacup", "s3cret")}
    conn = :get |> conn("/") |> GitHubManifestPage.call(opts)

    assert conn.resp_body =~ "organisation <strong>appsinacup</strong>"

    assert conn.resp_body =~
             ~s(action="https://github.com/organizations/appsinacup/settings/apps/new?state=s3cret")
  end

  test "the code is handed over with this run's state only", %{opts: opts} do
    conn = :get |> conn("/callback?code=abc&state=s3cret") |> GitHubManifestPage.call(opts)

    assert conn.status == 200
    assert_received {:manifest_code, "abc"}

    conn = :get |> conn("/callback?code=xyz&state=other") |> GitHubManifestPage.call(opts)

    assert conn.status == 400
    refute_received {:manifest_code, "xyz"}
  end
end
