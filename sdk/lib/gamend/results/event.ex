defmodule Gamend.Results.Event do
  @moduledoc """
  Result event struct from Gamend: one thing that happened in a play.

  This is a stub module for SDK type definitions. The actual struct
  is provided by Gamend at runtime.

  ## Fields

  - `id` - Event ID (string, UUID); ids are time-ordered, so they sort in the order written
  - `result_id` - The play it belongs to (string, UUID)
  - `elapsed_ms` - Milliseconds since the play began (integer)
  - `key` - What happened (string)
  - `value` - The number it carries, or `nil` (float)
  - `metadata` - Anything else (map)
  """

  @type t :: %__MODULE__{
          id: String.t(),
          result_id: String.t(),
          elapsed_ms: non_neg_integer(),
          key: String.t(),
          value: float() | nil,
          metadata: map()
        }

  defstruct [:id, :result_id, :elapsed_ms, :key, :value, :metadata]
end
