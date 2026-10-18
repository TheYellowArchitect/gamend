defmodule Gamend.Bans.Ban do
  @moduledoc """
  Ban struct from Gamend: an IP, an account or a chat mute.

  This is a stub module for SDK type definitions. The actual struct
  is provided by Gamend at runtime.

  ## Fields

  - `id` - Ban ID (string, UUID)
  - `kind` - `:ip`, `:account` or `:chat` (a mute)
  - `subject` - The IP address (an IPv6 one as its /64) or the user id (string)
  - `user_id` - The banned user, `nil` for an IP ban (string)
  - `scope` - A chat ban's reach: `"global"`, `"lobby"`, `"group"` or `"party"`; `nil` otherwise
  - `scope_ref_id` - A scoped chat ban's room, `nil` otherwise (string)
  - `expires_at` - When it ends, `nil` for a permanent ban
  - `reason` - Why, as the banned player is shown it (string)
  - `source` - `:admin`, `:api`, `:room` (a lobby host, group admin or party leader), `:plugin` or `:system`
  - `banned_by` - The person who placed it, `nil` when none did (string)
  - `lifted_at` - When it was lifted or replaced, `nil` while in force or once expired
  - `lifted_by` - The admin who lifted it, `nil` when none did (string)
  - `inserted_at` - Creation timestamp
  - `updated_at` - Last update timestamp
  """

  @type kind :: :ip | :account | :chat

  @type t :: %__MODULE__{
          id: String.t(),
          kind: kind(),
          subject: String.t(),
          user_id: String.t() | nil,
          scope: String.t() | nil,
          scope_ref_id: String.t() | nil,
          expires_at: DateTime.t() | nil,
          reason: String.t() | nil,
          source: :admin | :api | :room | :plugin | :system,
          banned_by: String.t() | nil,
          lifted_at: DateTime.t() | nil,
          lifted_by: String.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :kind,
    :subject,
    :user_id,
    :scope,
    :scope_ref_id,
    :expires_at,
    :reason,
    :source,
    :banned_by,
    :lifted_at,
    :lifted_by,
    :inserted_at,
    :updated_at
  ]
end
