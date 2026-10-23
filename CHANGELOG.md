# Changelog

## 0.1.0 (unreleased)

- Triggers that ask an agent something on a cron expression read in a time zone, or on an interval,
  with jitter, and once for runs missed while nothing ran them.
- Feeds, RSS or Atom, that ask only when they hold entries not seen before.
- Webhooks, proved by a shared secret or a Standard Webhooks signature, asked about once each.
- Each trigger runs once in a cluster, claimed in a `WardrikStore`.
