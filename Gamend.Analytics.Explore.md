# `Gamend.Analytics.Explore`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/analytics/explore.ex#L1)

Reading the event rows (`analytics_events`) one question at a time: one
event, a group of them or all, over a range of UTC days, in one segment
(`Gamend.Analytics.Segment`), narrowed by any of the events' dimensions
(`lang = ro`, `mode = daily`) or to one account. The admin Analytics
pages' Explore and People tabs are built on it.

A filter is a map (`filter/1` fills the defaults):

    %{names: ["web.game.finished"] | :all, from: ~D[…], to: ~D[…],
      segment: :all, where: %{"lang" => "ro"}, user_id: nil}

A `where` value of `"none"` matches the events without that field, the
way a breakdown names them.

Rows are an account's only (a visitor's event is a counter), so every
number here is about accounts. `counter_series/4` reads the counters,
where everyone is, for the same event.

# `filter`

```elixir
@type filter() :: %{
  names: [String.t()] | :all,
  from: Date.t(),
  to: Date.t(),
  segment: Gamend.Analytics.Segment.t(),
  where: %{required(String.t()) =&gt; String.t()},
  user_id: String.t() | nil
}
```

# `active_days`

```elixir
@spec active_days(String.t(), Date.t(), Date.t()) :: MapSet.t(Date.t())
```

The days `user_id` was seen in `from..to`, as a set of dates.

# `breakdown`

```elixir
@spec breakdown(filter(), String.t(), keyword()) :: [map()]
```

The filter's events by the values of one dimension, most people first:
`[%{value, events, people, measures: %{m => avg}, rates: %{label => r}}]`.
A row without the field is `"none"`. Options: `measures:` (field names to
average), `rates:` (`{numerator, denominator, label}`: the sum of one
over the sum of the other, a score over its questions).

# `counter_series`

```elixir
@spec counter_series(filter()) :: [%{day: Date.t(), count: integer()}] | nil
```

The daily counter behind an event, everyone included, for the filter's
days: the bare name with no `where`, `name.dim:value` with one, nil with
more (no counter holds two dimensions at once) or with several names.

# `filter`

```elixir
@spec filter(keyword()) :: filter()
```

A filter from options: `names:` (default `:all`), `to:` (default today),
`from:` or `days:` (default 30, ending on `to`), `segment:`, `where:`,
`user_id:`.

# `measures`

```elixir
@spec measures(filter(), keyword()) :: %{measures: map(), rates: map()}
```

The filter's whole-range averages and rates, as `breakdown/3` computes
them per value: `%{measures: %{m => avg}, rates: %{label => r}}`.

# `names`

```elixir
@spec names(pos_integer(), Date.t()) :: [{String.t(), non_neg_integer()}]
```

The event names with a row in the last `days` days ending on `to`, by how
many rows, most first: `[{name, events}]`.

# `person`

```elixir
@spec person(String.t(), Date.t()) :: map()
```

What one account has done: `%{first_day, last_day, days_active,
days_active_30, events, by_name}` — its activity days (all of them, and
in the last 30), its event rows, and those by name (`[%{name, events,
last_at}]`, most first).

# `rows`

```elixir
@spec rows(filter(), keyword()) :: %{
  rows: [Gamend.Analytics.Event.t()],
  total: non_neg_integer()
}
```

One page of the filter's rows, newest first, each with its account
(`user`, nil once the account is deleted): `%{rows, total}`. Options:
`page:` (from 1), `page_size:` (default 50).

# `series`

```elixir
@spec series(filter()) :: [%{day: Date.t(), events: integer(), people: integer()}]
```

Every day of the filter's range: `[%{day, events, people}]`, oldest first.

# `totals`

```elixir
@spec totals(filter()) :: %{events: integer(), people: integer()}
```

The filter's events and distinct people.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
