# `Gamend.Payments.Upgrades`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments/upgrades.ex#L1)

Moving to a longer plan: a monthly subscription to a yearly one, or any
subscription to a one-off purchase (lifetime) of the same entitlement.
Never for a per-subject product (`Payments.per_subject?/1`): each subject's
purchase stands alone.

An entitlement is one row per user and key, so a second purchase of a key
the user holds is refused (`:already_owned`). An upgrade is the exception
(`replaced_purchase/2`): the row comes from a Stripe subscription still
running, and the new product lasts longer (`longer?/2`: a one-off
entitlement outlasts any subscription, a subscription outlasts a shorter
one by `grant_config["duration_seconds"]`).

The new purchase takes the row when it is fulfilled (`grant_purchase`
upserts by key and moves `source_purchase_id`), so the old subscription's
later webhooks find no row to change. What is left is the old subscription
itself, which would go on charging. `supersede/1`, run once a purchase is
fulfilled, ends it the way the App Store ends an upgraded plan:

  * a subscription that starts when the old one's paid period ends
    (`first_charge_at/2`, the checkout's `trial_end`): the old one is set to
    cancel at its period end. Nothing is paid twice, nothing refunded.
  * anything else (a one-off purchase, or a period ending within 48 hours,
    which Stripe charges at once): the old one is cancelled now and the
    unused part of its last payment refunded, pro rata by time from the
    moment the new purchase was paid. The amount is the same on every
    retry, so the refund's idempotency key holds.

The refund carries `superseded_purchase_id`, never `purchase_id`: the
reversal path counts a refund only when it is ours, and this one takes
nothing back. Progress is kept on the old purchase as
`metadata["superseded"]` (`by`, `mode`, `requested_at`, then `refund_id`,
`refund_amount`, `done_at`), written before Stripe is called and after, as
`StripeRefunds` does. `sweep/1` finishes what a failure left.

# `mode`

```elixir
@type mode() :: :at_period_end | :now
```

# `first_charge_at`

```elixir
@spec first_charge_at(Ecto.UUID.t() | nil, Gamend.Payments.Product.t(), DateTime.t()) ::
  DateTime.t() | nil
```

When a subscription bought now to replace one (`replaced_purchase/2`) is
first charged: the end of the period already paid for. nil when `product`
is not a subscription, replaces nothing, or that end is under 48 hours away
(Stripe would refuse the wait; the plan is charged now and the old one
refunded pro rata instead).

# `holding_purchase`

```elixir
@spec holding_purchase(Ecto.UUID.t() | nil, String.t()) ::
  Gamend.Payments.Purchase.t() | nil
```

The purchase behind the user's active `key` row, with its product, or nil:
what the user holds that plan by. A grant with no purchase answers nil.

# `longer?`

```elixir
@spec longer?(Gamend.Payments.Product.t(), Gamend.Payments.Product.t()) :: boolean()
```

Whether `new` lasts longer than `old`: a one-off entitlement has no end, a
subscription lasts its `grant_config["duration_seconds"]`, and a product
with no period set lasts nothing (it is never an upgrade, nor upgraded
from, by length).

# `mode`

```elixir
@spec mode(Gamend.Payments.Purchase.t(), Gamend.Payments.Purchase.t()) :: mode()
```

How `new` ends `old`: at `old`'s period end when `new` is a Stripe
subscription whose first charge waits for it (`trial_end` at or past that
end), else now.

# `replaced_purchase`

```elixir
@spec replaced_purchase(Ecto.UUID.t() | nil, Gamend.Payments.Product.t()) ::
  Gamend.Payments.Purchase.t() | nil
```

The Stripe subscription a purchase of `product` would replace for the user,
or nil: the purchase behind their active row for the product's entitlement,
when it is a running Stripe subscription and `product` lasts longer.

# `supersede`

```elixir
@spec supersede(Gamend.Payments.Purchase.t()) ::
  {:ok, [{Ecto.UUID.t(), mode() | {:error, term()}}]}
```

End the Stripe subscriptions `purchase` replaces: the buyer's other running
Stripe subscriptions to the same entitlement, once `purchase` holds the
row. Run after a purchase is fulfilled, and by `sweep/1`. Answers each
ended subscription's purchase id with how it ended, or why it did not.

# `sweep`

```elixir
@spec sweep(pos_integer()) :: %{optional(atom()) =&gt; non_neg_integer()}
```

Finish the supersessions a failure left: every running Stripe subscription
whose entitlement row another purchase now holds. Up to `batch` holders a
run. Answers how many subscriptions ended each way.

# `trial_end`

```elixir
@spec trial_end(Ecto.UUID.t() | nil, Gamend.Payments.Product.t(), DateTime.t() | nil) ::
  DateTime.t() | nil
```

The checkout's `trial_end` for `product`: the later of the caller's own
(a host's free period) and `first_charge_at/2`.

# `unused_amount`

```elixir
@spec unused_amount(term(), DateTime.t() | nil, DateTime.t() | nil, DateTime.t()) ::
  non_neg_integer()
```

The part of `amount_paid` for the time left in the period after `from`,
rounded down to the minor unit. 0 when nothing is left or nothing is known.

# `upgrade?`

```elixir
@spec upgrade?(Ecto.UUID.t() | nil, Gamend.Payments.Product.t()) :: boolean()
```

Whether buying `product` would replace a plan the user holds (`replaced_purchase/2`).

---

*Consult [api-reference.md](api-reference.md) for complete listing*
