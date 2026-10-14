# `Gamend.Analytics.Catalog`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/analytics/catalog.ex#L1)

What the analytics a game reports MEAN: which events and counters there
are, what each is called, which group it belongs to, which of its fields
are dimensions (a closed set to filter and break down by) and which are
numbers (to average). The admin Analytics pages read it to group, label
and offer filters; nothing is stored by it.

A host declares its own with a module implementing this behaviour:

    config :gamend_core, :analytics_catalog, MyGame.Analytics

    @impl Gamend.Analytics.Catalog
    def groups, do: [%{id: "games", label: "Word games", prefixes: ["web.game."]}]

    @impl Gamend.Analytics.Catalog
    def events do
      [
        %{
          name: "web.game.finished",
          group: "games",
          label: "Round finished",
          dims: [game: "Game", lang: "Language"],
          measures: [score: "Score", total: "Questions"],
          rates: [{"score", "total", "Score"}]
        }
      ]
    end

Core adds its own group (Payments, `payments.`). A name nobody declared
still shows: in the group whose prefix it starts with, else in a group of
its own made of its first two segments (`web.game.started` →
`web.game`), labelled with the name itself. With no host catalogue that
is every name, which is the page as it was before catalogues.

An event `kind` is `:event` (reported with `Gamend.Analytics.track/3`:
counted, and kept as a row for an account) or `:counter` (counted only,
`Gamend.Analytics.count/3`: a visitor's page, a 404, a webhook).

`tabs/0` (optional) adds the host's own pages to the Analytics tab bar:
`[%{id: "traffic", label: "Traffic", path: "/admin/analytics/traffic"}]`.
A host page draws the same bar with
`GamendWeb.AdminLive.AnalyticsComponents.analytics_header/1`.

# `groups`

```elixir
@callback groups() :: [map()]
```

# `event`

```elixir
@type event() :: %{
  name: String.t(),
  group: String.t(),
  label: String.t(),
  description: String.t() | nil,
  kind: :event | :counter,
  dims: [{String.t(), String.t()}],
  measures: [{String.t(), String.t()}],
  rates: [{String.t(), String.t(), String.t()}],
  declared: boolean()
}
```

# `group`

```elixir
@type group() :: %{
  id: String.t(),
  label: String.t(),
  description: String.t() | nil,
  prefixes: [String.t()]
}
```

# `tab`

```elixir
@type tab() :: %{id: String.t(), label: String.t(), path: String.t()}
```

# `events`

```elixir
@callback events() :: [map()]
```

# `tabs`
*optional* 

```elixir
@callback tabs() :: [map()]
```

# `event`

```elixir
@spec event(String.t()) :: event()
```

One name's entry: the declared one, else one derived from the name.

# `events`

```elixir
@spec events() :: [event()]
```

Every declared event and counter, normalized, in declaration order.

# `group`

```elixir
@spec group(String.t()) :: group()
```

A group by id, declared or derived.

# `grouped`

```elixir
@spec grouped([String.t()], keyword()) :: [{group(), [event()]}]
```

`names` (event names or counter keys seen in the data) together with every
declared one, as `[{group, [event]}]`: the declared groups in order with
their events, then the derived groups, alphabetically. A group with no
event is left out. `kind:` (`:event` / `:counter`) keeps one kind of the
declared entries; a name seen is always kept.

# `groups`

```elixir
@spec groups() :: [group()]
```

Every declared group, in order: the host's, then core's. A host group with
a core group's id replaces it.

# `host`

```elixir
@spec host() :: module() | nil
```

The host's catalogue module, or nil.

# `tabs`

```elixir
@spec tabs() :: [tab()]
```

The host's extra tabs.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
