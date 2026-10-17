# `Gamend.Bans`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/bans.ex#L1)

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

# `account_ban`

```elixir
@spec account_ban(String.t()) :: Gamend.Bans.Ban.t() | nil
```

The active ban on an account, or nil. Queries only when the cache holds one,
so it is cheap to ask on every request.

# `active`

```elixir
@spec active(Gamend.Bans.Ban.kind(), String.t()) :: Gamend.Bans.Ban.t() | nil
```

The active ban on `subject`, or nil: for showing its end and reason.

# `active?`

```elixir
@spec active?(Gamend.Bans.Ban.t()) :: boolean()
```

Whether `ban` is in force now.

# `ban`

```elixir
@spec ban(Gamend.Bans.Ban.kind(), String.t(), keyword()) ::
  {:ok, Gamend.Bans.Ban.t()} | {:error, Ecto.Changeset.t()}
```

Bans `subject` until `:expires_at` (a `DateTime`, `nil` for permanent).

Options: `:expires_at`, `:reason` (shown to the banned player), `:source`
(`:admin` by default, see `Gamend.Bans.Ban`) and `:by` (the admin's user id).
The ban applies on this instance at once and on the others within moments.

# `banned?`

```elixir
@spec banned?(Gamend.Bans.Ban.kind(), String.t()) :: boolean()
```

Whether `subject` is banned now: an ETS read, no query.

# `expires_after`

```elixir
@spec expires_after(non_neg_integer() | :infinity) :: DateTime.t() | nil
```

The `expires_at` for a ban lasting `ttl_ms` from now; nil for `:infinity`.

# `history`

```elixir
@spec history(Gamend.Bans.Ban.kind() | nil, keyword()) :: [Gamend.Bans.Ban.t()]
```

Bans of one kind or all, ended ones too, newest first. `:limit` (100) caps it.

# `lift`

```elixir
@spec lift(Gamend.Bans.Ban.kind(), String.t(), keyword()) ::
  {:ok, [Gamend.Bans.Ban.t()]}
```

Ends the active ban on `subject`, if it has one. `:by` is the admin's user id.
Answers the bans it ended (none, or one).

# `list_active`

```elixir
@spec list_active(Gamend.Bans.Ban.kind() | nil) :: [Gamend.Bans.Ban.t()]
```

Every active ban, of one kind or all, newest first.

# `prune`

```elixir
@spec prune(integer()) :: non_neg_integer()
```

Deletes bans that ended (lifted or expired) more than `days` ago; an active
ban is never deleted. `days` of 0 keeps them all. Answers the rows deleted.
Run by `Gamend.Retention` with `bans_days`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
