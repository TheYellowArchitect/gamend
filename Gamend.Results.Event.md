# `Gamend.Results.Event`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/results/event.ex#L1)

Ecto schema for `result_events`: one thing that happened in a play
(`Gamend.Results.record/4`).

Its `id` is its place: UUIDv7 ids are strictly ordered on a node, so a
result's events sorted by id are the order they were written in.
`elapsed_ms` is the time into the play, on the server's clock. `key` says
what happened, `value` the number it carries (summed by
`Gamend.Results.stats/1`), `metadata` anything else.

# `t`

```elixir
@type t() :: %Gamend.Results.Event{
  __meta__: term(),
  elapsed_ms: term(),
  id: term(),
  key: term(),
  metadata: term(),
  result: term(),
  result_id: term(),
  value: term()
}
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
