# `Gamend.Bans`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/bans.ex#L1)

Bans: an IP address, an account or a chat sender kept out for a while, or
for good.

The `bans` table is the source of truth and keeps every ban after it ends,
so a target's history is its rows. `Gamend.Bans.Cache` holds the active ones
in ETS for the per-request check (`banned?/2`), and carries each change to
the other instances over PubSub (`Gamend.Bans.Sync` applies them there and
loads the table at boot).

Placing a ban on a target that already has one ends the old one (lifted by
whoever placed the new one) and starts the new one, so a target has at most
one active ban. A target is the kind, the subject and, for a chat ban, its
reach (`Gamend.Bans.Ban.target/4`): a global mute and a mute in one lobby are
two targets.

    Gamend.Bans.ban(:ip, "1.2.3.4", expires_at: Gamend.Bans.expires_after(:timer.hours(24)))
    Gamend.Bans.ban(:account, user.id, expires_at: in_a_week, reason: "Cheating", by: admin.id)
    Gamend.Bans.ban(:chat, user.id, scope: "lobby", scope_ref_id: lobby.id, source: :room)
    Gamend.Bans.lift(:account, user.id, by: admin.id)
    Gamend.Bans.banned?(:ip, "1.2.3.4")

An IP ban's subject is the address as the web layer keys it (an IPv6 one as
its /64, `GamendWeb.Plugs.IpBan`); an account or chat ban's is the user id.

## Chat bans (mutes)

A chat ban silences a sender everywhere (`scope: "global"`, friend DMs
included) or in one lobby, group or party (`scope` and `scope_ref_id`).
`Gamend.Chat.mute_user/4` and `unmute_user/3` are chat's way in, with the
room rules; `muted?/3` is the per-message check. Placing and lifting one
tells the player `{:chat_muted, ban}` and `{:chat_unmuted, ...}`, the user
channel's `chat_muted` and `chat_unmuted`.

## Account bans

A banned account still signs in, and can read and delete itself; everything
else refuses it (the web layer: `GamendWeb.Plugs.AccountBan` on the API, the
channels, `GamendWeb.UserAuth` on the website). Placing and lifting one
tells the account on its user topic, `{:account_banned, ban}` and
`{:account_unbanned, user_id}`, which the user channel passes on as the
`account_banned` and `account_unbanned` events.

## Hooks and plugins

A plugin bans and lifts with these functions (`source: :plugin`), and hears
of every ban through two fire-and-forget hooks: `after_ban_created/1`, and
`after_ban_lifted/1` once for every ban that ends, lifted, replaced or
expired. A ban with an end schedules a job for it (`Gamend.Bans.ExpiryWorker`),
so an expiry is told like a lift: the hook, and `account_unbanned` or
`chat_unmuted`.

# `account_ban`

```elixir
@spec account_ban(String.t()) :: Gamend.Bans.Ban.t() | nil
```

The active ban on an account, or nil. Queries only when the cache holds one,
so it is cheap to ask on every request.

# `active`

```elixir
@spec active(Gamend.Bans.Ban.kind(), String.t(), keyword()) ::
  Gamend.Bans.Ban.t() | nil
```

The active ban on `subject`, or nil: for showing its end and reason. A chat
ban names its reach with `:scope` and `:scope_ref_id`.

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

Options: `:expires_at` (a `DateTime` or an ISO 8601 string), `:reason`
(shown to the banned player), `:source` (`:admin` by default, see
`Gamend.Bans.Ban`), `:by` (the person's user id), and for a chat ban
`:scope` and `:scope_ref_id`. The ban applies on this instance at once and on
the others within moments.

An account ban needs an existing user that is not an admin: banning an admin
would let one admin lock another (or themselves) out of the console.

# `banned?`

```elixir
@spec banned?(Gamend.Bans.Ban.kind(), String.t()) :: boolean()
```

Whether an IP or account `subject` is banned now: an ETS read, no query.

# `banned_user_ids`

```elixir
@spec banned_user_ids() :: Ecto.Query.t()
```

The ids of the accounts banned now, as a subquery: `Gamend.Accounts.Search`'s `banned` facet.

# `count`

```elixir
@spec count(map()) :: non_neg_integer()
```

How many bans `list/2` would page through.

# `expire`

```elixir
@spec expire(Gamend.Bans.Ban.t()) :: :ok | :noop | {:not_yet, pos_integer()}
```

Tells of a ban that ran out: drops it from the cache, tells the player
(`account_unbanned`, `chat_unmuted`) and runs `after_ban_lifted/1`. Run by
`Gamend.Bans.ExpiryWorker` at `expires_at`. `:noop` for a ban lifted or
replaced first (that already told), `{:not_yet, seconds}` for one still in
force.

# `expires_after`

```elixir
@spec expires_after(non_neg_integer() | :infinity) :: DateTime.t() | nil
```

The `expires_at` for a ban lasting `ttl_ms` from now; nil for `:infinity`.

# `get`

```elixir
@spec get(Ecto.UUID.t()) :: Gamend.Bans.Ban.t() | nil
```

One ban, with its users, or nil.

# `lift`

```elixir
@spec lift(Gamend.Bans.Ban.kind(), String.t(), keyword()) ::
  {:ok, [Gamend.Bans.Ban.t()]}
```

Ends the active ban on `subject`, if it has one. `:by` is the person's user
id; a chat ban names its reach with `:scope` and `:scope_ref_id`. Answers the
bans it ended (none, or one).

# `lift_ban`

```elixir
@spec lift_ban(Gamend.Bans.Ban.t(), keyword()) :: {:ok, [Gamend.Bans.Ban.t()]}
```

Ends this ban's target's active ban: the ban itself while it is in force (a
target banned again since has a newer one, which this lifts). `opts` as for
`lift/3`: `:by`.

# `list`

```elixir
@spec list(map(), keyword()) :: [Gamend.Bans.Ban.t()]
```

Bans, ended ones too, newest first, with the banned user and the people who
placed and lifted them. Filters (string or atom keys): `kind` (`:ip`,
`:account` or `:chat`, or the string), `user_id`, `subject`, `scope`,
`scope_ref_id`, and `active` (true: only the bans in force). `opts` are
`Gamend.Query.page/2`'s: `page`, `page_size`.

# `list_active`

```elixir
@spec list_active(Gamend.Bans.Ban.kind() | nil) :: [Gamend.Bans.Ban.t()]
```

Every active ban, of one kind or all, newest first.

# `muted?`

```elixir
@spec muted?(String.t(), String.t() | nil, String.t() | nil) :: boolean()
```

Whether `user_id` may not send in this chat: muted everywhere, or in this
lobby, group or party. An ETS read, run on every outgoing message.

# `prune`

```elixir
@spec prune(integer()) :: non_neg_integer()
```

Deletes bans that ended (lifted or expired) more than `days` ago; an active
ban is never deleted. `days` of 0 keeps them all. Answers the rows deleted.
Run by `Gamend.Retention` with `bans_days`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
