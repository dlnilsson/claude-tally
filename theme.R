# Nord-inspired dark theme for claude-tally graphs

nord <- list(
  bg       = "#2E3440",
  bg_light = "#3B4252",
  fg       = "#D8DEE9",
  fg_dim   = "#4C566A",
  frost1   = "#8FBCBB",
  frost2   = "#88C0D0",
  frost3   = "#81A1C1",
  frost4   = "#5E81AC",
  green    = "#A3BE8C",
  red      = "#BF616A",
  orange   = "#D08770",
  yellow   = "#EBCB8B",
  purple   = "#B48EAD"
)

palette_tally <- c(
  nord$frost2, nord$green, nord$orange, nord$purple,
  nord$yellow, nord$frost4, nord$red, nord$frost1,
  "#A3D4C7", "#C9A5D1", "#D4A373", "#9CB4CC"
)

theme_tally <- function(base_size = 12) {
  ggplot2::theme_minimal(base_size = base_size) %+replace%
    ggplot2::theme(
      plot.background    = ggplot2::element_rect(fill = nord$bg, color = NA),
      panel.background   = ggplot2::element_rect(fill = nord$bg, color = NA),
      panel.grid.major   = ggplot2::element_line(color = nord$fg_dim, linewidth = 0.25),
      panel.grid.minor   = ggplot2::element_blank(),
      text               = ggplot2::element_text(color = nord$fg, family = "sans"),
      axis.text          = ggplot2::element_text(color = nord$fg),
      axis.title         = ggplot2::element_text(color = nord$fg, size = ggplot2::rel(0.9)),
      plot.title         = ggplot2::element_text(
        color = nord$frost2, face = "bold", size = ggplot2::rel(1.3),
        margin = ggplot2::margin(b = 6)
      ),
      plot.subtitle      = ggplot2::element_text(
        color = nord$fg, size = ggplot2::rel(0.85),
        margin = ggplot2::margin(b = 10)
      ),
      plot.caption       = ggplot2::element_text(color = nord$fg_dim, size = ggplot2::rel(0.7)),
      legend.background  = ggplot2::element_rect(fill = nord$bg_light, color = NA),
      legend.text        = ggplot2::element_text(color = nord$fg, size = ggplot2::rel(0.8)),
      legend.title       = ggplot2::element_text(color = nord$fg, size = ggplot2::rel(0.85)),
      legend.key         = ggplot2::element_rect(fill = NA, color = NA),
      strip.text         = ggplot2::element_text(color = nord$frost2, face = "bold"),
      plot.margin        = ggplot2::margin(12, 12, 12, 12)
    )
}

scale_color_tally <- function(...) {
  ggplot2::scale_color_manual(values = palette_tally, ...)
}

scale_fill_tally <- function(...) {
  ggplot2::scale_fill_manual(values = palette_tally, ...)
}

# Continuous fill gradient (for heatmap)
scale_fill_tally_c <- function(...) {
  ggplot2::scale_fill_gradient(low = nord$bg_light, high = nord$frost2, ...)
}
