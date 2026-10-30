defmodule WardrikTriggers.Records do
  @moduledoc """
  Stores triggers. Each record holds the trigger, its next and last run, and what its feeds and
  webhook have seen.
  """

  alias WardrikTriggers.Trigger

  @prefix "triggers/"

  @doc "Returns the record for trigger `name` of `agent_id` and its version, or `nil`."
  @spec lookup(WardrikStore.t(), String.t(), String.t()) :: {map(), WardrikStore.vsn()} | nil
  def lookup(store, agent_id, name), do: WardrikStore.lookup(store, key(agent_id, name))

  @doc """
  Writes `record` if the stored version is `vsn`. Pass `nil` to create it.

  Returns `{:error, :conflict}` if the version differs.
  """
  @spec put(WardrikStore.t(), map(), WardrikStore.vsn() | nil) ::
          :ok | {:error, :conflict | term()}
  def put(store, %{"agent_id" => agent_id, "trigger" => %{"name" => name}} = record, vsn) do
    with {:ok, _vsn} <- WardrikStore.put(store, key(agent_id, name), record, if_vsn: vsn), do: :ok
  end

  @doc "Deletes trigger `name` of `agent_id`."
  @spec delete(WardrikStore.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def delete(store, agent_id, name), do: WardrikStore.delete(store, key(agent_id, name))

  @doc "Returns every stored trigger as `{agent_id, name}`."
  @spec all(WardrikStore.t()) :: [{String.t(), String.t()}]
  def all(store), do: store |> WardrikStore.keys(@prefix) |> Enum.map(&parsed/1)

  @doc "Returns the trigger names of `agent_id`."
  @spec of(WardrikStore.t(), String.t()) :: [String.t()]
  def of(store, agent_id) do
    for {^agent_id, name} <- all(store), do: name
  end

  @doc "Returns the record's trigger."
  @spec trigger(map()) :: Trigger.t()
  def trigger(%{"trigger" => fields}) do
    {:ok, trigger} = Trigger.decode(fields)
    trigger
  end

  @doc "Returns the record's next run, or `nil` for a webhook."
  @spec next_at(map()) :: DateTime.t() | nil
  def next_at(%{"next_at" => nil}), do: nil

  def next_at(%{"next_at" => text}) do
    {:ok, next_at, _offset} = DateTime.from_iso8601(text)
    next_at
  end

  @doc """
  Updates the record with `fun`. Retries on a conflicting write.

  Returns `{:error, :not_found}` if there's no record.
  """
  @spec update(WardrikStore.t(), String.t(), String.t(), (map() -> map())) ::
          :ok | {:error, term()}
  def update(store, agent_id, name, fun) do
    case lookup(store, agent_id, name) do
      nil ->
        {:error, :not_found}

      {record, vsn} ->
        case put(store, fun.(record), vsn) do
          {:error, :conflict} -> update(store, agent_id, name, fun)
          done -> done
        end
    end
  end

  defp key(agent_id, name), do: @prefix <> URI.encode_www_form(agent_id) <> "/" <> name

  defp parsed(@prefix <> rest) do
    [agent_id, name] = String.split(rest, "/", parts: 2)
    {URI.decode_www_form(agent_id), name}
  end
end
