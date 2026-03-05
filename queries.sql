-- This uses MAX(id) per session_id to grab the most recent row for each session. You can pull specific fields from the JSON too, e.g.:
SELECT
    session_id,
    recorded_at,
    raw ->> '$.model.display_name' AS model,
    raw ->> '$.cost.total_cost_usd' AS cost
FROM status
WHERE
    id IN (
        SELECT MAX(id) FROM status
        GROUP BY session_id
    )
ORDER BY recorded_at DESC;


-- grab latest
SELECT
    session_id,
    recorded_at,
    JSON(raw)
FROM status
WHERE
    id IN (
        SELECT MAX(id) FROM status
        GROUP BY session_id
    )
ORDER BY recorded_at DESC;


-- select token usage
SELECT
    session_id,
    recorded_at,
    raw ->> '$.model.display_name' AS model,
    raw ->> '$.cost.total_cost_usd' AS cost,
    raw ->> '$.context_window.total_input_tokens' AS input_tokens,
    raw ->> '$.context_window.total_output_tokens' AS output_tokens,
    raw ->> '$.workspace.project_dir' AS project_dir
FROM status
WHERE
    id IN (
        SELECT MAX(id) FROM status
        GROUP BY session_id
    )
ORDER BY recorded_at DESC;


-- delete old entries
DELETE FROM status
WHERE id NOT IN (
    SELECT MAX(id) FROM status
    GROUP BY session_id
);


-- all this week
SELECT
    session_id,
    recorded_at,
    raw ->> '$.model.display_name' AS model,
    raw ->> '$.cost.total_cost_usd' AS cost,
    raw ->> '$.context_window.total_input_tokens' AS input_tokens,
    raw ->> '$.context_window.total_output_tokens' AS output_tokens,
    raw ->> '$.workspace.project_dir' AS project_dir
FROM status
WHERE
    id IN (
        SELECT MAX(id) FROM status
        GROUP BY session_id
    )
    AND recorded_at >= DATE('now', 'weekday 0', '-6 days')
ORDER BY recorded_at DESC;

-- sum cost this week
SELECT ROUND(SUM(raw ->> '$.cost.total_cost_usd'), 2) AS total_cost
FROM status
WHERE id IN (
    SELECT MAX(id) FROM status
    GROUP BY session_id
)
AND recorded_at >= DATE('now', 'weekday 0', '-6 days');

-- lines added, removed this week
SELECT
    raw ->> '$.workspace.project_dir' AS project_dir,
    COUNT(*) AS sessions,
    ROUND(SUM(raw ->> '$.cost.total_cost_usd'), 2) AS total_cost,
    SUM(raw ->> '$.cost.total_lines_added') AS lines_added,
    SUM(raw ->> '$.cost.total_lines_removed') AS lines_removed
FROM status
WHERE
    id IN (
        SELECT MAX(id) FROM status
        GROUP BY session_id
    )
    AND recorded_at >= DATE('now', 'weekday 0', '-6 days')
GROUP BY project_dir
ORDER BY total_cost DESC;
