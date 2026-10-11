# `Gamend.Analytics.Buffer`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/analytics/buffer.ex#L1)

Gathers `Gamend.Analytics` writes in ETS and lands them in batches: one
upsert per `(key, day)` counter and one `insert_all` for the events, every
`flush_ms`. A page view at twenty requests a second is otherwise a
database write per request, on the request's own connection.

The table is public with write concurrency: the request process does one
`update_counter` or one insert and never sends this process a message.
Up to one window of counts and events is lost on a crash or a kill, which
a daily number can bear; a graceful stop flushes.

## Configuration

    config :gamend_core, Gamend.Analytics.Buffer,
      flush_ms: 10_000    # 0 writes through synchronously

`flush_ms: 0` is what the test environment runs: a test reads a counter
the moment the page wrote it, and nothing buffered can outlive the sandbox
owner. When the process is not running (a partial tree) callers write
through too, rather than drop the write.

Events are capped at `max_events/0` waiting rows; past that a new event is
dropped and `analytics.dropped` counted, so a database outage costs memory
bounded in megabytes, never the node.

# `buffered?`

```elixir
@spec buffered?() :: boolean()
```

Whether writes are gathered here (`flush_ms/0` > 0 and the table exists).

# `bump`

```elixir
@spec bump(String.t(), pos_integer(), Date.t()) :: :ok
```

Adds `n` to the counter `key` for `day`. Caller must have checked `buffered?/0`.

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `clear`

```elixir
@spec clear() :: :ok
```

Drops everything gathered, unwritten. For a test that set a window.

# `event`

```elixir
@spec event(map()) :: :ok
```

Queues one event row (`%{name, dims, user_id, inserted_at}`). Dropped, and
counted as `analytics.dropped`, past `max_events/0`.

# `flush`

```elixir
@spec flush() :: {non_neg_integer(), non_neg_integer()}
```

Writes everything gathered so far, in the caller's process: the counters
as one upsert per `(key, day)`, the events in chunks of 500.
The timer calls it; the admin pages call it before reading; a test calls
it when it set a window. Answers `{counters, events}` written.

# `flush_ms`

```elixir
@spec flush_ms() :: non_neg_integer()
```

Milliseconds between flushes; 0 means callers write through.

# `max_events`

```elixir
@spec max_events() :: pos_integer()
```

The cap on events waiting to be written.

# `start_link`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
