defmodule Gamend.Payments.StripePlanChangeTest do
  @moduledoc """
  A running Stripe subscription moved to another product of the same period
  (`Gamend.Payments.StripePlanChange`): from here, and from a webhook when
  the price changed in Stripe.
  """
  use Gamend.DataCase

  alias Gamend.AccountsFixtures
  alias Gamend.Payments
  alias Gamend.Payments.Entitlement
  alias Gamend.Payments.Purchase

  defmodule NoopPaymentHooks do
    use Gamend.TestSupport.NoopHooks
  end

  # A subscription bills the price its purchase was bought at until changed.
  # `sub_late_` ones are past_due; `sub_declined_` ones refuse a change as a
  # declined card would.
  defmodule StripeAdapter do
    def retrieve_subscription(subscription_id) do
      status =
        if String.starts_with?(subscription_id, "sub_late_"), do: "past_due", else: "active"

      price = Process.get({:price, subscription_id})
      {:ok, subscription(subscription_id, status, price)}
    end

    def change_subscription_price("sub_declined_" <> _rest, _item_id, _price_id, _opts),
      do: {:error, {:stripe_error, %{"code" => "card_declined"}}}

    def change_subscription_price(subscription_id, item_id, price_id, opts) do
      send(self(), {:stripe_change_price, subscription_id, item_id, price_id, opts})
      {:ok, subscription(subscription_id, "active", price_id)}
    end

    def verify_webhook(raw_body, _signature), do: Jason.decode(raw_body)

    def subscription(subscription_id, status, price_id) do
      %{
        "id" => subscription_id,
        "object" => "subscription",
        "status" => status,
        "cancel_at_period_end" => false,
        "items" => %{
          "data" => [
            %{
              "id" => "si_" <> subscription_id,
              "price" => %{"id" => price_id},
              "current_period_end" => System.os_time(:second) + 20 * 86_400
            }
          ]
        }
      }
    end
  end

  @month 30 * 86_400

  setup do
    original_stripe = Application.get_env(:gamend_core, :stripe_adapter)
    original_hooks = Application.get_env(:gamend_core, :hooks_module)

    Application.put_env(:gamend_core, :stripe_adapter, StripeAdapter)
    Application.put_env(:gamend_core, :hooks_module, NoopPaymentHooks)

    on_exit(fn ->
      restore_env(:stripe_adapter, original_stripe)
      restore_env(:hooks_module, original_hooks)
    end)

    n = System.unique_integer([:positive])

    %{
      user: AccountsFixtures.user_fixture(),
      small: create_product("host_small_#{n}", @month),
      large: create_product("host_large_#{n}", @month),
      yearly: create_product("host_yearly_#{n}", 365 * 86_400)
    }
  end

  describe "change_stripe_subscription/4" do
    test "moves the subscription, its purchase and its row to the other product", ctx do
      purchase = paid_subscription(ctx.user, ctx.small, "srv1", "sub_a")
      row = row(ctx.user, ctx.small, "srv1")

      assert {:ok, %{entitlement: moved, purchase: moved_purchase}} =
               Payments.change_stripe_subscription(ctx.user, row.id, ctx.large)

      assert_received {:stripe_change_price, "sub_a", "si_sub_a", price, opts}
      assert price == ctx.large.external_id
      assert opts[:end_trial] == false
      assert opts[:idempotency_key] == "plan-change:#{purchase.id}:0"

      assert moved.id == row.id
      assert moved.key == key(ctx.large, "srv1")
      assert moved.product_id == ctx.large.product_id
      assert DateTime.diff(moved.expires_at, DateTime.utc_now()) > 19 * 86_400
      refute Repo.get_by(Entitlement, user_id: ctx.user.id, key: key(ctx.small, "srv1"))

      assert moved_purchase.product_id == ctx.large.product_id
      assert moved_purchase.provider_product_id == ctx.large.id
      assert [%{"from" => _, "to" => _}] = moved_purchase.metadata["plan_changes"]

      # And back: the second change has an idempotency key of its own.
      Process.put({:price, "sub_a"}, ctx.large.external_id)

      assert {:ok, %{entitlement: back}} =
               Payments.change_stripe_subscription(ctx.user, row.id, ctx.small)

      assert back.key == key(ctx.small, "srv1")
      assert_received {:stripe_change_price, "sub_a", _item, _price, opts}
      assert opts[:idempotency_key] == "plan-change:#{purchase.id}:1"
    end

    test "passes end_trial on", ctx do
      paid_subscription(ctx.user, ctx.small, "srv2", "sub_b")
      row = row(ctx.user, ctx.small, "srv2")

      assert {:ok, _changed} =
               Payments.change_stripe_subscription(ctx.user, row.id, ctx.large, end_trial: true)

      assert_received {:stripe_change_price, "sub_b", _item, _price, opts}
      assert opts[:end_trial] == true
    end

    test "refuses what is not a plan change, before asking Stripe", ctx do
      paid_subscription(ctx.user, ctx.small, "srv3", "sub_c")
      row = row(ctx.user, ctx.small, "srv3")

      assert {:error, :same_product} =
               Payments.change_stripe_subscription(ctx.user, row.id, ctx.small)

      assert {:error, :incompatible_product} =
               Payments.change_stripe_subscription(ctx.user, row.id, ctx.yearly)

      {:ok, inactive} = Payments.update_provider_product(ctx.large, %{active: false})

      assert {:error, :not_for_sale} =
               Payments.change_stripe_subscription(ctx.user, row.id, inactive)

      other = AccountsFixtures.user_fixture()

      assert {:error, :entitlement_not_found} =
               Payments.change_stripe_subscription(other, row.id, ctx.large)

      refute_received {:stripe_change_price, _, _, _, _}
    end

    test "a subscription that is not paying, or a declined card, changes nothing", ctx do
      paid_subscription(ctx.user, ctx.small, "srv4", "sub_late_d")
      late = row(ctx.user, ctx.small, "srv4")

      assert {:error, :subscription_not_active} =
               Payments.change_stripe_subscription(ctx.user, late.id, ctx.large)

      paid_subscription(ctx.user, ctx.small, "srv5", "sub_declined_e")
      declined = row(ctx.user, ctx.small, "srv5")

      assert {:error, {:stripe_error, %{"code" => "card_declined"}}} =
               Payments.change_stripe_subscription(ctx.user, declined.id, ctx.large)

      assert Repo.reload!(declined).key == key(ctx.small, "srv5")
    end

    test "a key held through another purchase refuses; a leftover one is replaced", ctx do
      paid_subscription(ctx.user, ctx.small, "srv6", "sub_f")
      paid_subscription(ctx.user, ctx.large, "srv6", "sub_g")
      row = row(ctx.user, ctx.small, "srv6")
      held = row(ctx.user, ctx.large, "srv6")

      assert {:error, :already_owned} =
               Payments.change_stripe_subscription(ctx.user, row.id, ctx.large)

      held |> Entitlement.changeset(%{status: "expired"}) |> Repo.update!()

      assert {:ok, %{entitlement: moved}} =
               Payments.change_stripe_subscription(ctx.user, row.id, ctx.large)

      assert moved.id == row.id
      refute Repo.get(Entitlement, held.id)
    end
  end

  describe "a price changed in Stripe" do
    test "is followed from customer.subscription.updated", ctx do
      purchase = paid_subscription(ctx.user, ctx.small, "srv7", "sub_h")
      row = row(ctx.user, ctx.small, "srv7")

      object =
        "sub_h"
        |> StripeAdapter.subscription("active", ctx.large.external_id)
        |> Map.put("metadata", %{"purchase_id" => purchase.id})

      assert {:ok, :processed} = webhook("customer.subscription.updated", object)

      moved = Repo.reload!(row)
      assert moved.key == key(ctx.large, "srv7")
      assert Repo.get!(Purchase, purchase.id).product_id == ctx.large.product_id

      # The same event again changes nothing more.
      assert {:ok, _result} = webhook("customer.subscription.updated", object)
      assert [_one] = Repo.get!(Purchase, purchase.id).metadata["plan_changes"]
    end

    test "to a price nobody sells here is left alone", ctx do
      purchase = paid_subscription(ctx.user, ctx.small, "srv8", "sub_i")
      row = row(ctx.user, ctx.small, "srv8")

      object =
        "sub_i"
        |> StripeAdapter.subscription("active", "price_unknown")
        |> Map.put("metadata", %{"purchase_id" => purchase.id})

      ExUnit.CaptureLog.capture_log(fn ->
        assert {:ok, :processed} = webhook("customer.subscription.updated", object)
      end)

      assert Repo.reload!(row).key == key(ctx.small, "srv8")
    end
  end

  defp paid_subscription(user, provider_product, subject, subscription_id) do
    Process.put({:price, subscription_id}, provider_product.external_id)
    ends_at = DateTime.add(DateTime.utc_now(:second), 20 * 86_400)

    {:ok, purchase} =
      Payments.create_purchase(user, provider_product, %{
        "metadata" => %{
          "subject" => subject,
          "stripe_subscription_id" => subscription_id,
          "stripe_subscription_status" => "active"
        }
      })

    {:ok, purchase} =
      purchase
      |> Purchase.changeset(%{expires_at: ends_at})
      |> Repo.update!()
      |> Payments.fulfill_purchase()

    purchase
  end

  defp row(user, provider_product, subject),
    do: Repo.get_by!(Entitlement, user_id: user.id, key: key(provider_product, subject))

  defp key(provider_product, subject),
    do: Payments.entitlement_key(provider_product.product, subject)

  defp webhook(type, object) do
    Jason.encode!(%{
      "id" => "evt_#{System.unique_integer([:positive])}",
      "type" => type,
      "api_version" => "2025-11-17.clover",
      "data" => %{"object" => object}
    })
    |> Payments.handle_stripe_webhook("sig")
  end

  defp create_product(key, duration) do
    {:ok, product} =
      Payments.create_product(%{
        "sku" => "#{key}_monthly",
        "title" => key,
        "kind" => "subscription",
        "grant_config" => %{
          "entitlement_key" => key,
          "per_subject" => true,
          "duration_seconds" => duration
        }
      })

    {:ok, provider_product} =
      Payments.create_provider_product(%{
        "product_id" => product.id,
        "provider" => "stripe",
        "external_id" => "price_#{key}",
        "currency" => "USD",
        "unit_amount" => 500
      })

    Repo.preload(provider_product, :product)
  end

  defp restore_env(key, nil), do: Application.delete_env(:gamend_core, key)
  defp restore_env(key, value), do: Application.put_env(:gamend_core, key, value)
end
