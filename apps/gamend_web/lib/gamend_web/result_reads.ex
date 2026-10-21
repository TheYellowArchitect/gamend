defmodule GamendWeb.ResultReads do
  @moduledoc """
  The reads a client makes of results (`Gamend.Results`), one implementation
  for the user socket (`results:list`, `results:get`, `results:events`) and
  the HTTP API (`GET /api/v1/results…`), so both answer the same shapes under
  the same visibility (`Gamend.Results.readable?/2`).

  The caller is read fresh, not from the socket's scope: whether they may
  read a lobby's result depends on the lobby they sit in now.
  """

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.Results
  alias Gamend.Results.Result
  alias GamendWeb.Pagination

  @doc """
  The caller's results, newest first, each with its stats, as a page
  (`Pagination.envelope/4`). Params: `kind`, `status`, `page`, `page_size`.
  """
  @spec list(String.t(), map()) :: map()
  def list(user_id, params) when is_binary(user_id) and is_map(params) do
    {rows, page, page_size, total} = page(user_id, params)
    Pagination.envelope(rows, page, page_size, total)
  end

  @doc "`list/2`'s page as its parts: `{rows, page, page_size, total_count}`."
  @spec page(String.t(), map()) :: {[map()], pos_integer(), pos_integer(), non_neg_integer()}
  def page(user_id, params) when is_binary(user_id) and is_map(params) do
    {page, page_size} = Pagination.params(params)
    filters = params |> Map.take(~w(kind status)) |> Map.put("user_id", user_id)
    results = Results.list(filters, page: page, page_size: page_size)
    stats = results |> Enum.map(& &1.id) |> Results.stats()
    rows = Enum.map(results, &serialize(&1, Map.get(stats, &1.id, %{})))
    {rows, page, page_size, Results.count(filters)}
  end

  @doc "One result and its stats, if the caller may read it."
  @spec get(String.t(), term()) :: {:ok, map()} | {:error, :not_found | :forbidden}
  def get(user_id, id) do
    with {:ok, result} <- readable(user_id, id) do
      {:ok, serialize(result, Results.stats(result))}
    end
  end

  @doc """
  A result's events, oldest first, if the caller may read it. Params:
  `after` (an event id: the ones written since), `limit`.
  """
  @spec events(String.t(), term(), map()) :: {:ok, map()} | {:error, :not_found | :forbidden}
  def events(user_id, id, params) when is_map(params) do
    with {:ok, result} <- readable(user_id, id) do
      events =
        Results.events(result.id,
          after: Gamend.UUIDv7.cast_or_nil(params["after"]),
          limit: to_int(params["limit"])
        )

      {:ok, %{result_id: result.id, events: events}}
    end
  end

  @doc "A result as a client reads it: its fields and `stats` by event key."
  @spec serialize(Result.t(), map()) :: map()
  def serialize(%Result{} = result, stats) do
    result
    |> Jason.encode!()
    |> Jason.decode!()
    |> Map.put("stats", Map.new(stats, fn {key, s} -> {key, %{count: s.count, sum: s.sum}} end))
  end

  defp readable(user_id, id) do
    user = Accounts.get_user(user_id)

    case Gamend.UUIDv7.cast_or_nil(id) && Results.get(id) do
      %Result{} = result ->
        if Results.readable?(result, user),
          do: {:ok, result},
          else: forbidden_or_hidden(result, user)

      _ ->
        {:error, :not_found}
    end
  end

  # A result the caller may not read is not there, unless it is theirs: a
  # stranger learns nothing from the answer, an owner learns it is hidden.
  defp forbidden_or_hidden(%Result{user_id: owner}, %User{id: owner}), do: {:error, :forbidden}
  defp forbidden_or_hidden(_result, _user), do: {:error, :not_found}

  defp to_int(value) when is_integer(value), do: value

  defp to_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp to_int(_value), do: nil
end
