# `Gamend.Analytics.Event`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/analytics/event.ex#L1)

One thing a player did, with who and when: `name` (`"web.game.finished"`),
`dims` (its fields — language, game, score — as a map with string keys),
`user_id` (nil for a visitor, nulled when the account is deleted) and
`inserted_at`, the moment it happened. Written by `Gamend.Analytics.track/3`
through `Gamend.Analytics.Buffer`, in batches, never one row at a time.

The daily counters (`Gamend.Analytics.DailyCount`) hold the same events
summed per day and per dimension, forever; these rows are what answers the
questions a sum cannot (distinct people, order, combinations) and are
pruned after `GAMEND_RETENTION_ANALYTICS_EVENTS_DAYS`.

# `t`

```elixir
@type t() :: %Gamend.Analytics.Event{
  __meta__: term(),
  dims: term(),
  id: term(),
  inserted_at: term(),
  name: term(),
  user: term(),
  user_id: term()
}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
