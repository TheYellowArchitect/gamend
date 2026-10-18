# October 2026

- [added] **Guests keep their progress.** The website makes guest accounts, and a guest who registers or signs in keeps what they did (`Gamend.Accounts.GuestMerge`, the `merge_user_data/2` hook), then returns to the page they came from (`?return_to=`). **Hosts:** implement `merge_user_data/2` for keys both accounts can hold, and pass `?return_to=` instead of setting `:user_return_to`.
- [added] **Features a guest registers for.** `config :gamend_core, Gamend.AccountRequired, [:quest_claims, :leaderboards]` keeps quest claims and leaderboard places for registered accounts, on the website and the API alike.
- [breaking] **Registering takes no password**: the emailed code confirms the address. A crashing game hook answers 500 without details.
- [added] **Bans.** Ban an account for a while or for good, with a reason (`Gamend.Bans`, `/admin/bans`, the admin API); a banned account answers 403 `account_banned` and sees `/suspended`. `after_ban_created/1` and `after_ban_lifted/1` fire for every ban, and plugins can place bans.
- [breaking] **IP bans and chat mutes are bans too**, kept as history after they end. **Hosts:** run the migrations; `GamendWeb.IpBanSync` is `Gamend.Bans.Sync` and `Gamend.Chat.Mute` is `Gamend.Bans.Ban`; `Gamend.IpBans`, `/admin/chat/mutes`, `/api/v1/admin/chat/mutes` and `after_user_muted/1` are gone (use `/api/v1/admin/bans` with `kind: "chat"` and `after_ban_created/1`).
- [changed] **Quests**: periods on the player's clock (`:quest_clock, :player`), a card that leads to where the quest is done (`:quest_action`), finished quests that wait for their claim, and repeat quests that bank each run.
- [added] **Leaderboards with several rankings**, drawn as tabs and filters (`"views"` metadata, `:leaderboard_views`), boards that can be hidden, a button to where a board is climbed (`:leaderboard_action`), and the same over the API (`key`, `/records/above`, `/keys`). **SDKs:** regenerated; Balaur's `get_my_record` takes `options`.
- [added] **Analytics events and tabs.** `Gamend.Analytics.track/3` keeps a row per event, `/admin/analytics` has Overview, Features, Explore, People, Counters and Economy tabs, a host describes its events (`:analytics_catalog`), and a reader back on their cookie counts as active. **Hosts:** run the migration.
- [added] **Stripe payments, end to end**: refunds within 14 days, resuming and upgrading, free periods, an hourly sweep for lost webhooks and `mix gamend.stripe.setup`. **Hosts:** set the webhook to API version `2025-11-17.clover`.
- [added] **Reports.** Players report from `/report` or the API, admins work the queue at `/admin/reports`, and a host adds its own kinds and a reward.
- [added] **Pages**: a Back button and a title icon on every page, navbar links and counts that follow the reader, presentation pages drawn for a signed-in reader, and an `/admin` card for every admin page (`:admin_cards`). **Hosts:** a page that deletes itself navigates away with `replace: true`.
- [added] **Website feature switches** for the store, chat, groups, friends, tournaments, the game (`play`), the payments API and the language switcher's flags; a page, link or guide marked with a switched-off flag goes with it.
- [added] **Per-account preferences**: notifications per group and channel with one-click unsubscribe, and the time zone, language and theme follow the account.
- [changed] **Layout and speed**: three page widths, breadcrumbs, a navbar that fits a phone, cached per-user reads and links that reuse the open connection. **Hosts:** declare `text-muted` and `--container-narrow` in your stylesheet.
- [changed] **Translations say "you" informally**, and the English is American.
- [changed] **Version 1.1**: releases are `1.1.<commit count>`, from the `VERSION` file.
- [added] **Smaller additions**: crawler statistics, FAQ sections on presentation pages, rate-limit-exempt IPs, KV pruning by prefix, slow query logging and `Accounts.update_user_metadata/2`.
- [removed] **IndexNow.** **Hosts:** drop `GAMEND_INDEX_NOW_*` and any `urls/1` from your sitemap source.
- [fixed] **Sign-in and connections**: Steam sign-in works again, an unconfirmed account gets its confirmation email instead of a login link, and TLS 1.2 clients (Stripe's sandbox webhooks) connect again.
- [fixed] **Smaller fixes**: leaving a page plays no `phx-remove`, a finished chain step always has its card, generated usernames ignore the caller's `:rand` seed, `Sitemap.Cache.prune/0` reads every page, and cached logins, lock waits and races no longer leave stale state.

# September 2026

- [added] **Gamend as a download**: server binaries and a `gamend` command, with a project's own static files and plugins served from where it runs.
- [added] **A C++ SDK**, generated with the Godot and Balaur ones and shipped together.
- [breaking] **One response shape across the API**, player and admin, with named schemas; the SDKs' classes follow.
- [added] **Accounts**: personal API tokens, GitHub sign-in, lockout after failed passwords, a grace period before deletion, captcha for API sign-up and Unicode usernames. An email registration signs in only once confirmed.
- [added] **Stripe Managed Payments**, the customer portal, and entitlements granted without a purchase.
- [added] **Site search, a `/ui` page of building blocks, manuals in the docs, and blog posts with pictures.**
- [added] **Settings for values that were fixed in code**, plus host hook modules and plugs.
- [changed] **`gamend_core` and `gamend_web` are on Hex.**
- [fixed] **Reliability and security**: slow work kept out of transactions, rate limiting before the body is read, IPv6 bans per /64, hashed lobby passwords, no personal data in logs, and fewer 500s.

# August 2026

- [added] **Plugins in GDScript and Gleam**, client logs, player analytics (D1/D7/D30), and grouped and repeating quests.
- [added] **Friends and retention admin pages**, a load-test harness, a performance guide and 16 new guides.
- [changed] **The home page shows the product**: screenshots, a tour video and a news menu.
- [fixed] **Faster logins and matchmaking**, plugins in releases, and realtime events no longer sent twice.

# July 2026

- [breaking] **Renamed to Gamend**, with UUIDv7 ids, underscore API paths, one pagination shape and one theme file.
- [added] **Quests (replacing achievements), economy, inventory, object storage, matchmaking, tournaments, ready checks, push notifications and lobby state.**
- [added] **Chat moderation, captcha, settings, retention for every table, the API lint, 30 locales and an admin runtime page.**
- [changed] **Hardening** of auth, payments and realtime, and faster broadcasts and queries.

# April 2026

- [added] **Native HTTPS, account activation, sitemap and robots.txt, a roadmap page, Spanish, French and Romanian, and security hardening.**

# March 2026

- [added] **Achievements, rate limiting, and WebSocket and WebRTC updates**; leaderboards accept labels; the admin shows live connections.

# Feb 2026

- [added] **Groups, parties, notifications, chat, the changelog and the blog.**
