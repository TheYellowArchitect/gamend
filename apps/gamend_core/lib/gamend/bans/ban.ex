defmodule Gamend.Bans.Ban do
  @moduledoc """
  One ban: an IP address or an account kept out until `expires_at` (`nil` is
  permanent), or until an admin lifts it.

  A row is kept after it ends, lifted or expired, so a target's history reads
  as its rows; retention deletes ended rows after `bans_days`. A ban is active
  while `lifted_at` is nil and `expires_at` is nil or still ahead.

    * `kind` — `:ip` (`subject` is the address, an IPv6 one as its /64) or
      `:account` (`subject` is the user id, also in `user_id`).
    * `reason` — why, in the words the banned player is shown.
    * `source` — who placed it: `:admin` (the admin pages), `:api` (the admin
      API), `:plugin` (a game hook) or `:system`.
    * `banned_by` / `lifted_by` — the admin who placed or lifted it, when one did.
  """

  use Gamend.Schema
  import Ecto.Changeset

  alias Gamend.Accounts.User

  @kinds [:ip, :account]
  @sources [:admin, :api, :plugin, :system]

  @type kind :: :ip | :account
  @type t :: %__MODULE__{}

  schema "bans" do
    field :kind, Ecto.Enum, values: @kinds
    field :subject, :string
    field :expires_at, :utc_datetime
    field :reason, :string
    field :source, Ecto.Enum, values: @sources, default: :admin
    field :lifted_at, :utc_datetime

    belongs_to :user, User
    belongs_to :banned_by_user, User, foreign_key: :banned_by
    belongs_to :lifted_by_user, User, foreign_key: :lifted_by

    timestamps(type: :utc_datetime)
  end

  @doc "The kinds of ban."
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc "Who may place a ban."
  @spec sources() :: [atom()]
  def sources, do: @sources

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(ban, attrs) do
    ban
    |> cast(attrs, [:kind, :subject, :user_id, :expires_at, :reason, :source, :banned_by])
    |> validate_required([:kind, :subject, :source])
    |> validate_length(:subject, max: 64)
    |> validate_length(:reason, max: Gamend.Limits.get(:max_ban_reason))
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:banned_by)
  end
end
