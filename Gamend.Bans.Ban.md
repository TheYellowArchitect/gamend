# `Gamend.Bans.Ban`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/bans/ban.ex#L1)

One ban: an IP address, an account or a chat sender kept out until
`expires_at` (`nil` is permanent), or until someone lifts it.

A row is kept after it ends, lifted or expired, so a target's history reads
as its rows; retention deletes ended rows after `bans_days`. A ban is active
while `lifted_at` is nil and `expires_at` is nil or still ahead.

  * `kind` — `:ip` (`subject` is the address, an IPv6 one as its /64),
    `:account` (`subject` is the user id, also in `user_id`) or `:chat`, a
    mute (`subject` and `user_id` are the muted player).
  * `scope` / `scope_ref_id` — a chat ban's reach: `"global"` (every chat,
    friend DMs included; no room id) or `"lobby"`, `"group"` or `"party"`
    with that room's id. Nil for the other kinds.
  * `reason` — why, in the words the banned player is shown.
  * `source` — who placed it: `:admin` (the admin pages), `:api` (the admin
    API), `:room` (a lobby host, group admin or party leader, in their own
    room), `:plugin` (a game hook) or `:system`.
  * `banned_by` / `lifted_by` — the person who placed or lifted it, when one did.

# `kind`

```elixir
@type kind() :: :ip | :account | :chat
```

# `t`

```elixir
@type t() :: %Gamend.Bans.Ban{
  __meta__: term(),
  banned_by: term(),
  banned_by_user: term(),
  expires_at: term(),
  id: term(),
  inserted_at: term(),
  kind: term(),
  lifted_at: term(),
  lifted_by: term(),
  lifted_by_user: term(),
  reason: term(),
  scope: term(),
  scope_ref_id: term(),
  source: term(),
  subject: term(),
  updated_at: term(),
  user: term(),
  user_id: term()
}
```

# `kinds`

```elixir
@spec kinds() :: [kind()]
```

The kinds of ban.

# `scopes`

```elixir
@spec scopes() :: [String.t()]
```

The reaches a chat ban may have.

# `sources`

```elixir
@spec sources() :: [atom()]
```

Who may place a ban.

# `target`

```elixir
@spec target(t()) :: tuple()
```

`target/4` of a ban.

# `target`

```elixir
@spec target(kind(), String.t(), String.t() | nil, String.t() | nil) :: tuple()
```

The key a ban is cached and replaced under: `{kind, subject, scope}`, the
scope nil for an IP or account ban, `"global"` or `{room_kind, room_id}` for
a chat ban.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
