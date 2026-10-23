defmodule WardrikTriggers.Webhook do
  @moduledoc """
  Proves a webhook request with the trigger's secret, and names it so it's asked about once.

  With `verify: :shared`, a request presents the secret as `Authorization: Bearer SECRET`, or at
  the end of its path. With `verify: :standard`, it's signed as the
  [Standard Webhooks](https://www.standardwebhooks.com/) spec says, over its id, its time and its
  body, and a request more than five minutes old doesn't verify.
  """

  @tolerance 300
  @body 32_768

  @typedoc "A request: its raw `body`, its `headers` with lowercase names, and a `path_secret`."
  @type request() :: %{
          required(:body) => String.t(),
          required(:headers) => %{String.t() => String.t()},
          optional(:path_secret) => String.t() | nil
        }

  @doc "Returns `:ok` if `request` proves itself with `secret`, or why it doesn't."
  @spec verify(:shared | :standard, String.t(), request(), DateTime.t()) ::
          :ok | {:error, String.t()}
  def verify(:shared, secret, request, _now) do
    presented = bearer(request.headers["authorization"]) || Map.get(request, :path_secret)

    if same?(presented, secret),
      do: :ok,
      else: {:error, "it doesn't present the secret"}
  end

  def verify(:standard, secret, %{headers: headers, body: body}, now) do
    with {:ok, id} <- header(headers, "webhook-id"),
         {:ok, timestamp} <- header(headers, "webhook-timestamp"),
         {:ok, signatures} <- header(headers, "webhook-signature"),
         :ok <- recent(timestamp, now) do
      expected = signature(secret, "#{id}.#{timestamp}.#{body}")

      if Enum.any?(String.split(signatures, " "), &same?(&1, "v1," <> expected)),
        do: :ok,
        else: {:error, "its signature doesn't match"}
    end
  end

  @doc "Returns the request's id: its `Idempotency-Key`, its `webhook-id`, or its body's hash."
  @spec id(request()) :: String.t()
  def id(%{headers: headers, body: body}) do
    headers["idempotency-key"] || headers["webhook-id"] ||
      Base.encode16(:crypto.hash(:sha256, body), case: :lower)
  end

  @doc "Writes the request's body under `prompt`, its first #{@body} characters."
  @spec prompt(String.t(), request()) :: String.t()
  def prompt(prompt, %{body: body}), do: prompt <> "\n\n" <> String.slice(body, 0, @body)

  defp bearer("Bearer " <> token), do: token
  defp bearer(_header), do: nil

  defp header(headers, name) do
    case Map.fetch(headers, name) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, "it has no #{name} header"}
    end
  end

  defp recent(timestamp, now) do
    case Integer.parse(timestamp) do
      {seconds, ""} ->
        if abs(DateTime.to_unix(now) - seconds) <= @tolerance,
          do: :ok,
          else: {:error, "it was signed too long ago"}

      _not_a_time ->
        {:error, "its webhook-timestamp isn't a time"}
    end
  end

  defp signature("whsec_" <> key, content), do: signature(Base.decode64!(key), content)

  defp signature(key, content),
    do: :hmac |> :crypto.mac(:sha256, key, content) |> Base.encode64()

  defp same?(presented, expected)
       when is_binary(presented) and byte_size(presented) == byte_size(expected),
       do: :crypto.hash_equals(presented, expected)

  defp same?(_presented, _expected), do: false
end
