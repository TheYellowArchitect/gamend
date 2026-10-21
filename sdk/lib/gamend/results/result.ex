defmodule Gamend.Results.Result do
  @moduledoc """
  Result struct from Gamend: one play by one player.

  This is a stub module for SDK type definitions. The actual struct
  is provided by Gamend at runtime.

  ## Fields

  - `id` - Result ID (string, UUID)
  - `user_id` - The player (string, UUID)
  - `lobby_id` - The lobby it ran in, `nil` when none (string)
  - `kind` - What was played (string)
  - `visibility` - Who may read it, KV's words (string)
  - `status` - `"open"` while it runs, `"ended"` once over
  - `metadata` - What the play was: its settings (map)
  - `started_at` - When it began
  - `ended_at` - When it ended, `nil` while open
  """

  @type t :: %__MODULE__{
          id: String.t(),
          user_id: String.t(),
          lobby_id: String.t() | nil,
          kind: String.t(),
          visibility: String.t(),
          status: String.t(),
          metadata: map(),
          started_at: DateTime.t(),
          ended_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :user_id,
    :lobby_id,
    :kind,
    :visibility,
    :status,
    :metadata,
    :started_at,
    :ended_at
  ]
end
