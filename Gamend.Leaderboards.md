# `Gamend.Leaderboards`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/leaderboards.ex#L1)

The Leaderboards context.

Provides server-authoritative leaderboard management. Scores can only be
submitted via server-side code — there is no public API for score submission.

## Usage

    # Create a leaderboard
    {:ok, lb} = Leaderboards.create_leaderboard(%{
      slug: "weekly_kills",
      title: "Weekly Kills",
      sort_order: :desc,
      operator: :incr
    })

    # Submit score (server-only): resolve the active leaderboard first and submit by ID
    leaderboard = Leaderboards.get_active_leaderboard_by_slug("weekly_kills")
    {:ok, record} = Leaderboards.submit_score(leaderboard.id, user_id, 10)

    # List records with rank (use leaderboard id)
    records = Leaderboards.list_records(leaderboard.id, page: 1, limit: 25)

## Keys

A board can hold several rankings: a record is unique per user (or label)
and `key`, and every read ranks within one key. `""` is the default, a
board with one ranking. A host keeping, say, a best per game and language
on one board submits with `key: "match|60|es_es"` and metadata naming the
parts; `list_records/2` with `key: :all` and `meta:` reads across keys
(`best_per_user: true` keeps each player's best of them). `list_keys/2`
names the keys a board holds, and `list_records_above/3` the records just
ahead of a score on one key. A board can show its keys as tabs and
filters on `/leaderboards` (`GamendWeb.LeaderboardViews`).

## Hidden boards

`hidden: true` keeps a board out of `list_leaderboards/1`,
`list_leaderboard_groups/1` and their counts unless `include_hidden: true`
is passed. Everything else reads it like any board.

## Guests

When the host requires an account to be listed (`Gamend.AccountRequired`,
`:leaderboards`), a guest's records stay on a public board but out of every
read of it: lists, counts and ranks, so a guest moves nobody. The guest's
own `get_user_record/3` still answers, ranked where it would stand, with
`hidden: true`. A hidden board keeps its guests (it is no one's public
board), and `guests: true` reads them anyway (the admin's view).

    # Get user's record (use leaderboard id)
    {:ok, record} = Leaderboards.get_user_record(leaderboard.id, user_id)

# `change_leaderboard`

```elixir
@spec change_leaderboard(Gamend.Leaderboards.Leaderboard.t(), map()) ::
  Ecto.Changeset.t()
```

Returns a changeset for a leaderboard (used in forms).

# `change_record`

```elixir
@spec change_record(Gamend.Leaderboards.Record.t(), map()) :: Ecto.Changeset.t()
```

Returns a changeset for a record (used in admin forms).

# `count_all_records`

```elixir
@spec count_all_records() :: non_neg_integer()
```

Count all leaderboard records across all leaderboards.

# `count_leaderboard_groups`

```elixir
@spec count_leaderboard_groups(keyword()) :: non_neg_integer()
```

Counts unique leaderboard slugs.

# `count_leaderboards`

```elixir
@spec count_leaderboards(keyword()) :: non_neg_integer()
```

Counts leaderboards matching the given filters.

Accepts the same filter options as `list_leaderboards/1`.

# `count_records`

```elixir
@spec count_records(Ecto.UUID.t(), keyword()) :: non_neg_integer()
```

Counts records for a leaderboard: the same `:key`, `:meta`,
`:best_per_user` and `:search` as `list_records/2`.

# `create_leaderboard`

```elixir
@spec create_leaderboard(Gamend.Types.leaderboard_create_attrs()) ::
  {:ok, Gamend.Leaderboards.Leaderboard.t()} | {:error, Ecto.Changeset.t()}
```

Creates a new leaderboard.

## Attributes

See `t:Gamend.Types.leaderboard_create_attrs/0` for available fields.

## Examples

    iex> create_leaderboard(%{slug: "my_lb", title: "My Leaderboard"})
    {:ok, %Leaderboard{}}

    iex> create_leaderboard(%{slug: "", title: ""})
    {:error, %Ecto.Changeset{}}

# `delete_leaderboard`

```elixir
@spec delete_leaderboard(Gamend.Leaderboards.Leaderboard.t()) ::
  {:ok, Gamend.Leaderboards.Leaderboard.t()} | {:error, Ecto.Changeset.t()}
```

Deletes a leaderboard and all its records.

# `delete_record`

```elixir
@spec delete_record(Gamend.Leaderboards.Record.t()) ::
  {:ok, Gamend.Leaderboards.Record.t()} | {:error, Ecto.Changeset.t()}
```

Deletes a record.

# `delete_user_record`

```elixir
@spec delete_user_record(String.t(), Ecto.UUID.t(), keyword()) ::
  {:ok, Gamend.Leaderboards.Record.t()} | {:error, :not_found}
```

Deletes a user's record from a leaderboard (in `key:`, default `""`).
Accepts either leaderboard ID or slug (both strings).

# `end_leaderboard`

```elixir
@spec end_leaderboard(Gamend.Leaderboards.Leaderboard.t() | String.t()) ::
  {:ok, Gamend.Leaderboards.Leaderboard.t()}
  | {:error, Ecto.Changeset.t() | :not_found}
```

Ends a leaderboard by setting `ends_at` to the current time.

# `get_active_leaderboard_by_slug`

```elixir
@spec get_active_leaderboard_by_slug(String.t()) ::
  Gamend.Leaderboards.Leaderboard.t() | nil
```

Gets the currently active leaderboard with the given slug.
Returns `nil` if no active leaderboard exists.

An active leaderboard is one that:
- Has not ended (`ends_at` is nil or in the future)
- Has started (`starts_at` is nil or in the past)

If multiple active leaderboards exist with the same slug,
returns the most recently created one.

# `get_label_record`

```elixir
@spec get_label_record(Ecto.UUID.t(), String.t(), String.t()) ::
  Gamend.Leaderboards.Record.t() | nil
```

Gets a single record by leaderboard ID, label and key (default `""`).

# `get_leaderboard`

```elixir
@spec get_leaderboard(String.t()) :: Gamend.Leaderboards.Leaderboard.t() | nil
```

Gets a leaderboard by its UUID, or the active leaderboard by slug.

## Examples

    iex> get_leaderboard("0198c0de-...")
    %Leaderboard{}

    iex> get_leaderboard(Ecto.UUID.generate())
    nil

# `get_leaderboard!`

```elixir
@spec get_leaderboard!(String.t()) :: Gamend.Leaderboards.Leaderboard.t()
```

Gets a leaderboard by its ID. Raises if not found.

# `get_record`

```elixir
@spec get_record(Ecto.UUID.t()) :: Gamend.Leaderboards.Record.t() | nil
```

Gets a record by its ID, or `nil` when there is none (or `id` is not a UUID).

Intended for internal/admin usage.

# `get_record`

```elixir
@spec get_record(Ecto.UUID.t(), Ecto.UUID.t(), String.t()) ::
  Gamend.Leaderboards.Record.t() | nil
```

Gets a single record by leaderboard ID, user ID and key (default `""`).

# `get_record!`

```elixir
@spec get_record!(Ecto.UUID.t()) :: Gamend.Leaderboards.Record.t()
```

Like `get_record/1`, but raises `Ecto.NoResultsError` when there is none.

# `get_user_record`

```elixir
@spec get_user_record(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
  {:ok, Gamend.Leaderboards.Record.t()} | {:error, :not_found}
```

Gets a user's record with their rank (within its key: `key:`, default `""`).
Returns `{:ok, record_with_rank}` or `{:error, :not_found}`.

# `host_action`

```elixir
@spec host_action(String.t(), Ecto.UUID.t() | nil) :: {String.t(), String.t()} | nil
```

Where a board is climbed, for the button on its page and its card:
`{label, path}`, or nil. Set `config :gamend_core, :leaderboard_action,
{Module, :function}`; it is called as `function(user_id | nil, slug)` and
answers `{label, path}` (the label already in the reader's language) or nil.

A board only says what it counts ("Most kilometers sailed"), never where
that is done, and only the host knows its own pages, as with a quest
(`Gamend.Quests.host_action/2`). A path starts with one `/` (`"/games"`); a
URL or `"//…"` is dropped. The page keeps the reader's locale prefix on it.

# `invalidate_cache`

```elixir
@spec invalidate_cache() :: :ok
```

Forget the cached leaderboard lookups.

Every write in here does this already. It is public because a CALLER can also
learn the cache is stale: `get_active_leaderboard_by_slug/1` is cached for a
minute, so a board deleted (or rolled back, under a test sandbox) hands out an
id whose row is gone, and the next `submit_score/4` fails on the foreign key.
A caller that sees that can drop the lookup and try again rather than wait out
the TTL.

# `list_keys`

```elixir
@spec list_keys(String.t(), keyword()) :: [String.t()]
```

The keys a board holds, sorted, from its listed records; with `prefix:`
only the keys starting with it (`"match|"`: every language Word match has
runs in). A key only guests have played is not offered.

# `list_leaderboard_groups`

```elixir
@spec list_leaderboard_groups(keyword()) :: [map()]
```

Lists unique leaderboard slugs with summary info.

Returns a list of maps with:
- `:slug` - the leaderboard slug
- `:title` - title from the latest leaderboard
- `:description` - description from the latest leaderboard
- `:active_id` - ID of the currently active leaderboard (or nil)
- `:latest_id` - ID of the most recent leaderboard
- `:season_count` - total number of leaderboards with this slug

# `list_leaderboards`

```elixir
@spec list_leaderboards(keyword()) :: [Gamend.Leaderboards.Leaderboard.t()]
```

Lists leaderboards with optional filters.

## Options

  * `:slug` - Filter by slug (returns all seasons of that leaderboard)
  * `:active` - If `true`, only active leaderboards. If `false`, only ended.
  * `:order_by` - Order by field: `:ends_at` or `:inserted_at` (default)
  * `:starts_after` - Only leaderboards that started after this DateTime
  * `:starts_before` - Only leaderboards that started before this DateTime
  * `:ends_after` - Only leaderboards that end after this DateTime
  * `:ends_before` - Only leaderboards that end before this DateTime
  * `:include_hidden` - Also hidden boards (default false)
  * `:page` - Page number (default 1)
  * `:page_size` - Page size (default 25)

## Examples

    iex> list_leaderboards(active: true)
    [%Leaderboard{}, ...]

    iex> list_leaderboards(slug: "weekly_kills")
    [%Leaderboard{}, ...]

    iex> list_leaderboards(starts_after: ~U[2025-01-01 00:00:00Z])
    [%Leaderboard{}, ...]

# `list_leaderboards_by_slug`

```elixir
@spec list_leaderboards_by_slug(String.t(), keyword()) :: [
  Gamend.Leaderboards.Leaderboard.t()
]
```

Lists all leaderboards with the given slug (all seasons), ordered by end date.

# `list_records`

```elixir
@spec list_records(String.t(), keyword()) :: [Gamend.Leaderboards.Record.t()]
```

Lists records for a leaderboard, ordered by rank.

## Options

See `t:Gamend.Types.pagination_opts/0` for available options, plus:

  * `:key` — the ranking to read (default `""`), or `:all` for every key's
    rows ranked together.
  * `:meta` — a map, keeping only records whose `metadata[field]` equals
    each value (`%{"game" => "match", "lang" => "es_es"}`). Ranks are
    computed **within** the filtered set, because "the Spanish board" means
    first among Spanish, not 57th overall. That is the opposite of
    `:search`, which ranks over the whole key so a found player's real
    position is what shows.
  * `:best_per_user` — with `key: :all`, each player's (or label's) best
    row only: one board read across keys, a player once.
  * `:guests` — `true` lists guests' records on a public board too, when
    the host keeps them off it (`Gamend.AccountRequired`): the admin's view.

# `list_records_above`

```elixir
@spec list_records_above(String.t(), integer(), keyword()) :: [
  Gamend.Leaderboards.Record.t()
]
```

The listed records just ahead of `score` on one key, nearest first: the
runs a player at that score would overtake next. Ahead means a strictly
better score (higher on a `:desc` board, lower on an `:asc` one), so a tie
is not ahead. Each record carries its `rank`.

It needs no record of the caller's: a first-timer reads it with their
first score, and a guest with theirs, though a guest's own record is not
listed (`Gamend.AccountRequired`). `list_records_around_user/3` needs the
caller on the board. Labels' records are listed, like any.

## Options

  * `:key` — the ranking (default `""`)
  * `:limit` — how many (default 3)

# `list_records_around_user`

```elixir
@spec list_records_around_user(String.t(), Ecto.UUID.t(), keyword()) :: [
  Gamend.Leaderboards.Record.t()
]
```

Lists records around a specific user (centered on their position).

Returns records above and below the user's rank.

## Options

  * `:limit` - Total number of records to return (default 11, centered on user)
  * `:key` - The ranking (default `""`)

# `resolve_slugs`

```elixir
@spec resolve_slugs([String.t()]) :: %{
  required(String.t()) =&gt; Gamend.Leaderboards.Leaderboard.t()
}
```

Resolves multiple slugs to their currently active leaderboards in a single query.

Returns a map of `slug => %Leaderboard{}` for each slug that has an active
leaderboard. Slugs with no active leaderboard are omitted from the result.

## Examples

    iex> resolve_slugs(["weekly_kills", "monthly_score", "nonexistent"])
    %{
      "weekly_kills" => %Leaderboard{id: 1, slug: "weekly_kills", ...},
      "monthly_score" => %Leaderboard{id: 5, slug: "monthly_score", ...}
    }

# `submit_label_score`

```elixir
@spec submit_label_score(String.t(), String.t(), integer(), map(), keyword()) ::
  {:ok, Gamend.Leaderboards.Record.t()} | {:error, term()}
```

Submit a score for a label-based (non-user) record.

Works just like `submit_score/4` but uses a string label instead of a user ID.
This is useful for statistics, rankings by category, etc.

## Examples

    iex> submit_label_score(leaderboard_id, "English", 42)
    {:ok, %Record{label: "English", score: 42}}

# `submit_score`

```elixir
@spec submit_score(String.t(), Ecto.UUID.t(), integer(), map(), keyword()) ::
  {:ok, Gamend.Leaderboards.Record.t()} | {:error, term()}
```

Submits a score for a user on a leaderboard.

This is a server-only function — there is no public API for score submission.
The score is processed according to the leaderboard's operator:

  * `:set` — Always replace with new score
  * `:best` — Only update if new score is better (respects sort_order)
  * `:incr` — Add to existing score
  * `:decr` — Subtract from existing score

To submit to a leaderboard by slug, first get the active leaderboard ID:

    leaderboard = Leaderboards.get_active_leaderboard_by_slug("weekly_kills")
    Leaderboards.submit_score(leaderboard.id, user_id, 10)

## Examples

    iex> submit_score(123, user_id, 10)
    {:ok, %Record{score: 10}}

    iex> submit_score(123, user_id, 5, %{weapon: "sword"})
    {:ok, %Record{score: 15, metadata: %{weapon: "sword"}}}

`key:` (default `""`) is the ranking within the board the score goes to;
the operator applies per key.

    iex> submit_score(123, user_id, 23, %{"game" => "match"}, key: "match|60")
    {:ok, %Record{key: "match|60", score: 23}}

# `update_leaderboard`

```elixir
@spec update_leaderboard(
  Gamend.Leaderboards.Leaderboard.t(),
  Gamend.Types.leaderboard_update_attrs()
) ::
  {:ok, Gamend.Leaderboards.Leaderboard.t()} | {:error, Ecto.Changeset.t()}
```

Updates an existing leaderboard.

Note: `slug`, `sort_order`, and `operator` cannot be changed after creation.

## Attributes

See `t:Gamend.Types.leaderboard_update_attrs/0` for available fields.

# `update_record`

```elixir
@spec update_record(Gamend.Leaderboards.Record.t(), map()) ::
  {:ok, Gamend.Leaderboards.Record.t()} | {:error, Ecto.Changeset.t()}
```

Updates an existing record.

Intended for internal/admin usage.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
