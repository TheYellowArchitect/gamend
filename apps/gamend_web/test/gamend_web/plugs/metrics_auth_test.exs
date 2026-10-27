defmodule GamendWeb.Plugs.MetricsAuthTest do
  # Who may read `/metrics` (`GamendWeb.Plugs.MetricsAuth`): loopback always;
  # with no token, a private address and nobody else; with a token, every
  # other caller only with it, a private address included.
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias GamendWeb.Plugs.MetricsAuth

  @loopback {127, 0, 0, 1}
  @loopback6 {0, 0, 0, 0, 0, 0, 0, 1}
  @private [{10, 1, 2, 3}, {172, 20, 0, 5}, {192, 168, 1, 9}]
  @public {203, 0, 113, 9}

  setup do
    previous = Application.get_env(:gamend_web, GamendWeb.Observability)
    on_exit(fn -> restore(previous) end)
    :ok
  end

  defp restore(nil), do: Application.delete_env(:gamend_web, GamendWeb.Observability)
  defp restore(value), do: Application.put_env(:gamend_web, GamendWeb.Observability, value)

  defp token(value) do
    config = Application.get_env(:gamend_web, GamendWeb.Observability, [])

    Application.put_env(
      :gamend_web,
      GamendWeb.Observability,
      Keyword.put(config, :metrics_token, value)
    )
  end

  defp call(ip, header \\ nil) do
    conn = conn(:get, "/metrics") |> Map.put(:remote_ip, ip)
    conn = if header, do: put_req_header(conn, "authorization", header), else: conn
    MetricsAuth.call(conn, MetricsAuth.init([]))
  end

  defp allowed?(conn), do: not conn.halted
  defp denied?(conn), do: conn.halted and conn.status == 401

  describe "with no token set" do
    setup do: token(nil)

    test "loopback and private addresses are let in" do
      assert allowed?(call(@loopback))
      assert allowed?(call(@loopback6))
      for ip <- @private, do: assert(allowed?(call(ip)), "#{inspect(ip)} was denied")
    end

    test "a public address is turned away, whatever it sends" do
      assert denied?(call(@public))
      assert denied?(call(@public, "Bearer anything"))
    end

    test "an address just outside a private range is public" do
      assert denied?(call({172, 32, 0, 1}))
      assert denied?(call({172, 15, 0, 1}))
      assert denied?(call({192, 169, 0, 1}))
    end
  end

  describe "with a token set" do
    setup do: token("s3cret")

    test "the right bearer token is let in, from anywhere" do
      assert allowed?(call(@public, "Bearer s3cret"))
      assert allowed?(call(hd(@private), "Bearer s3cret"))
    end

    test "a private address needs the token too; loopback never does" do
      assert denied?(call(hd(@private)))
      assert allowed?(call(@loopback))
    end

    test "a wrong token, another scheme or no header is turned away" do
      assert denied?(call(@public, "Bearer nope"))
      assert denied?(call(@public, "Basic s3cret"))
      assert denied?(call(@public, "s3cret"))
      assert denied?(call(@public))
    end
  end

  test "an empty setting is no token" do
    token("")
    assert allowed?(call(hd(@private)))
    assert denied?(call(@public))
  end
end
