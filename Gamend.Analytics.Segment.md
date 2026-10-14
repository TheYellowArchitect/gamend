# `Gamend.Analytics.Segment`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/analytics/segment.ex#L1)

The ways the people numbers split: `:all`, `:registered` (an account with
an identity: an email, a provider) and `:guest` (an account backed by
nothing but a device or a browser, `Gamend.Accounts.User.anonymous?/1`).
A visitor with no account is in none of them: the daily counters count
them, no row does.

The split is by what the account is NOW, so a guest who registers later
reads as registered on the days before too: a guest's numbers are the
guests who stayed guests.

# `t`

```elixir
@type t() :: :all | :registered | :guest
```

# `all`

```elixir
@spec all() :: [t()]
```

Every segment, `:all` first.

# `condition`

```elixir
@spec condition(:registered | :guest) :: Ecto.Query.dynamic_expr()
```

The `where` for one segment over a `:user` binding.

# `label`

```elixir
@spec label(t()) :: String.t()
```

How a page names it.

# `parse`

```elixir
@spec parse(term()) :: t()
```

A segment from a request parameter (`"guest"`); anything else is `:all`.

# `restrict`

```elixir
@spec restrict(Ecto.Queryable.t(), t()) :: Ecto.Query.t()
```

Restricts `query` to one segment: a query on a table with a `user_id` is
joined to `users` (as `:user`); a query that already has a `:user` binding
(`users` itself, `as: :user`) is filtered on it.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
