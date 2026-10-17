defmodule Gamend.Bans do
  @moduledoc """
  Bans: an IP address or an account kept out for a while, or for good.

  The `bans` table is the source of truth and keeps every ban after it ends,
  so a target's history is its rows. `Gamend.Bans.Cache` holds the active ones
  in ETS for the per-request check (`banned?/2`), and carries each change to
  the other instances over PubSub (`Gamend.Bans.Sync` applies them there and
  loads the table at boot).

  Placing a ban on a target that already has one ends the old one (lifted by
  whoever placed the new one) and starts the new one, so a target has at most
  one active ban.

      Gamend.Bans.ban(:ip, "1.2.3.4", expires_at: Gamend.Bans.expires_after(:timer.hours(24)))
      Gamend.Bans.ban(:account, user.id, expires_at: in_a_week, reason: "Cheating", by: admin.id)
      Gamend.Bans.lift(:account, user.id, by: admin.id)
      Gamend.Bans.banned?(:ip, "1.2.3.4")

  An IP ban's subject is the address as the web layer keys it (an IPv6 one as
  its /64, `GamendWeb.Plugs.IpBan`); an account ban's is the user id.

  ## Account bans

  A banned account still signs in, and can read and delete itself; everything
  else refuses it (the web layer: `GamendWeb.Plugs.AccountBan` on the API, the
  channels, `GamendWeb.UserAuth` on the website). Placing and lifting one
  tells the account on its user topic, `{:account_banned, ban}` and
  `{:account_unbanned, user_id}`, which the user channel passes on as the
  `account_banned` and `account_unbanned` events.
  """

  import Ecto.Query

  alias Gamend.AfterCommit
  alias Gamend.Bans.Ban
  alias Gamend.Bans.Cache
  alias Gamend.Repo

  @history_limit 100

  @doc """
  Bans `subject` until `:expires_at` (a `DateTime`, `nil` for permanent).

  Options: `:expires_at`, `:reason` (shown to the banned player), `:source`
  (`:admin` by default, see `Gamend.Bans.Ban`) and `:by` (the admin's user id).
  The ban applies on this instance at once and on the others within moments.
  """
  @spec ban(Ban.kind(), String.t(), keyword()) :: {:ok, Ban.t()} | {:error, Ecto.Changeset.t()}
  def ban(kind, subject, opts \\ []) when is_binary(subject) do
    now = DateTime.utc_now(:second)

    attrs = %{
      kind: kind,
      subject: subject,
      user_id: if(kind == :account, do: subject),
      expires_at: opts |> Keyword.get(:expires_at) |> truncate(),
      reason: Keyword.get(opts, :reason),
      source: Keyword.get(opts, :source, :admin),
      banned_by: Keyword.get(opts, :by)
    }

    AfterCommit.transact(fn ->
      _ = lift_rows(kind, subject, now, Keyword.get(opts, :by))

      with {:ok, ban} <- %Ban{} |> Ban.changeset(attrs) |> validate_future(now) |> Repo.insert() do
        AfterCommit.defer(fn ->
          Cache.put(ban)
          notify(ban.kind, subject, {:account_banned, ban})
        end)

        {:ok, ban}
      end
    end)
  end

  @doc """
  Ends the active ban on `subject`, if it has one. `:by` is the admin's user id.
  Answers the bans it ended (none, or one).
  """
  @spec lift(Ban.kind(), String.t(), keyword()) :: {:ok, [Ban.t()]}
  def lift(kind, subject, opts \\ []) when is_binary(subject) do
    AfterCommit.transact(fn ->
      lifted = lift_rows(kind, subject, DateTime.utc_now(:second), Keyword.get(opts, :by))

      AfterCommit.defer(fn ->
        Cache.delete(kind, subject)
        if lifted != [], do: notify(kind, subject, {:account_unbanned, subject})
      end)

      {:ok, lifted}
    end)
  end

  @doc "Whether `subject` is banned now: an ETS read, no query."
  @spec banned?(Ban.kind(), String.t()) :: boolean()
  def banned?(kind, subject) when is_binary(subject), do: Cache.banned?(kind, subject)

  @doc "The active ban on `subject`, or nil: for showing its end and reason."
  @spec active(Ban.kind(), String.t()) :: Ban.t() | nil
  def active(kind, subject) when is_binary(subject) do
    DateTime.utc_now(:second)
    |> active_query()
    |> where([b], b.kind == ^kind and b.subject == ^subject)
    |> order_by([b], desc: b.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  The active ban on an account, or nil. Queries only when the cache holds one,
  so it is cheap to ask on every request.
  """
  @spec account_ban(String.t()) :: Ban.t() | nil
  def account_ban(user_id) when is_binary(user_id) do
    if banned?(:account, user_id), do: active(:account, user_id)
  end

  @doc "Every active ban, of one kind or all, newest first."
  @spec list_active(Ban.kind() | nil) :: [Ban.t()]
  def list_active(kind \\ nil) do
    DateTime.utc_now(:second)
    |> active_query()
    |> of_kind(kind)
    |> order_by([b], desc: b.inserted_at)
    |> Repo.all()
  end

  @doc """
  Bans of one kind or all, ended ones too, newest first. `:limit` (100) caps it.
  """
  @spec history(Ban.kind() | nil, keyword()) :: [Ban.t()]
  def history(kind \\ nil, opts \\ []) do
    Ban
    |> of_kind(kind)
    |> order_by([b], desc: b.inserted_at)
    |> limit(^Keyword.get(opts, :limit, @history_limit))
    |> Repo.all()
  end

  @doc "Whether `ban` is in force now."
  @spec active?(Ban.t()) :: boolean()
  def active?(%Ban{lifted_at: nil, expires_at: nil}), do: true

  def active?(%Ban{lifted_at: nil, expires_at: %DateTime{} = expires_at}),
    do: DateTime.after?(expires_at, DateTime.utc_now())

  def active?(%Ban{}), do: false

  @doc "The `expires_at` for a ban lasting `ttl_ms` from now; nil for `:infinity`."
  @spec expires_after(non_neg_integer() | :infinity) :: DateTime.t() | nil
  def expires_after(:infinity), do: nil

  def expires_after(ttl_ms) when is_integer(ttl_ms),
    do: DateTime.utc_now(:second) |> DateTime.add(ttl_ms, :millisecond) |> truncate()

  @doc """
  Deletes bans that ended (lifted or expired) more than `days` ago; an active
  ban is never deleted. `days` of 0 keeps them all. Answers the rows deleted.
  Run by `Gamend.Retention` with `bans_days`.
  """
  @spec prune(integer()) :: non_neg_integer()
  def prune(days) when not is_integer(days) or days <= 0, do: 0

  def prune(days) do
    cutoff = DateTime.add(DateTime.utc_now(:second), -days, :day)

    {count, _} =
      Repo.delete_all(
        from(b in Ban,
          where:
            (not is_nil(b.lifted_at) and b.lifted_at < ^cutoff) or
              (not is_nil(b.expires_at) and b.expires_at < ^cutoff)
        )
      )

    count
  end

  # ── Private ────────────────────────────────────────────────────────────────

  # The account hears of its own ban on its user topic; an IP has no one to tell.
  defp notify(:account, user_id, message),
    do: Gamend.Broadcast.best_effort("user:#{user_id}", message, "ban")

  defp notify(_kind, _subject, _message), do: :ok

  defp lift_rows(kind, subject, now, by) do
    rows =
      now
      |> active_query()
      |> where([b], b.kind == ^kind and b.subject == ^subject)
      |> Repo.all()

    if rows != [] do
      ids = Enum.map(rows, & &1.id)

      Repo.update_all(from(b in Ban, where: b.id in ^ids),
        set: [lifted_at: now, lifted_by: by, updated_at: now]
      )
    end

    Enum.map(rows, &%{&1 | lifted_at: now, lifted_by: by, updated_at: now})
  end

  defp active_query(now) do
    from(b in Ban, where: is_nil(b.lifted_at) and (is_nil(b.expires_at) or b.expires_at > ^now))
  end

  defp of_kind(query, nil), do: query
  defp of_kind(query, kind), do: where(query, [b], b.kind == ^kind)

  # A ban that ends before it starts would be stored and never apply.
  defp validate_future(changeset, now) do
    Ecto.Changeset.validate_change(changeset, :expires_at, fn :expires_at, expires_at ->
      if DateTime.after?(expires_at, now), do: [], else: [expires_at: "must be in the future"]
    end)
  end

  defp truncate(nil), do: nil
  defp truncate(%DateTime{} = at), do: DateTime.truncate(at, :second)
end
