defmodule Gamend.Results.Event do
  @moduledoc """
  Ecto schema for `result_events`: one thing that happened in a play
  (`Gamend.Results.record/4`).

  Its `id` is its place: UUIDv7 ids are strictly ordered on a node, so a
  result's events sorted by id are the order they were written in.
  `elapsed_ms` is the time into the play, on the server's clock. `key` says
  what happened, `value` the number it carries (summed by
  `Gamend.Results.stats/1`), `metadata` anything else.
  """

  use Gamend.Schema
  import Ecto.Changeset

  alias Gamend.Results.Result

  @type t :: %__MODULE__{}

  @max_key 64

  schema "result_events" do
    field :elapsed_ms, :integer
    field :key, :string
    field :value, :float
    field :metadata, :map, default: %{}

    belongs_to :result, Result
  end

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:result_id, :elapsed_ms, :key, :value, :metadata])
    |> validate_required([:result_id, :elapsed_ms, :key])
    |> validate_length(:key, min: 1, max: @max_key)
    |> validate_number(:elapsed_ms, greater_than_or_equal_to: 0)
    |> Gamend.Limits.validate_metadata_size(:metadata)
  end
end

defimpl Jason.Encoder, for: Gamend.Results.Event do
  def encode(event, opts) do
    Gamend.SchemaJSON.encode(
      event,
      [:id, :result_id, :elapsed_ms, :key, :value, :metadata],
      opts
    )
  end
end
