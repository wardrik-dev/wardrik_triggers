defmodule WardrikTriggers.Target do
  @moduledoc """
  What triggers ask: the host's agents. `WardrikTriggers` calls it as `{module, config}`.
  """

  @doc """
  Asks the agent `agent_id` `prompt`, for the trigger `trigger`. With `overlap: :skip`, answers
  `:busy` and asks nothing while the agent is busy; with `:queue`, asks it anyway. `labels` are what
  the prompt holds: `["outside"]` where it carries a feed's entries or a webhook's request.
  """
  @callback ask(
              config :: term(),
              agent_id :: String.t(),
              prompt :: String.t(),
              opts :: [trigger: String.t(), overlap: :skip | :queue, labels: [String.t()]]
            ) :: :asked | :busy | :no_agent | {:error, term()}

  @doc "Hears how the trigger `trigger`'s run went, every run, asked or not."
  @callback fired(
              config :: term(),
              agent_id :: String.t(),
              trigger :: String.t(),
              WardrikTriggers.Trigger.status()
            ) ::
              :ok

  @doc "Resolves the secret a webhook names as `${NAME}`, as the agent `agent_id` holds it."
  @callback resolve_secret(config :: term(), agent_id :: String.t(), name :: String.t()) ::
              {:ok, String.t()} | :error
end
