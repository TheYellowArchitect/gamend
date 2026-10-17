# `Gamend.Leaderboards.Record`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/leaderboards/record.ex#L1)

Ecto schema for the `leaderboard_records` table.

A record represents a single score entry in a leaderboard.
Records can be either **user-based** (one per user per leaderboard)
or **label-based** (one per label per leaderboard, no user required).

- User-based: `user_id` is set, `label` is nil. Uniqueness on `(leaderboard_id, user_id, key)`.
- Label-based: `label` is set, `user_id` is nil. Uniqueness on `(leaderboard_id, label, key)`.

`key` splits a board into separate rankings: one record per user (or
label) per key, each key ranked on its own. `""`, the default, is a board
with one ranking. The record's metadata says what its key stands for.

# `t`

```elixir
@type t() :: %Gamend.Leaderboards.Record{
  __meta__: term(),
  hidden: term(),
  id: term(),
  inserted_at: term(),
  key: term(),
  label: term(),
  leaderboard: term(),
  leaderboard_id: term(),
  metadata: term(),
  rank: term(),
  score: term(),
  updated_at: term(),
  user: term(),
  user_id: term()
}
```

# `changeset`

Changeset for creating a new record.
Either `user_id` or `label` must be provided (but not both).

# `update_changeset`

Changeset for updating an existing record's score.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
