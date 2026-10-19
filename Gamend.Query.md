# `Gamend.Query`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/query.ex#L1)

Query-building pieces shared by the contexts. Right now: paging.

## Why this exists

Seven contexts each carried a private `paginate/2`, in four different
behaviours. Three (`quests`, `economy`, `inventory`) read `:page_size`
straight out of the options and applied it, so `list_ledger(page_size:
1_000_000)` was a single unbounded read. Two (`groups`, `lobbies`) clamped —
to a hard-coded `@max_page_size 1000` that ignored the configurable
`max_page_size` limit entirely. Two (`matchmaking`, `ready_checks`) clamped
correctly through `Gamend.Limits`.

`GamendWeb.Pagination` already fixed the same drift one layer up, and
`mix gamend.api.lint` keeps controllers honest — but nothing was watching
the contexts, and a plugin calls them directly. Both functions here clamp
through `Gamend.Limits`, so the configured maximum is the maximum wherever
the call came from.

## Which one

`page/2` always windows: the caller is paging, and no `:page` just means the
first one. `maybe_page/2` windows only when asked, and otherwise bounds the
read at `unpaginated_limit/0` — for a listing whose callers legitimately want
"all of them", where "all" must still not mean an unbounded `Repo.all` over a
growing table.

# `filter_id`

```elixir
@spec filter_id(Ecto.Queryable.t(), atom(), String.t() | nil) :: Ecto.Queryable.t()
```

The rows whose `field` is exactly the id `value`.

For a caller holding an id rather than a search term -- a plugin scoping a
read by user or lobby, a link from another page. `nil` and `""` leave the
query alone. A value that is not a UUID matches nothing: it arrives in
request params, where comparing it raised `Ecto.Query.CastError`, and
ignoring it instead would answer every row to a filter plainly meant to
narrow them. KV did the first and push the second.

See `filter_user/2` for the admin search that also matches names.

# `filter_user`

```elixir
@spec filter_user(Ecto.Queryable.t(), String.t() | nil) :: Ecto.Queryable.t()
```

Narrows a query over a table with a `user_id` column to one user, found by
exact id or by a substring of their username or display name — so an admin
can filter a list without knowing the raw id.

`nil` leaves the query alone. Economy, inventory and quests each carried an
identical private copy of this.

# `filter_user_named`

```elixir
@spec filter_user_named(Ecto.Queryable.t(), atom(), String.t()) :: Ecto.Query.t()
```

Narrows `query` to the rows whose `field` holds a player named by
`pattern` (`users_named/1`): by their ids when few, else joined to the
names as `:named_user`.

# `maybe_page`

```elixir
@spec maybe_page(Ecto.Queryable.t(), keyword()) :: Ecto.Query.t()
```

Applies the window when `:page` is given, and otherwise caps the read at
`unpaginated_limit/0`.

# `name_match`

```elixir
@spec name_match(String.t(), atom()) :: Ecto.Query.dynamic_expr()
```

The condition a player search reads, on a user bound as `binding`
(`:named_user`): the expressions the trigram indexes cover.

# `page`

```elixir
@spec page(Ecto.Queryable.t(), keyword()) :: Ecto.Query.t()
```

Applies `:page` and `:page_size`, both clamped, defaulting to the first page.

    Query.page(query, page: 2, page_size: 50)

# `unpaginated_limit`

```elixir
@spec unpaginated_limit() :: pos_integer()
```

The ceiling applied to a read that requested no page.

# `users_named`

```elixir
@spec users_named(String.t()) :: {:few, [Ecto.UUID.t()]} | :many
```

The users whose username or display name holds `pattern` (a
`Repo.search_pattern/1`): `{:few, ids}` when at most 500 do,
`:many` past that.

Every player search across a big table goes through it: when a term names
few players, the table is read by their ids, through its index; when it
names many, the caller reads the table in its own order, joined to the
names, and stops at a page. Joining every row to the names first read a
whole leaderboard or member list per search, 0.5 s at 100,000 rows. On
Postgres the names are found through their trigram indexes
(`UserNameTrigramIndexes`).

---

*Consult [api-reference.md](api-reference.md) for complete listing*
