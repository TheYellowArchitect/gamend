defmodule GamendWeb.HostRuntimeOriginTest do
  @moduledoc """
  Which browser origins may open a socket: the `check_origin` that
  `GamendWeb.HostRuntime.config/2` gives the pages' socket (the endpoint's)
  and the game socket. Read from the environment, so not async.
  """
  use ExUnit.Case, async: false

  alias Phoenix.Socket.Transport

  @vars ~w(GAMEND_HTTP_HOST GAMEND_HTTP_ALLOWED_ORIGINS GAMEND_HTTP_OTHER_HOSTS)

  setup do
    saved = Map.new(@vars, &{&1, System.get_env(&1)})

    on_exit(fn ->
      Enum.each(saved, fn
        {var, nil} -> System.delete_env(var)
        {var, value} -> System.put_env(var, value)
      end)
    end)

    Enum.each(@vars, &System.delete_env/1)
    System.put_env("GAMEND_HTTP_HOST", "mygame.gamend.cloud")
    :ok
  end

  defp config, do: GamendWeb.HostRuntime.config(:prod, host_root: File.cwd!())

  defp pages do
    for {:gamend_web, GamendWeb.Endpoint, opts} <- config(), reduce: [] do
      acc -> Keyword.merge(acc, opts)
    end
    |> Keyword.fetch!(:check_origin)
  end

  defp entry(key) do
    Enum.find_value(config(), fn
      {:gamend_web, ^key, value} -> {:ok, value}
      _ -> nil
    end)
  end

  defp game, do: entry(:game_socket_check_origin)
  defp cors, do: entry(:cors_allowed_origins)

  # Phoenix's own check, as a socket's upgrade request runs it.
  defp allowed?(check_origin, origin) do
    conn =
      Plug.Test.conn(:get, "/socket/websocket")
      |> Plug.Conn.put_req_header("origin", origin)
      |> Transport.check_origin(GamendWeb.UserSocket, GamendWeb.Endpoint,
        check_origin: check_origin
      )

    not conn.halted
  end

  test "no allowlist: the game socket takes any origin, the pages their own name" do
    assert pages() == ["//mygame.gamend.cloud"]
    assert game() == {:ok, false}
    assert cors() == {:ok, "*"}
  end

  test "another name, such as a custom domain, is the pages' origin beside the host" do
    System.put_env("GAMEND_HTTP_OTHER_HOSTS", "play.mygame.com")

    assert pages() == ["//mygame.gamend.cloud", "//play.mygame.com"]
    assert game() == {:ok, false}
  end

  test "an allowlist holds both sockets to it and the server's own names" do
    System.put_env("GAMEND_HTTP_ALLOWED_ORIGINS", "https://html.itch.zone")
    System.put_env("GAMEND_HTTP_OTHER_HOSTS", "play.mygame.com")

    expected = ["//mygame.gamend.cloud", "//play.mygame.com", "https://html.itch.zone"]
    assert pages() == expected
    assert game() == {:ok, expected}
  end

  @tag capture_log: true
  test "a regex: entry becomes a call Phoenix makes, not a string it cannot parse" do
    System.put_env("GAMEND_HTTP_ALLOWED_ORIGINS", ~S"regex:^https://[a-z0-9-]+\.itch\.zone$")

    assert {GamendWeb.Http, :origin_allowed?, [["//mygame.gamend.cloud", %Regex{}]]} = pages()
    assert {:ok, {GamendWeb.Http, :origin_allowed?, [_allowed]}} = game()

    check_origin = pages()
    assert allowed?(check_origin, "https://html.itch.zone")
    assert allowed?(check_origin, "https://mygame.gamend.cloud")
    refute allowed?(check_origin, "https://evil.example")
  end

  describe "GamendWeb.Http.origin_allowed?/2" do
    defp check(origin, allowed), do: GamendWeb.Http.origin_allowed?(URI.parse(origin), allowed)

    test "a //host entry takes either scheme and any port" do
      assert check("https://a.com", ["//a.com"])
      assert check("http://a.com:4000", ["//a.com"])
      refute check("https://b.com", ["//a.com"])
    end

    test "a full origin keeps its scheme and port" do
      assert check("https://a.com", ["https://a.com"])
      refute check("http://a.com", ["https://a.com"])
      refute check("https://a.com:8443", ["https://a.com"])
    end

    test "a //*.host entry takes the host and its subdomains" do
      assert check("https://a.com", ["//*.a.com"])
      assert check("https://x.a.com", ["//*.a.com"])
      refute check("https://xa.com", ["//*.a.com"])
    end

    test "a pattern matches the whole origin" do
      assert check("https://html.itch.zone", [~r/\.itch\.zone$/])
      refute check("https://itch.zone.evil", [~r/\.itch\.zone$/])
    end

    test "an origin with no host is refused" do
      refute check("null", ["//a.com", ~r/.*/])
    end
  end
end
