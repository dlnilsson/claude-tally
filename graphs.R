#!/usr/bin/env Rscript

# claude-tally: Generate usage graphs from session data
# Usage: Rscript graphs.R [--db PATH] [--output-dir DIR]

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
  library(ggplot2)
  library(dplyr)
  library(lubridate)
  library(scales)
  library(tidyr)
  library(forcats)
  library(patchwork)
})

# Resolve script directory for sourcing theme.R
script_dir <- tryCatch(
  dirname(normalizePath(sys.frame(1)$ofile)),
  error = function(e) {
    args <- commandArgs(trailingOnly = FALSE)
    file_arg <- grep("^--file=", args, value = TRUE)
    if (length(file_arg) > 0) {
      dirname(normalizePath(sub("^--file=", "", file_arg[1])))
    } else {
      getwd()
    }
  }
)
source(file.path(script_dir, "theme.R"))

# -- CLI args ------------------------------------------------------------------

parse_args <- function() {
  args <- commandArgs(trailingOnly = TRUE)
  opts <- list(db = NULL, output_dir = ".")

  i <- 1L
  while (i <= length(args)) {
    if (args[i] == "--db" && i < length(args)) {
      opts$db <- args[i + 1L]
      i <- i + 2L
    } else if (args[i] == "--output-dir" && i < length(args)) {
      opts$output_dir <- args[i + 1L]
      i <- i + 2L
    } else {
      i <- i + 1L
    }
  }

  if (is.null(opts$db)) {
    data_home <- Sys.getenv("XDG_DATA_HOME", unset = "")
    if (data_home == "") {
      data_home <- file.path(Sys.getenv("HOME"), ".local", "share")
    }
    opts$db <- file.path(data_home, "claude-tally", "status.db")
  }

  opts
}

# -- Project name normalization ------------------------------------------------

normalize_project <- function(path) {
  home <- Sys.getenv("HOME")
  rel <- sub(paste0("^", gsub("([.\\\\|(){}^$*+?])", "\\\\\\1", home), "/?"), "", path)
  if (rel == "" || rel == path) return(basename(path))
  parts <- strsplit(rel, "/", fixed = TRUE)[[1]]
  skip <- c("dev", "private", "src", "projects", "work")
  idx <- which(!parts %in% skip)[1]
  if (is.na(idx)) return(rel)
  base <- parts[idx]
  # Strip worktree suffix (e.g. sendify.SEN-4231 -> sendify) but keep dotfiles
  if (!startsWith(base, ".")) {
    base <- sub("\\..*$", "", base)
  }
  base
}

# -- Data loading --------------------------------------------------------------

load_sessions <- function(db_path) {
  if (!file.exists(db_path)) {
    stop("Database not found: ", db_path, call. = FALSE)
  }

  db <- dbConnect(SQLite(), dbname = db_path, flags = SQLITE_RO)
  on.exit(dbDisconnect(db), add = TRUE)
  dbExecute(db, "PRAGMA busy_timeout = 5000")

  sql <- "
    SELECT
        session_id,
        recorded_at,
        COALESCE(raw ->> '$.session_name', '') AS session_name,
        COALESCE(raw ->> '$.model.display_name', 'unknown') AS model,
        COALESCE(raw ->> '$.cost.total_cost_usd', 0) AS cost_usd,
        COALESCE(raw ->> '$.cost.total_lines_added', 0) AS lines_added,
        COALESCE(raw ->> '$.cost.total_lines_removed', 0) AS lines_removed,
        COALESCE(raw ->> '$.cost.total_duration_ms', 0) AS duration_ms,
        COALESCE(raw ->> '$.context_window.total_input_tokens', 0) AS input_tokens,
        COALESCE(raw ->> '$.context_window.total_output_tokens', 0) AS output_tokens,
        COALESCE(raw ->> '$.workspace.project_dir', '') AS project_dir
    FROM status
    WHERE id IN (SELECT MAX(id) FROM status GROUP BY session_id)
    ORDER BY recorded_at
  "

  df <- dbGetQuery(db, sql)
  if (nrow(df) == 0) {
    stop("No session data found in database.", call. = FALSE)
  }

  df |>
    mutate(
      recorded_at     = ymd_hms(recorded_at),
      date            = as.Date(recorded_at),
      week            = floor_date(date, "week", week_start = 1),
      cost_usd        = as.numeric(cost_usd),
      lines_added     = as.numeric(lines_added),
      lines_removed   = as.numeric(lines_removed),
      duration_ms     = as.numeric(duration_ms),
      input_tokens    = as.numeric(input_tokens),
      output_tokens   = as.numeric(output_tokens),
      duration_min    = duration_ms / 60000,
      net_lines       = lines_added - lines_removed,
      project         = sapply(project_dir, normalize_project, USE.NAMES = FALSE)
    )
}

# -- Helper: top N projects + "Other" -----------------------------------------

top_projects <- function(df, n = 8) {
  top <- df |>
    group_by(project) |>
    summarise(total = sum(cost_usd, na.rm = TRUE), .groups = "drop") |>
    slice_max(total, n = n) |>
    pull(project)

  df |>
    mutate(project_grp = if_else(project %in% top, project, "Other")) |>
    mutate(project_grp = fct_relevel(project_grp, "Other", after = Inf))
}

# -- Graphs --------------------------------------------------------------------

plot_daily_cost <- function(df) {
  daily <- df |>
    group_by(date) |>
    summarise(cost = sum(cost_usd, na.rm = TRUE), sessions = n(), .groups = "drop")

  mean_cost <- mean(daily$cost)

  ggplot(daily, aes(date, cost)) +
    geom_col(fill = nord$frost4, alpha = 0.3, width = 0.8) +
    geom_line(color = nord$frost2, linewidth = 0.8) +
    geom_point(color = nord$frost2, size = 1.5) +
    geom_hline(yintercept = mean_cost, linetype = "dashed", color = nord$yellow, linewidth = 0.4) +
    annotate("text",
      x = max(daily$date), y = mean_cost,
      label = sprintf("mean $%.2f", mean_cost),
      color = nord$yellow, hjust = 1, vjust = -0.5, size = 3
    ) +
    scale_y_continuous(labels = dollar_format()) +
    labs(title = "Daily Cost", subtitle = "Total spend per day", x = NULL, y = "Cost (USD)") +
    theme_tally()
}

plot_weekly_cost <- function(df) {
  weekly <- top_projects(df) |>
    group_by(week, project_grp) |>
    summarise(cost = sum(cost_usd, na.rm = TRUE), .groups = "drop")

  ggplot(weekly, aes(week, cost, fill = project_grp)) +
    geom_col() +
    scale_y_continuous(labels = dollar_format()) +
    scale_fill_tally() +
    labs(
      title = "Weekly Cost by Project",
      subtitle = "Stacked by top projects",
      x = NULL, y = "Cost (USD)", fill = "Project"
    ) +
    theme_tally()
}

plot_cost_by_project <- function(df) {
  project_cost <- df |>
    group_by(project, model) |>
    summarise(cost = sum(cost_usd, na.rm = TRUE), .groups = "drop") |>
    mutate(project = fct_reorder(project, cost, .fun = sum))

  ggplot(project_cost, aes(cost, project, fill = model)) +
    geom_col() +
    scale_x_continuous(labels = dollar_format()) +
    scale_fill_tally() +
    labs(
      title = "Cost by Project",
      subtitle = "Colored by model",
      x = "Cost (USD)", y = NULL, fill = "Model"
    ) +
    theme_tally()
}

plot_lines_by_project <- function(df) {
  project_lines <- df |>
    group_by(project) |>
    summarise(
      added   = sum(lines_added, na.rm = TRUE),
      removed = sum(lines_removed, na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(project = fct_reorder(project, added - removed)) |>
    pivot_longer(cols = c(added, removed), names_to = "type", values_to = "lines") |>
    mutate(lines = if_else(type == "removed", -lines, lines))

  ggplot(project_lines, aes(lines, project, fill = type)) +
    geom_col() +
    scale_x_continuous(labels = comma_format()) +
    scale_fill_manual(values = c(added = nord$green, removed = nord$red), labels = c("Added", "Removed")) +
    labs(
      title = "Lines Changed by Project",
      subtitle = "Added vs removed",
      x = "Lines", y = NULL, fill = NULL
    ) +
    theme_tally()
}

plot_tokens_scatter <- function(df) {
  df2 <- top_projects(df, n = 6)

  ggplot(df2, aes(input_tokens, output_tokens, color = project_grp, size = cost_usd)) +
    geom_point(alpha = 0.7) +
    scale_x_continuous(labels = comma_format()) +
    scale_y_continuous(labels = comma_format()) +
    scale_size_continuous(range = c(1, 8), labels = dollar_format()) +
    scale_color_tally() +
    labs(
      title = "Input vs Output Tokens",
      subtitle = "Size = cost",
      x = "Input Tokens", y = "Output Tokens",
      color = "Project", size = "Cost"
    ) +
    theme_tally()
}

plot_cost_per_line <- function(df) {
  cpl <- df |>
    filter((lines_added + lines_removed) > 0) |>
    mutate(cost_per_line = cost_usd / (lines_added + lines_removed)) |>
    top_projects(n = 8) |>
    mutate(project_grp = fct_reorder(project_grp, cost_per_line, .fun = median))

  if (nrow(cpl) == 0) return(NULL)

  ggplot(cpl, aes(project_grp, cost_per_line, fill = project_grp)) +
    geom_boxplot(alpha = 0.7, outlier.color = nord$fg_dim, outlier.size = 1) +
    scale_y_continuous(labels = dollar_format()) +
    scale_fill_tally() +
    labs(
      title = "Cost per Line Changed",
      subtitle = "Sessions with code changes only",
      x = NULL, y = "$ / line"
    ) +
    guides(fill = "none") +
    theme_tally() +
    theme(axis.text.x = element_text(angle = 35, hjust = 1))
}

plot_duration_vs_cost <- function(df) {
  df2 <- top_projects(df, n = 6) |>
    filter(duration_min > 0)

  ggplot(df2, aes(duration_min, cost_usd, color = project_grp)) +
    geom_point(alpha = 0.7, size = 2) +
    geom_smooth(method = "lm", se = FALSE, color = nord$yellow, linewidth = 0.6) +
    scale_x_continuous(labels = comma_format()) +
    scale_y_continuous(labels = dollar_format()) +
    scale_color_tally() +
    labs(
      title = "Session Duration vs Cost",
      subtitle = "With linear trend",
      x = "Duration (minutes)", y = "Cost (USD)", color = "Project"
    ) +
    theme_tally()
}

plot_activity_heatmap <- function(df) {
  activity <- df |>
    mutate(
      wday  = wday(date, label = TRUE, abbr = TRUE, week_start = 1),
      yweek = isoweek(date),
      year  = isoyear(date)
    ) |>
    group_by(year, yweek, wday) |>
    summarise(cost = sum(cost_usd, na.rm = TRUE), .groups = "drop")

  ggplot(activity, aes(yweek, fct_rev(wday), fill = cost)) +
    geom_tile(color = nord$bg, linewidth = 0.5) +
    scale_fill_tally_c(labels = dollar_format()) +
    labs(
      title = "Activity Heatmap",
      subtitle = "Daily spend by week",
      x = "Week", y = NULL, fill = "Cost"
    ) +
    coord_equal() +
    theme_tally() +
    theme(panel.grid = element_blank())
}

# -- Output --------------------------------------------------------------------

save_plot <- function(p, filename, output_dir, width = 10, height = 6) {
  if (is.null(p)) return(invisible(NULL))
  path <- file.path(output_dir, filename)
  ggsave(path, p, width = width, height = height, dpi = 300, bg = nord$bg)
  cat("  ", path, "\n")
}

# -- Main ----------------------------------------------------------------------

main <- function() {
  opts <- parse_args()
  cat("Reading database:", opts$db, "\n")

  df <- load_sessions(opts$db)
  cat(sprintf("Loaded %d sessions (%s to %s)\n",
    nrow(df),
    format(min(df$date), "%Y-%m-%d"),
    format(max(df$date), "%Y-%m-%d")
  ))

  dir.create(opts$output_dir, showWarnings = FALSE, recursive = TRUE)

  # Generate all plots
  p1 <- plot_daily_cost(df)
  p2 <- plot_weekly_cost(df)
  p3 <- plot_cost_by_project(df)
  p4 <- plot_lines_by_project(df)
  p5 <- plot_tokens_scatter(df)
  p6 <- plot_cost_per_line(df)
  p7 <- plot_duration_vs_cost(df)
  p8 <- plot_activity_heatmap(df)

  # Individual PNGs
  cat("Saving PNGs:\n")
  save_plot(p1, "01-daily-cost.png", opts$output_dir)
  save_plot(p2, "02-weekly-cost.png", opts$output_dir)
  save_plot(p3, "03-cost-by-project.png", opts$output_dir)
  save_plot(p4, "04-lines-by-project.png", opts$output_dir)
  save_plot(p5, "05-tokens-scatter.png", opts$output_dir)
  save_plot(p6, "06-cost-per-line.png", opts$output_dir)
  save_plot(p7, "07-duration-vs-cost.png", opts$output_dir)
  save_plot(p8, "08-activity-heatmap.png", opts$output_dir)

  # Multi-page PDF
  pdf_path <- file.path(opts$output_dir, "claude-tally-report.pdf")
  cat("Saving PDF:", pdf_path, "\n")

  plots <- list(p1, p2, p3, p4, p5, p6, p7, p8)
  plots <- plots[!sapply(plots, is.null)]

  cairo_pdf(pdf_path, width = 12, height = 8, onefile = TRUE)
  for (i in seq(1, length(plots), by = 2)) {
    if (i + 1 <= length(plots)) {
      print(plots[[i]] + plots[[i + 1]] + plot_layout(ncol = 2))
    } else {
      print(plots[[i]])
    }
  }
  dev.off()

  cat("Done.\n")
}

main()
