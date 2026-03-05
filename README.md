# claude-tally

`claude-tally` is a small helper for Claude CLI statusline integrations.
It reads JSON from `stdin` and stores each status payload in a local SQLite database.
These are client-side metrics, generated only when using the Claude CLI tool with `/statusline` configured.

## Install

Install with Go:

```bash
go install github.com/dlnilsson/claude-tally@latest
```

Make sure your Go bin directory is on `PATH` (usually `$(go env GOPATH)/bin`).

## Claude CLI setup

1. In Claude, run:

```text
/statusline
```

2. Locate the generated statusline script (this confirms `/statusline` has created it):

```bash
head -n 5 $(jq -r .statusLine.command .claude/settings.json | awk '{print $2}')
```

3. Append this to that script:

```bash
#!/bin/bash
input=$(cat)
printf '%s' "$input" | claude-tally &
```

After this, statusline events will be piped into `claude-tally`.

## Storage location

The database is created at:

- `$XDG_DATA_HOME/claude-tally/status.db` (when `XDG_DATA_HOME` is set), or
- `~/.local/share/claude-tally/status.db` (default)

Each row includes:

- `recorded_at` (timestamp)
- `session_id`
- `raw` (full JSON payload)

## Example metrics

See [`queries.sql`](queries.sql) for ready-to-run SQLite examples, including:

- latest session snapshots
- token usage by session
- weekly cost totals
- weekly lines added/removed by project

Example query:

```sql
-- lines added, removed this week
SELECT
      raw ->> '$.workspace.project_dir' AS project_dir,
      COUNT(*) AS sessions,
      ROUND(SUM(raw ->> '$.cost.total_cost_usd'), 2) AS total_cost,
      SUM(raw ->> '$.cost.total_lines_added') AS lines_added,
      SUM(raw ->> '$.cost.total_lines_removed') AS lines_removed
  FROM status
  WHERE id IN (
      SELECT MAX(id) FROM status GROUP BY session_id
  )
  AND recorded_at >= date('now', 'weekday 0', '-6 days')
  GROUP BY project_dir
  ORDER BY total_cost DESC;
```

Example results:

| project\_dir | sessions | total\_cost | lines\_added | lines\_removed |
| :--- | :--- | :--- | :--- | :--- |
| /home/dln/dev/frontend | 3 | 16.78 | 1090 | 165 |
| /home/dln/dev/backend | 10 | 14.69 | 570 | 155 |
