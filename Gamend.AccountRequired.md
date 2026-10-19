# `Gamend.AccountRequired`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/account_required.ex#L1)

What a guest may not do until it registers. A guest is an account with no
email and no sign-in provider, only a device or a browser
(`Gamend.Accounts.User.anonymous?/1`). The host picks the features:

    config :gamend_core, Gamend.AccountRequired, [:quest_claims, :leaderboards]

Default: none, so a guest does everything a registered player does.

  * `:quest_claims` — `Gamend.Quests.claim/3` answers
    `{:error, :account_required}` (the API's 403 `account_required`), and
    an `auto_claim` quest does not pay itself. Progress still counts: a
    completed quest waits, and pays once the account is registered.
  * `:leaderboards` — a guest's records are kept but never listed on a
    public board (one not `hidden`): no list, count or rank includes them,
    so a guest moves nobody. Their own record still reads, ranked where it
    would stand, with `hidden: true` (`Gamend.Leaderboards.get_user_record/3`,
    the API's `GET …/me`). Registering lists them at once: each record
    keeps a `guest` flag that the database sets from the account and moves
    when the account gains its first identity (or loses its last).

Both apply in core, so every client meets the same rule; a client reads
the 403 or the `hidden` flag to say why and offer registration.

# `feature`

```elixir
@type feature() :: :quest_claims | :leaderboards
```

# `allowed?`

```elixir
@spec allowed?(
  Gamend.Accounts.User.t() | Gamend.Accounts.Scope.t() | Ecto.UUID.t() | nil,
  feature()
) ::
  boolean()
```

Whether this user (a `User`, a `Scope` or an id) may use `feature`:
always when the host does not require an account for it, else only a
registered account. An unknown id may not.

# `features`

```elixir
@spec features() :: [feature()]
```

The features a host can require an account for.

# `required?`

```elixir
@spec required?(feature()) :: boolean()
```

Whether the host requires an account for `feature`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
