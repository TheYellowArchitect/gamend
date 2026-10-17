# `Gamend.Bans.Ban`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/bans/ban.ex#L1)

One ban: an IP address or an account kept out until `expires_at` (`nil` is
permanent), or until an admin lifts it.

A row is kept after it ends, lifted or expired, so a target's history reads
as its rows; retention deletes ended rows after `bans_days`. A ban is active
while `lifted_at` is nil and `expires_at` is nil or still ahead.

  * `kind` — `:ip` (`subject` is the address, an IPv6 one as its /64) or
    `:account` (`subject` is the user id, also in `user_id`).
  * `reason` — why, in the words the banned player is shown.
  * `source` — who placed it: `:admin` (the admin pages), `:api` (the admin
    API), `:plugin` (a game hook) or `:system`.
  * `banned_by` / `lifted_by` — the admin who placed or lifted it, when one did.

# `kind`

```elixir
@type kind() :: :ip | :account
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

# `sources`

```elixir
@spec sources() :: [atom()]
```

Who may place a ban.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
