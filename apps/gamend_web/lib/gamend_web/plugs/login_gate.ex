defmodule GamendWeb.Plugs.LoginGate do
  @moduledoc """
  At most `max_logins_in_flight` sign-ins served at once
  (`Gamend.Limits`); past it, `503` with `Retry-After`, before any work.

  A sign-in hashes a password or writes a session, and after a restart every
  client asks at once: measured on half a CPU, 600 reconnecting clients
  queued 1,886 processes and ran a 512 MB server out of memory. Refused
  early, they wait at the clients and come back.

  Counted in a registry of request processes (`GamendWeb.ConnectionTracker`),
  so a request that crashes is uncounted when its process ends.
  """

  import Plug.Conn

  alias GamendWeb.ConnectionTracker

  @retry_after_seconds 2

  def init(opts), do: opts

  def call(conn, _opts) do
    limit = Gamend.Limits.get(:max_logins_in_flight)

    cond do
      not is_integer(limit) or limit <= 0 ->
        conn

      ConnectionTracker.count_logins() >= limit ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(@retry_after_seconds))
        |> put_resp_content_type("application/json")
        |> send_resp(
          503,
          ~s({"error":"busy","message":"Too many sign-ins at once; retry shortly."})
        )
        |> halt()

      true ->
        :ok = ConnectionTracker.start_login()

        register_before_send(conn, fn conn ->
          ConnectionTracker.finish_login()
          conn
        end)
    end
  end
end
