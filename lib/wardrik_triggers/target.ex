defmodule WardrikTriggers.Target do
  @moduledoc """
  Connects triggers to your agents. Given to `WardrikTriggers` as `:target`, as `{module, config}`.

  Each callback gets `config` as its first argument.
  """

  @doc """
  Asks `agent_id` `prompt`.

  ## Options

    * `:trigger` - the trigger's name.
    * `:overlap` - `:skip` to return `:busy` and ask nothing while the agent is busy. `:queue` to
      ask anyway.
    * `:labels` - `["outside"]` when the prompt holds feed entries or a webhook body. `[]`
      otherwise.

  Return `:no_agent` if there's no such agent. `{:error, reason}` is logged and reported as
  `:failed`.
  """
  @callback ask(
              config :: term(),
              agent_id :: String.t(),
              prompt :: String.t(),
              opts :: [trigger: String.t(), overlap: :skip | :queue, labels: [String.t()]]
            ) :: :asked | :busy | :no_agent | {:error, term()}

  @doc "Called after every run of `trigger`, with how it went."
  @callback fired(
              config :: term(),
              agent_id :: String.t(),
              trigger :: String.t(),
              WardrikTriggers.Trigger.status()
            ) ::
              :ok

  @doc "Returns the secret `name` held for `agent_id`. A webhook names it as `${NAME}`."
  @callback resolve_secret(config :: term(), agent_id :: String.t(), name :: String.t()) ::
              {:ok, String.t()} | :error
end
