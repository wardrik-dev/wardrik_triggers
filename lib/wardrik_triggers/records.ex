defmodule WardrikTriggers.Records do
  @moduledoc """
  Keeps each trigger in the store, with when it next runs, when it last ran, and what its feeds
  and webhook have seen.
  """

  alias WardrikTriggers.Trigger

  @prefix "triggers/"

  @doc "Returns the trigger `name` of the agent `agent_id`, with its version, or `nil`."
  @spec lookup(WardrikStore.t(), String.t(), String.t()) :: {map(), WardrikStore.vsn()} | nil
  def lookup(store, agent_id, name), do: WardrikStore.lookup(store, key(agent_id, name))

  @doc "Writes `record`, over `vsn` only, or as new with `nil`."
  @spec put(WardrikStore.t(), map(), WardrikStore.vsn() | nil) ::
          :ok | {:error, :conflict | term()}
  def put(store, %{"agent_id" => agent_id, "trigger" => %{"name" => name}} = record, vsn) do
    with {:ok, _vsn} <- WardrikStore.put(store, key(agent_id, name), record, if_vsn: vsn), do: :ok
  end

  @doc "Removes the trigger `name` of the agent `agent_id`."
  @spec delete(WardrikStore.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def delete(store, agent_id, name), do: WardrikStore.delete(store, key(agent_id, name))

  @doc "Returns every trigger kept, each as `{agent_id, name}`."
  @spec all(WardrikStore.t()) :: [{String.t(), String.t()}]
  def all(store), do: store |> WardrikStore.keys(@prefix) |> Enum.map(&parsed/1)

  @doc "Returns the triggers of the agent `agent_id`, by name."
  @spec of(WardrikStore.t(), String.t()) :: [String.t()]
  def of(store, agent_id) do
    for {^agent_id, name} <- all(store), do: name
  end

  @doc "Returns the trigger a record keeps."
  @spec trigger(map()) :: Trigger.t()
  def trigger(%{"trigger" => fields}) do
    {:ok, trigger} = Trigger.decode(fields)
    trigger
  end

  @doc "Returns when the record's trigger next runs, or `nil` for a webhook."
  @spec next_at(map()) :: DateTime.t() | nil
  def next_at(%{"next_at" => nil}), do: nil

  def next_at(%{"next_at" => text}) do
    {:ok, next_at, _offset} = DateTime.from_iso8601(text)
    next_at
  end

  @doc "Changes `record` with `fun`, over whatever another node wrote in between."
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
