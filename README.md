# WardrikTriggers

Ask agents something on a clock, when a feed has something new, or when a service sends a webhook.

## Install

```elixir
def deps do
  [
    {:wardrik_triggers, "~> 0.1"}
  ]
end
```

## Start it

Add `WardrikTriggers` to your supervision tree with a [WardrikStore](https://hexdocs.pm/wardrik_store)
to keep triggers in, and a `WardrikTriggers.Target`, which asks your agents. Here it's beside
[WardrikCore](https://hexdocs.pm/wardrik_core)'s agents, and a
[WardrikVault](https://hexdocs.pm/wardrik_vault) that holds webhook secrets:

```elixir
store = WardrikStore.ETS.new(name: MyApp.Store)

children = [
  {WardrikStore, store},
  {WardrikVault, name: MyApp.Vault, store: store, keys: [System.fetch_env!("VAULT_KEY")]},
  {WardrikCore, backend: {WardrikStore.Durable, store: store}},
  {WardrikTriggers, name: MyApp.Triggers, store: store, target: {MyApp.Triggered, []}}
]
```

The target asks the agent, hears how each run went, and resolves webhook secrets:

```elixir
defmodule MyApp.Triggered do
  @behaviour WardrikTriggers.Target

  require Logger

  @impl true
  def ask(_config, agent_id, prompt, opts) do
    case WardrikCore.whereis(agent_id) do
      nil -> :no_agent
      agent -> asked(agent, prompt, opts)
    end
  end

  @impl true
  def fired(_config, agent_id, trigger, status),
    do: Logger.info("#{agent_id} ran #{trigger}: #{status}")

  @impl true
  def resolve_secret(_config, _agent_id, name) do
    case WardrikVault.fetch(MyApp.Vault, %WardrikCore.Principal{id: "acme"}, name) do
      {:ok, secret} -> {:ok, secret}
      {:error, _reason} -> :error
    end
  end

  defp asked(agent, prompt, opts) do
    if opts[:overlap] == :skip and WardrikCore.status(agent) != :idle do
      :busy
    else
      :ok = WardrikCore.ask(agent, prompt, %{trigger: opts[:trigger]})
      :asked
    end
  end
end
```

| Key | Takes | Unless set |
| --- | --- | --- |
| `name` | the name you reach the triggers by | required |
| `store` | the `WardrikStore` to keep them in | required |
| `target` | a `WardrikTriggers.Target`, as `{module, config}` | required |
| `req_options` | options for reading feeds, as `Req` takes them | `[]` |
| `reconcile` | how often each node reads every trigger again, in milliseconds | a minute |

Every run emits `[:wardrik_triggers, :fired]`, with the `agent_id`, the `trigger` and its `status`,
for watching.

With [Wardrik](https://hexdocs.pm/wardrik), all of this is done for you, and triggers are part of
an agent's definition. See [Trigger agents](https://hexdocs.pm/wardrik/triggers.html).

## Give an agent triggers

Start the agent, then give it its triggers:

```elixir
{:ok, _agent} = WardrikCore.start_agent(agent_id: "acme/digest", model: "anthropic:claude-haiku-4-5")
{:ok, _version} = WardrikVault.put(MyApp.Vault, %WardrikCore.Principal{id: "acme"}, "ISSUES_HOOK_SECRET", "s3cret")

WardrikTriggers.put(MyApp.Triggers, "acme/digest", [
  %{"name" => "daily", "every" => "0 9 * * *", "timezone" => "America/Los_Angeles", "prompt" => "Write today's update."},
  %{"name" => "rivals", "every" => "6h", "feed" => "https://rivalco.example/changelog.rss", "prompt" => "What changed?"},
  %{"name" => "issues", "webhook" => %{"secret" => "${ISSUES_HOOK_SECRET}"}, "prompt" => "Triage it."}
])
#=> :ok
```

A trigger is a map with string keys, as an agent file writes it. `put/3` replaces an agent's
triggers; `set/3` and `remove/3` change one, and `list/2` says when each next runs:

```elixir
WardrikTriggers.list(MyApp.Triggers, "acme/digest")
#=> [
#=>   {%WardrikTriggers.Trigger{name: "daily", every: "0 9 * * *", timezone: "America/Los_Angeles", ...},
#=>    ~U[2026-10-24 16:00:00Z]},
#=>   {%WardrikTriggers.Trigger{name: "issues", webhook: %{secret: "${ISSUES_HOOK_SECRET}", verify: :shared}, ...}, nil},
#=>   ...
#=> ]
```

Every function takes the name you gave it, and raises saying so where it isn't started.

| Key | Means |
| --- | --- |
| `every` | a cron expression, as `0 9 * * 1` or `@daily`, or an interval of at least a minute, as `30m`, `2h` or `1d` |
| `timezone` | the time zone a cron expression is read in, as `Europe/Berlin`; `Etc/UTC` unless set |
| `prompt` | what the agent is asked |
| `name` | the trigger's name; `trigger-1`, `trigger-2` and so on by its place unless set |
| `overlap` | `skip` leaves a busy agent be, `queue` asks it anyway; `skip` unless set, `queue` for a webhook |
| `missed` | `run_once` runs once for what was missed while nothing ran, `skip` lets it go |
| `jitter` | up to this many seconds added to each run |
| `feed` | an RSS or Atom feed's URL, or a list of them |
| `webhook` | `secret`, as `${NAME}`, and `verify`, `shared` or `standard`, in place of `every` |

## On a clock

A cron expression is read on `timezone`'s clock. A time the clocks skip runs at the first instant
after the gap, and a time they repeat runs on its first pass only. An interval counts from when the
trigger was set or last ran.

A run more than a minute late, because nothing ran it, runs once, however many were missed.
`missed: skip` lets them go.

## Watching a feed

A trigger with `feed` asks only when a feed holds entries it hasn't seen, with up to 20 of them
under the prompt. Its first run only notes what each feed holds. A feed that hasn't changed answers
with nothing, and a run fails only when no feed reads.

## Receiving a webhook

Hand each request a service sends to `deliver/4`, with its raw body and its headers. In a
`Plug.Router`:

```elixir
post "/hooks/:org/:name/:trigger" do
  {:ok, body, conn} = Plug.Conn.read_body(conn)
  request = %{body: body, headers: Map.new(conn.req_headers), path_secret: nil}

  case WardrikTriggers.deliver(MyApp.Triggers, "#{org}/#{name}", trigger, request) do
    :ok -> send_resp(conn, 202, "")
    {:error, :not_found} -> send_resp(conn, 404, "")
    {:error, _busy} -> send_resp(conn, 503, "")
  end
end
```

Read the body before `Plug.Parsers` does, since a signature covers the exact bytes.
[WardrikHTTP](https://hexdocs.pm/wardrik_http) serves this route for a Wardrik.

With `verify: shared`, a request presents the secret as a bearer token or at the end of its path.
With `verify: standard`, it's signed as [Standard Webhooks](https://www.standardwebhooks.com/) says.
The target resolves the secret `${NAME}` names. A request that doesn't prove itself is
`{:error, :not_found}`. Each request is asked about once, by its `Idempotency-Key`, its
`webhook-id`, or its body.

## In a cluster

Every node runs triggers. A run is claimed by moving the trigger's next run on in the store, over
the version the node read, so it runs once in the cluster, and a lost node's triggers carry on from
another.

## License

Apache-2.0
