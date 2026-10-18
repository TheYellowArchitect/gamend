# `Gamend.Chat.Moderation.Notices`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/chat/moderation/notices.ex#L1)

The notifications chat moderation sends: alerting admins that a report landed,
warning a player, telling a player they were muted, and telling a reporter
what came of their report.

Every message has a `default_*` function so the admin console can prefill the
box and let a moderator edit it before sending. The text is the moderator's,
not core's — these are only sensible starting points.

All of them go through `Notifications.admin_create_notification/3` with the
recipient as their own sender. That is the same trick chat notifications use:
the notification table upserts on `(sender_id, recipient_id, title)`, so a
player who is muted twice keeps one "You have been muted" entry (re-marked
unread) instead of collecting a pile, and an admin sees one standing "New
chat reports" alert rather than one per report.

# `default_mute_message`

```elixir
@spec default_mute_message(Gamend.Bans.Ban.t()) :: String.t()
```

Default body for the notice a muted player receives.

# `default_reporter_message`

```elixir
@spec default_reporter_message(String.t()) :: String.t()
```

Default body for the reply a reporter receives once their report is handled.

# `default_warning_message`

```elixir
@spec default_warning_message(String.t() | nil) :: String.t()
```

Default body for a moderator warning about a reported message.

# `mute_title`

```elixir
@spec mute_title() :: String.t()
```

Title used for the player mute notice.

# `notify_admins_of_report`

```elixir
@spec notify_admins_of_report(non_neg_integer()) :: :ok
```

Tell every admin that a report is waiting.

Best-effort and fire-and-forget: a failure here must never take down the
report that triggered it.

# `notify_muted`

```elixir
@spec notify_muted(Ecto.UUID.t(), String.t()) :: :ok
```

Send `message` to a muted player.

# `notify_reporter`

```elixir
@spec notify_reporter(Ecto.UUID.t(), String.t()) :: :ok
```

Tell a reporter what came of their report.

# `notify_warning`

```elixir
@spec notify_warning(Ecto.UUID.t(), String.t()) :: :ok
```

Send a warning to a player.

# `report_resolved_title`

```elixir
@spec report_resolved_title() :: String.t()
```

Title used when telling a reporter their report was handled.

# `report_title`

```elixir
@spec report_title() :: String.t()
```

Title used for the admin report alert (constant, so alerts collapse).

# `warning_title`

```elixir
@spec warning_title() :: String.t()
```

Title used for a moderator warning.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
