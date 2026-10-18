# `Gamend.Bans.ExpiryWorker`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/bans/expiry_worker.ex#L1)

Tells of a ban's end when it runs out (`Gamend.Bans.expire/1`): the
`after_ban_lifted/1` hook, and `account_unbanned` for an account.

One job per ban with an end, inserted with the ban and scheduled at its
`expires_at`. The ban itself needs no job to end: the cache stops counting it
at `expires_at` whether or not this runs. A ban lifted or replaced first makes
this a no-op, since the lift told already; one deleted (its user deleted) is
gone. A job that starts a moment early waits out the rest.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
