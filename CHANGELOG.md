# October 2026

- [fixed] **Steam sign-in works again, in the browser and over the API.** Under Ueberauth 0.11, which signs its state cookie, every Steam callback failed with `csrf_attack`: `ueberauth_steam_strategy` 0.2.1 wrote that cookie unsigned (fixed in 0.2.2, now required). The polled flow (`GET /api/v1/auth/steam`) and linking (`POST /api/v1/me/providers/steam/authorize`) never passed on any version: they opened Steam directly, so the browser never had the cookie. Their `authorization_url` is now `/auth/steam?session_id=…`, Ueberauth's own request, and the callback finds the session id in the browser's session.
- [added] **Quests on the player's clock.** `config :gamend_core, :quest_clock, :player` reads each player's quest periods in their own time zone (from their preferences, UTC when unknown): a daily turns over at their midnight, a weekly at their Monday's. Windows and timestamps stay UTC. The default stays `:utc`, one rollover for everyone.
- [added] **A quest card leads to where the quest is done.** `config :gamend_core, :quest_action, {Module, :function}` answers a path for a quest and a viewer (`Quests.host_action/2`). On `/quests` a click anywhere on a card does its one thing: claims it when it waits for its claim, else follows that path (in the reader's locale), else opens its chain or group, whose badge is otherwise a button of its own. `entity_card` takes `href` (the title's link stretched over the card), and every clickable entity card rises a little on hover. A path off the site is dropped. The "You have N quests ready to claim" banner is gone: the Claim button is on the card, and the count on the Claimable filter and the nav.
- [fixed] **A finished chain step always has its card.** A chain showed its earliest unclaimed step, so a later step that finished first (its predecessor claimed out of order) was counted as claimable with no Claim button anywhere. The chain's earliest claimable step stands for it now.
- [changed] **Finished quests never expire, and repeat quests bank.** A completed run waits for its claim whatever period it finished in (`claim/2` pays the oldest first, the list shows it until claimed, the retention prune keeps it), and a `repeat` quest keeps counting while it waits: each target's worth is one more claim, ready the moment the last is paid. `claimable_count/1` counts every waiting claim. A claimable card shows no countdown.
- [changed] **Analytics in tabs.** `/admin/analytics` is Overview, Features, Explore (one event or group, filters on its dimensions, breakdowns with averages, the rows), People (one account's days, events and ledger), Counters and Economy, with small server-drawn charts (`GamendWeb.Charts`) and every filter in the URL. A host describes its events with `Gamend.Analytics.Catalog` (`config :gamend_core, :analytics_catalog`: groups, labels, dimensions, numbers) and can add its own tabs; without one, events are grouped by name. **Hosts:** links to `/admin/analytics` keep working; the old single page's sections moved to the tabs.
- [fixed] **Analytics counts a reader back on their cookie.** The activity day (DAU / WAU / MAU, D1 / D7 / D30) was recorded only when a session was made, so a returning website reader was almost never active; every signed-in request and LiveView mount records it now. `track/3` keeps a row for an account only (a visitor's event is counted), and the people numbers split into registered and guest accounts (`segment:`, `Analytics.segments/0`, `?segment=` on the admin API). The per-day table gains WAU, MAU and stickiness for each day.
- [added] **Analytics events.** `Gamend.Analytics.track/3` counts a thing for the day and keeps the row (who, when, every field) in `analytics_events`, so the admin Analytics page now shows every feature's DAU / WAU / MAU, first-timers and D1 / D7 / D30, any feature broken down by one of its dimensions (people per value), the counters grouped by key with their dimensions, and the newest events. Writes are buffered (`Gamend.Analytics.Buffer`, 10 s) — `count/3` included — and the rows are pruned after `GAMEND_RETENTION_ANALYTICS_EVENTS_DAYS` (365). **Hosts:** run the migration; the admin page's flat counter list is gone.
- [fixed] **No login link for an account not confirmed yet.** Asking for a magic link sent it a second email whose link signed in; the page now sends the confirmation email again instead, at most once a minute, so asking right after registering sends nothing new.
- [fixed] **TLS 1.2 clients can connect again.** The HTTPS listener used Plug's `:strong` cipher suite, which has meant TLS 1.3 only since Plug 1.19; a 1.2-only client (Stripe's sandbox webhook sender, Java 8 crawlers, old Android) failed the handshake with nothing logged. It is now `:compatible`: TLS 1.3 and 1.2, ECDHE AEAD suites only.
- [added] **Stripe payments, end to end.** Buyers refund within 14 days, resume a cancelled renewal and upgrade to a longer plan; checkouts can start with a free period; an hourly sweep catches lost webhooks; `mix gamend.stripe.setup` configures the account; payments are counted and logged. Disputes, refunds and failed renewals now end access properly, and a player opens one checkout at a time. **Hosts:** set the Stripe webhook to API version `2025-11-17.clover` (or run the setup task).
- [added] **Reports.** Players report problems from `/report` or the API, admins work the queue at `/admin/reports`, and a host can add its own report kinds. The web form asks for no email (a signed-in reporter hears back in their notifications), a page report keeps the page's full URL (keyed by its path), and "Edit this report" brings a report just sent back to its form: sending it again replaces it. A host that pays for a fixed report says so on the form and in the reply (`config :gamend_core, :report_reward`). The admins' "New reports" alert (and the chat one) links to its queue.
- [added] **Every admin page has a dashboard card**: Reports, Sessions, Notifications, Push devices and Friends joined `/admin`, and a host adds its own with `config :gamend_web, :admin_cards, [Module]` (`GamendWeb.AdminCard`).
- [added] **Per-account preferences.** Notification choices per group and channel, with email and one-click unsubscribe; time zone, language and theme follow the account.
- [added] **Guest accounts on the website**, kept when the visitor registers or signs in.
- [added] **Leaderboards hold several rankings per board and can be hidden.**
- [added] **Website feature switches**: the store, chat, groups, friends, tournaments, the game itself (`play`) and the payments catalog and checkout API can be turned off on the site while the game client keeps them. A theme page, a link or a guide (`feature:` in its front matter, through the new `visible:` content hook) marked with a switched-off flag goes with it.
- [changed] **Translations say "you" informally**, in every language that has the choice (French `tu`, German `du`, Russian `ты`), and the English is American (`Canceled`). Tests hold both.
- [added] **Smaller additions**: crawler statistics in Admin → Geo, a count of LiveViews with no account in Admin → Connections, FAQ sections on presentation pages, rate-limit-exempt IPs, KV pruning by prefix, slow query logging, `Accounts.update_user_metadata/2`, a nav entry `count` (`{Module.fun}`) drawn as a red number, summed on its dropdown: the quests to claim, a claim's flash that says what it paid ("Rewards claimed! +50 coins"), and `data-motion-text="pop"` on a `readonly` nav entry, for a host's motion script to play when its value changes (a coin balance).
- [breaking] **Registering takes no password**: the emailed code confirms the address and sets it. A crashing game hook answers 500 without details.
- [changed] **Faster pages.** Links between pages reuse the open connection, settings and quests read less, and repeated per-user reads are cached.
- [added] **A Back button on every page**: `<.back_link>` and `home_path/0` in `CoreComponents`, at the start of each title row, and `<.header back_href=…>` for a plain page. Its link is the page's trail (pages one step under home go home in the reader's locale); a click returns to the page the reader came from instead, when that was a click inside the site in the same language (`back_link.js`, the Navigation API). **Hosts:** a page that deletes itself should navigate away with `replace: true`.
- [changed] **Layout and accessibility.** Three page widths, breadcrumbs in the navbar (admin pages too, named from their path), a navbar that fits a phone, and fixes from a Lighthouse pass. **Hosts:** declare `text-muted` and `--container-narrow` in your stylesheet, as `assets/css/app.css` does.
- [changed] **Version 1.1**: releases are `1.1.<commit count>`, read from the new `VERSION` file.
- [fixed] **Leaving a page no longer plays its `phx-remove`s.** LiveView 1.2 defaults `cascadePhxRemoveOnNavigation` to true, so a live navigation played every `phx-remove` in the old page at the click: a list item faded out and a panel folded shut while the next page loaded. The socket sets it to false; a `phx-remove` plays only when a patch removes its element.
- [fixed] **Generated usernames no longer follow the caller's `:rand` seed.** A host that seeded `:rand` and left it seeded made every new account try the same four names, and once they were taken registration failed. The generator now draws from a random state of its own.
- [fixed] **`Sitemap.Cache.prune/0` reads every page of the storage listing**, so a host with over a thousand sitemap files no longer keeps every old signature.
- [fixed] **Races and stale data.** A revoked login, a balance or a KV value could stay cached for a minute; waiting on a lock no longer stalls for seconds; group admins, party invites, lobby leaders and rows deleted mid-request no longer leave bad state or answer 500. Scheduled hooks reach plugins again.

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
