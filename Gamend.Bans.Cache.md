# `Gamend.Bans.Cache`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/bans/cache.ex#L1)

Node-local hot path for `Gamend.Bans`: every active ban in ETS, keyed by its
target (`Gamend.Bans.Ban.target/4`, `{kind, subject, scope}`), read on each
request an IP ban covers and each chat message a mute covers.

The database is the source of truth; this mirrors it, and PubSub carries each
change to the other instances, where `Gamend.Bans.Sync` applies it (and loads
the table at boot). An entry past its end is dropped as it is read, so a ban
never outlives its expiry whether or not anything sweeps.

# `active?`

```elixir
@spec active?(tuple()) :: boolean()
```

Whether `target` has an active ban on this node.

# `apply_remote`

```elixir
@spec apply_remote(atom(), term()) :: :ok
```

Apply a change that originated on another instance.

Only touches ETS — the originating instance already persisted it.

# `delete`

```elixir
@spec delete(tuple()) :: :ok
```

Remove a target's ban locally and on the other instances.

# `init_table`

```elixir
@spec init_table() :: :ok
```

Ensure the ETS table exists (called once at app startup).

# `list`

```elixir
@spec list(Gamend.Bans.Ban.kind() | nil) :: [
  {Gamend.Bans.Ban.kind(), String.t(), DateTime.t() | :infinity}
]
```

The active bans on this node, of one kind or all, as
`[{kind, subject, expires_at | :infinity}]`: no query, for counts on a page.

# `load_persisted`

```elixir
@spec load_persisted() :: :ok
```

Load every active ban from the database into ETS, replacing what was there.

Called at boot by `Gamend.Bans.Sync`.

# `put`

```elixir
@spec put(Gamend.Bans.Ban.t()) :: :ok
```

Mirror a ban locally and on the other instances.

# `topic`

```elixir
@spec topic() :: String.t()
```

PubSub topic on which ban changes are broadcast.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
