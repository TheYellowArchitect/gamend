defmodule GamendWeb.Plugs.IpBan do
  @moduledoc """
  Plug that blocks requests from banned IP addresses, and the IP side of
  `Gamend.Bans`: it keys an address the way the plug checks it.

  The check is an ETS read (`Gamend.Bans.Cache`); the bans themselves are
  `Gamend.Bans` rows of kind `:ip`, persisted, kept as history after they end,
  and carried to every app instance over PubSub.

  ## Banning / unbanning an IP

      GamendWeb.Plugs.IpBan.ban("1.2.3.4")                    # permanent
      GamendWeb.Plugs.IpBan.ban("1.2.3.4",                    # 24h ban
        expires_at: Gamend.Bans.expires_after(:timer.hours(24)),
        reason: "Scraping"
      )
      GamendWeb.Plugs.IpBan.unban("1.2.3.4")
      GamendWeb.Plugs.IpBan.banned?("1.2.3.4")

  This plug runs early in the endpoint pipeline, after `RealIp` extracts
  the true client address.

  An IPv6 address is banned by its /64 (`GamendWeb.RateLimit.ip_key/1`): one
  subscriber is routinely handed the whole /64 and moves around inside it, so
  a ban on a single address would not hold. `ban("2001:db8::1")` is listed as
  `2001:db8::/64`. An IPv4 address is banned as itself.
  """

  import Plug.Conn

  alias Gamend.Bans

  @behaviour Plug

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Ban an IP address. `opts` are `Gamend.Bans.ban/3`'s: `:expires_at` (none is
  permanent), `:reason`, `:source`, `:by`.

  The ban takes effect locally right away, is persisted to the database,
  and is broadcast to the other app instances.
  """
  @spec ban(String.t(), keyword()) :: {:ok, Bans.Ban.t()} | {:error, Ecto.Changeset.t()}
  def ban(ip, opts \\ []), do: Bans.ban(:ip, GamendWeb.RateLimit.ip_key(ip), opts)

  @doc """
  Lift the ban on the given IP (locally, persisted, and cluster-wide): the
  ban on its /64 for IPv6, and any on the exact address, which is how IPv6
  bans were stored before they covered the /64.
  """
  @spec unban(String.t(), keyword()) :: :ok
  def unban(ip, opts \\ []) do
    [GamendWeb.RateLimit.ip_key(ip), ip]
    |> Enum.uniq()
    |> Enum.each(&Bans.lift(:ip, &1, opts))
  end

  @doc "Check if an IP is currently banned: itself, or its /64 for IPv6."
  @spec banned?(String.t()) :: boolean()
  def banned?(ip) do
    [ip, GamendWeb.RateLimit.ip_key(ip)] |> Enum.uniq() |> Enum.any?(&Bans.banned?(:ip, &1))
  end

  # ── Plug callbacks ────────────────────────────────────────────────────────

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    network = GamendWeb.RateLimit.ip_key(conn.remote_ip)

    if Bans.banned?(:ip, ip) or (network != ip and Bans.banned?(:ip, network)) do
      conn
      |> send_resp(403, "Forbidden")
      |> halt()
    else
      conn
    end
  end
end
