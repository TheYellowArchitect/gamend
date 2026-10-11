defmodule GamendWeb.AdminLive.Analytics do
  @moduledoc """
  Admin view over player activity and retention: DAU / WAU / MAU, new users,
  D1 / D7 / D30 cohort retention and payer conversion, plus a per-day table
  for the last 30 (or 90) UTC days; then the same per FEATURE (every event
  name `Gamend.Analytics.track/3` was given), the daily counters grouped by
  key with their dimensions, and the newest event rows. Read-only; the
  numbers come from `Gamend.Analytics`. Grafana is the place to graph them.
  """
  use GamendWeb, :live_view

  alias Gamend.Analytics

  @windows [30, 90]
  @counter_windows [7, 30, 90]
  @recent_events 50

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Admin · Analytics")
     |> assign(:days, 30)
     |> assign(:counter_days, 7)
     |> reload()}
  end

  @impl true
  def handle_event("window", %{"days" => days}, socket) do
    days =
      case Integer.parse(days) do
        {n, ""} when n in @windows -> n
        _ -> 30
      end

    {:noreply, socket |> assign(:days, days) |> reload()}
  end

  def handle_event("counter_window", %{"days" => days}, socket) do
    days =
      case Integer.parse(days) do
        {n, ""} when n in @counter_windows -> n
        _ -> 7
      end

    {:noreply, socket |> assign(:counter_days, days) |> reload()}
  end

  def handle_event("refresh", _params, socket), do: {:noreply, reload(socket)}

  # Economy uses a fixed 7-day window: it answers "what is the game doing
  # this week", the cohort table answers "how are we trending".
  @flow_days 7

  defp reload(socket) do
    # Gathered for up to a flush window; a reader wants now.
    _ = Analytics.flush()
    today = Date.utc_today()

    socket
    |> assign(:today, today)
    |> assign(:summary, Analytics.summary(today))
    |> assign(:series, socket.assigns.days |> Analytics.daily_series(today) |> Enum.reverse())
    |> assign(:economy, Analytics.economy_totals(@flow_days, today: today))
    |> assign(:features, Analytics.feature_summary(today))
    |> assign(:families, Analytics.families("*", socket.assigns.counter_days, today))
    |> assign(:events, Analytics.recent_events(@recent_events))
    |> assign(:flow_days, @flow_days)
  end

  # ── render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-4">
        <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
          <div class="flex items-center gap-3">
            <.link navigate={~p"/admin"} class="btn btn-surface btn-sm">&larr; Back to Admin</.link>
            <h1 class="text-xl font-bold">Analytics · activity &amp; retention</h1>
          </div>
          <div class="flex items-center gap-2">
            <span class="text-xs text-muted">
              UTC days · as of {Date.to_iso8601(@summary.day)}
            </span>
            <button phx-click="refresh" class="btn btn-ghost btn-sm">Refresh</button>
          </div>
        </div>

        <div class="grid grid-cols-2 md:grid-cols-4 xl:grid-cols-8 gap-3">
          <.stat title="DAU" value={@summary.dau} desc="seen today" />
          <.stat title="WAU" value={@summary.wau} desc="last 7 days" />
          <.stat title="MAU" value={@summary.mau} desc="last 30 days" />
          <.stat title="Stickiness" value={pct(@summary.stickiness)} desc="DAU ÷ MAU" />
          <.stat title="D1" value={pct(@summary.d1)} desc="back the next day" />
          <.stat title="D7" value={pct(@summary.d7)} desc="back on day 7" />
          <.stat title="D30" value={pct(@summary.d30)} desc="back on day 30" />
          <.stat
            title="Payers"
            value={pct(@summary.conversion_30d)}
            desc={"#{@summary.payers_30d} of MAU, 30d"}
          />
        </div>

        <div class="text-xs text-muted">
          New users: {@summary.new_users_7d} in the last 7 days, {@summary.new_users_30d} in the last 30.
          Retention is pooled over the cohorts of the last 60 days that have reached each horizon
          (a D7 needs a cohort at least 7 days old); "—" means no cohort has reached it yet.
        </div>

        <div class="card bg-base-200">
          <div class="card-body">
            <div class="flex flex-wrap items-center justify-between gap-2">
              <h2 class="card-title">Per day</h2>
              <div class="join">
                <button
                  :for={n <- [30, 90]}
                  phx-click="window"
                  phx-value-days={n}
                  class={["btn btn-sm join-item", @days == n && "btn-active"]}
                >
                  {n} days
                </button>
              </div>
            </div>

            <div class="overflow-x-auto">
              <table class="table table-sm table-zebra">
                <thead>
                  <tr>
                    <th>Day (UTC)</th>
                    <th class="text-right">Active</th>
                    <th class="text-right">New</th>
                    <th class="text-right">D1</th>
                    <th class="text-right">D7</th>
                    <th class="text-right">D30</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={row <- @series}>
                    <td class="font-mono">{Date.to_iso8601(row.day)}</td>
                    <td class="text-right">{row.active}</td>
                    <td class="text-right">{row.new_users}</td>
                    <td class="text-right">{pct(row.d1)}</td>
                    <td class="text-right">{pct(row.d7)}</td>
                    <td class="text-right">{pct(row.d30)}</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p class="text-xs text-muted mt-2">
              D1/D7/D30 on a row are that day's sign-up cohort: of the players who registered
              that day, the share seen again exactly 1 / 7 / 30 days later.
            </p>
          </div>
        </div>

        <div class="grid grid-cols-1 xl:grid-cols-2 gap-4">
          <div class="card bg-base-200">
            <div class="card-body">
              <h2 class="card-title">Economy · last {@flow_days} days</h2>
              <p class="text-xs text-muted">
                Every wallet grant and spend, by the ledger <code>reason</code> the game
                passed. Sources are positive, sinks negative — the Net column is what inflates
                or drains balances.
              </p>
              <div class="overflow-x-auto">
                <table class="table table-sm table-zebra">
                  <thead>
                    <tr>
                      <th>Currency</th>
                      <th>Reason</th>
                      <th class="text-right">Granted</th>
                      <th class="text-right">Spent</th>
                      <th class="text-right">Net</th>
                      <th class="text-right">Entries</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={row <- @economy}>
                      <td class="font-mono">{row.currency}</td>
                      <td class="font-mono">{row.reason}</td>
                      <td class="text-right">{row.granted}</td>
                      <td class="text-right">{row.spent}</td>
                      <td class={["text-right font-semibold", net_class(row.net)]}>{row.net}</td>
                      <td class="text-right">{row.entries}</td>
                    </tr>
                    <tr :if={@economy == []}>
                      <td colspan="6" class="text-muted">
                        No ledger entries in the window.
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>

          <div class="card bg-base-200">
            <div class="card-body">
              <h2 class="card-title">Features · who does what</h2>
              <p class="text-xs text-muted">
                Every event name (<code>Gamend.Analytics.track/3</code>) as a feature:
                distinct signed-in users with an event that day / 7 days / 30 days, how
                many were new to it (first event in the last 60 days) and, of those, the
                share back at it 1 / 7 / 30 days later. Events count visitors too.
              </p>
              <div class="overflow-x-auto">
                <table class="table table-sm table-zebra">
                  <thead>
                    <tr>
                      <th>Feature</th>
                      <th class="text-right">DAU</th>
                      <th class="text-right">WAU</th>
                      <th class="text-right">MAU</th>
                      <th class="text-right">Stick.</th>
                      <th class="text-right">New 7d</th>
                      <th class="text-right">New 30d</th>
                      <th class="text-right">D1</th>
                      <th class="text-right">D7</th>
                      <th class="text-right">D30</th>
                      <th class="text-right">Events 7d</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={f <- @features}>
                      <td class="font-mono">{f.name}</td>
                      <td class="text-right">{f.dau}</td>
                      <td class="text-right">{f.wau}</td>
                      <td class="text-right">{f.mau}</td>
                      <td class="text-right">{pct(f.stickiness)}</td>
                      <td class="text-right">{f.new_7d}</td>
                      <td class="text-right">{f.new_30d}</td>
                      <td class="text-right">{pct(f.d1)}</td>
                      <td class="text-right">{pct(f.d7)}</td>
                      <td class="text-right">{pct(f.d30)}</td>
                      <td class="text-right">{f.events_7d}</td>
                    </tr>
                    <tr :if={@features == []}>
                      <td colspan="11" class="text-muted">No events yet.</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>

        <div class="card bg-base-200">
          <div class="card-body">
            <div class="flex flex-wrap items-center justify-between gap-2">
              <h2 class="card-title">Counters · last {@counter_days} days</h2>
              <div class="join">
                <button
                  :for={n <- [7, 30, 90]}
                  phx-click="counter_window"
                  phx-value-days={n}
                  class={["btn btn-sm join-item", @counter_days == n && "btn-active"]}
                >
                  {n} days
                </button>
              </div>
            </div>
            <p class="text-xs text-muted">
              Daily counters (<code>Gamend.Analytics.count/3</code>, and one per <code>track/3</code>
              and per dimension of it) grouped by key, each dimension's
              values largest first. Whatever the game and the site report; empty until they do.
            </p>
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Key</th>
                    <th class="text-right">Today</th>
                    <th class="text-right">Total</th>
                    <th>By dimension</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={fam <- @families}>
                    <td class="font-mono align-top">{fam.key}</td>
                    <td class="text-right align-top">{Map.get(fam.by_day, @today, 0)}</td>
                    <td class="text-right align-top font-semibold">{fam.total}</td>
                    <td>
                      <div :for={{dim, values} <- Enum.sort(fam.dims)} class="text-xs">
                        <span class="font-mono text-muted">{dim}:</span>
                        <span :for={{value, n} <- Enum.take(values, 12)} class="mr-2">
                          <span class="font-mono">{value}</span> {n}
                        </span>
                        <span :if={length(values) > 12} class="text-muted">
                          +{length(values) - 12} more
                        </span>
                      </div>
                    </td>
                  </tr>
                  <tr :if={@families == []}>
                    <td colspan="4" class="text-muted">No counters yet.</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <div class="card bg-base-200">
          <div class="card-body">
            <h2 class="card-title">Newest events</h2>
            <p class="text-xs text-muted">
              The newest {length(@events)} rows of <code>analytics_events</code>: what is being
              tracked right now, with its fields. A visitor has no user; a deleted account's
              rows keep the event and lose the user.
            </p>
            <div class="overflow-x-auto">
              <table class="table table-sm table-zebra">
                <thead>
                  <tr>
                    <th>When (UTC)</th>
                    <th>Event</th>
                    <th>User</th>
                    <th>Fields</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={e <- @events}>
                    <td class="font-mono whitespace-nowrap">
                      {Calendar.strftime(e.inserted_at, "%m-%d %H:%M:%S")}
                    </td>
                    <td class="font-mono">{e.name}</td>
                    <td class="font-mono">{short_id(e.user_id)}</td>
                    <td class="font-mono text-xs">{fields(e.dims)}</td>
                  </tr>
                  <tr :if={@events == []}>
                    <td colspan="4" class="text-muted">No events yet.</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp short_id(nil), do: "—"
  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8)

  defp fields(dims) when is_map(dims),
    do: dims |> Enum.sort() |> Enum.map_join("  ", fn {k, v} -> "#{k}=#{v}" end)

  defp net_class(n) when n > 0, do: "text-success"
  defp net_class(n) when n < 0, do: "text-error"
  defp net_class(_), do: nil

  attr :title, :string, required: true
  attr :value, :any, required: true
  attr :desc, :string, default: nil

  defp stat(assigns) do
    ~H"""
    <div class="card bg-base-100 p-3">
      <div class="text-xs text-muted">{@title}</div>
      <div class="text-2xl font-bold">{@value}</div>
      <div :if={@desc} class="text-xs text-muted">{@desc}</div>
    </div>
    """
  end

  defp pct(nil), do: "—"
  defp pct(rate) when is_float(rate), do: "#{Float.round(rate * 100, 1)}%"
end
