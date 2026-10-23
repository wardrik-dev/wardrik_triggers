defmodule WardrikTriggers.Test.Target do
  @moduledoc "A target that tells the test what it was asked, and answers as the test says."
  @behaviour WardrikTriggers.Target

  @impl true
  def ask(%{test: test, answer: answer}, agent_id, prompt, opts) do
    send(test, {:asked, agent_id, prompt, opts})
    answer
  end

  @impl true
  def fired(%{test: test}, agent_id, trigger, status) do
    send(test, {:fired, agent_id, trigger, status})
    :ok
  end

  @impl true
  def resolve_secret(_config, _agent_id, "HOOK_SECRET"), do: {:ok, "s3cret"}

  def resolve_secret(_config, _agent_id, "STANDARD_SECRET"),
    do: {:ok, "whsec_" <> Base.encode64("key")}

  def resolve_secret(_config, _agent_id, _name), do: :error
end
