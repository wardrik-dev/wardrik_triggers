defmodule WardrikTriggers do
  @moduledoc """
  Triggers ask agents something without anyone typing: on a clock, when a feed they watch has new
  entries, or when a service sends them a webhook.

      children = [
        {WardrikTriggers, name: MyApp.Triggers, store: store, target: {MyApp.Agents, []}}
      ]

      :ok =
        WardrikTriggers.put(MyApp.Triggers, "acme/digest", [
          %{"name" => "daily", "every" => "0 9 * * *", "prompt" => "Write today's update."}
        ])

  Each trigger runs once in the cluster, on whichever node claims it first, and asks its agent
  through the `WardrikTriggers.Target` given as `target`.
  """

  use Supervisor

  alias WardrikTriggers.Records
  alias WardrikTriggers.Run
  alias WardrikTriggers.Scheduler
  alias WardrikTriggers.Trigger

  @doc """
  Starts the triggers. Takes `:name`, `:store`, the `WardrikStore` they're kept in, `:target`, a
  `WardrikTriggers.Target` as `{module, config}`, `:req_options` for reading feeds, and
  `:reconcile`, how often each node reads every trigger again, a minute unless set.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    opts =
      Keyword.validate!(opts, [
        :name,
        :store,
        :target,
        req_options: [],
        reconcile: :timer.minutes(1)
      ])

    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, Map.new(opts), name: name)
  end

  @doc """
  Gives the agent `agent_id` the triggers `fields` describe, in place of those it had. A trigger
  whose `every` and `timezone` stay keeps its next run.
  """
  @spec put(atom(), String.t(), [map()]) :: :ok | {:error, String.t()}
  def put(triggers, agent_id, fields) do
    with {:ok, decoded} <- decode_all(fields),
         :ok <- remove_others(triggers, agent_id, Enum.map(decoded, & &1.name)) do
      Enum.each(
        decoded,
        &({:ok, _trigger} = GenServer.call(scheduler(triggers), {:set, agent_id, &1}))
      )
    end
  end

  @doc "Sets one of the agent `agent_id`'s triggers, as `fields` describe it."
  @spec set(atom(), String.t(), map()) :: {:ok, Trigger.t()} | {:error, String.t()}
  def set(triggers, agent_id, fields) do
    with {:ok, trigger} <- Trigger.decode(fields),
         do: GenServer.call(scheduler(triggers), {:set, agent_id, trigger})
  end

  @doc "Removes the agent `agent_id`'s trigger `name`."
  @spec remove(atom(), String.t(), String.t()) :: :ok | {:error, :not_found}
  def remove(triggers, agent_id, name),
    do: GenServer.call(scheduler(triggers), {:remove, agent_id, name})

  @doc "Lists the agent `agent_id`'s triggers, each with when it next runs, `nil` for a webhook."
  @spec list(atom(), String.t()) :: [{Trigger.t(), DateTime.t() | nil}]
  def list(triggers, agent_id) do
    store = settings(triggers).store

    for name <- Records.of(store, agent_id),
        {record, _vsn} <- [Records.lookup(store, agent_id, name)],
        do: {Records.trigger(record), Records.next_at(record)}
  end

  @doc """
  Asks the agent `agent_id` about a request a service sent its webhook trigger `name`, once the
  request proves itself, and only once. A request that doesn't is `{:error, :not_found}`.
  """
  @spec deliver(atom(), String.t(), String.t(), WardrikTriggers.Webhook.request()) ::
          :ok | {:error, :not_found | :busy | :no_agent | :failed}
  def deliver(triggers, agent_id, name, request),
    do: Run.webhook(settings(triggers), agent_id, name, request)

  @doc "Reads every trigger from the store again, as each node does every so often."
  @spec reconcile(atom()) :: :ok
  def reconcile(triggers), do: GenServer.call(scheduler(triggers), :reconcile)

  @impl Supervisor
  def init(opts) do
    settings = %{
      store: WardrikStore.scope(opts.store, "wardrik_triggers"),
      target: opts.target,
      req_options: opts.req_options,
      reconcile: opts.reconcile,
      tasks: Module.concat(opts.name, "Tasks"),
      scheduler: scheduler(opts.name)
    }

    :ets.new(table(opts.name), [:named_table, :protected, read_concurrency: true])
    true = :ets.insert(table(opts.name), {:settings, settings})

    children = [{Task.Supervisor, name: settings.tasks}, {Scheduler, settings}]
    Supervisor.init(children, strategy: :rest_for_one)
  end

  defp scheduler(triggers), do: Module.concat(triggers, "Scheduler")
  defp table(triggers), do: Module.concat(triggers, "Settings")

  defp settings(triggers) do
    [{:settings, settings}] = :ets.lookup(table(triggers), :settings)
    settings
  rescue
    ArgumentError ->
      reraise ArgumentError,
              "#{inspect(triggers)} isn't started. Add {WardrikTriggers, name: #{inspect(triggers)}, store: store, target: target} to your supervision tree, ahead of what uses it.",
              __STACKTRACE__
  end

  defp decode_all(fields) do
    fields
    |> Enum.with_index(1)
    |> Enum.map(fn {trigger, index} -> Trigger.decode(trigger, index) end)
    |> Enum.reduce({:ok, []}, &collected/2)
    |> reversed()
  end

  defp collected({:ok, trigger}, {:ok, triggers}), do: {:ok, [trigger | triggers]}
  defp collected({:error, why}, {:ok, _triggers}), do: {:error, why}
  defp collected(_result, error), do: error

  defp reversed({:ok, triggers}), do: {:ok, Enum.reverse(triggers)}
  defp reversed(error), do: error

  defp remove_others(triggers, agent_id, keeping) do
    store = settings(triggers).store

    for name <- Records.of(store, agent_id), name not in keeping do
      remove(triggers, agent_id, name)
    end

    :ok
  end
end
