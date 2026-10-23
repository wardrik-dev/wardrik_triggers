defmodule WardrikTriggers.WebhookTest do
  use ExUnit.Case, async: true

  alias WardrikTriggers.Webhook

  @now ~U[2026-10-22 09:00:00Z]

  defp request(headers, body \\ "{}", path_secret \\ nil),
    do: %{headers: headers, body: body, path_secret: path_secret}

  defp signed(id, at, body) do
    signature = :hmac |> :crypto.mac(:sha256, "key", "#{id}.#{at}.#{body}") |> Base.encode64()

    %{
      "webhook-id" => id,
      "webhook-timestamp" => "#{at}",
      "webhook-signature" => "v0,x v1,#{signature}"
    }
  end

  test "takes the shared secret as a bearer token, or at the end of the path" do
    assert :ok =
             Webhook.verify(
               :shared,
               "s3cret",
               request(%{"authorization" => "Bearer s3cret"}),
               @now
             )

    assert :ok = Webhook.verify(:shared, "s3cret", request(%{}, "{}", "s3cret"), @now)

    assert {:error, "it doesn't present the secret"} =
             Webhook.verify(:shared, "s3cret", request(%{"authorization" => "Bearer nope"}), @now)

    assert {:error, _why} = Webhook.verify(:shared, "s3cret", request(%{}), @now)
  end

  test "checks a Standard Webhooks signature, and how old it is" do
    secret = "whsec_" <> Base.encode64("key")
    at = DateTime.to_unix(@now)

    assert :ok = Webhook.verify(:standard, secret, request(signed("msg_1", at, "{}")), @now)

    assert {:error, "its signature doesn't match"} =
             Webhook.verify(
               :standard,
               secret,
               request(signed("msg_1", at, "{}"), "{\"x\":1}"),
               @now
             )

    assert {:error, "it was signed too long ago"} =
             Webhook.verify(:standard, secret, request(signed("msg_1", at - 600, "{}")), @now)

    assert {:error, "it has no webhook-id header"} =
             Webhook.verify(:standard, secret, request(%{}), @now)

    headers = %{signed("msg_1", at, "{}") | "webhook-timestamp" => "soon"}

    assert {:error, "its webhook-timestamp isn't a time"} =
             Webhook.verify(:standard, secret, request(headers), @now)
  end

  test "names a request by its idempotency key, its webhook id, or its body" do
    assert Webhook.id(request(%{"idempotency-key" => "k", "webhook-id" => "w"})) == "k"
    assert Webhook.id(request(%{"webhook-id" => "w"})) == "w"

    assert Webhook.id(request(%{}, "{}")) ==
             Base.encode16(:crypto.hash(:sha256, "{}"), case: :lower)
  end

  test "writes the body under the prompt, its first 32,768 characters" do
    prompt = Webhook.prompt("Triage it.", request(%{}, String.duplicate("a", 40_000)))
    assert String.length(prompt) == String.length("Triage it.\n\n") + 32_768
  end
end
