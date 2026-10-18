# `Gamend.Bans.Sync`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/bans/sync.ex#L1)

Keeps the node-local ban table (`Gamend.Bans.Cache`) in step with the
database and the other app instances.

After init it loads every active ban into ETS; afterwards it applies the
changes other instances broadcast on `Gamend.Bans.Cache.topic/0`. Events
originating on this node are skipped — the writer already applied them.

The initial load runs in `handle_continue` and retries rather than failing the
boot: `init/1` must not couple application startup to the database being
reachable (e.g. during a rolling restart on an unmigrated table). Every failed
attempt logs an error, so a missing `bans` table stays loudly visible.

Ended bans are kept as history and deleted by `Gamend.Retention`, so there is
no sweep here: `Cache.active?/1` drops an expired entry as it reads it.

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `start_link`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
