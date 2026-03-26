# ========================================================================
# publication_figures.R
# Publication-quality and poster-grade map figures
# Inspired by Milos Agathon's cartographic style (github.com/milos-agathon)
#
# Adds: scale bars, north arrows (ggspatial), clean panel layouts,
# bivariate change overlays, and a 3-panel summary figure.
#
# Outputs: figures/publication/
# ========================================================================

source("Scripts/config.R")

ensure_pkgs <- function(pkgs) {
  miss <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(miss)) install.packages(miss, dependencies = TRUE)
}
ensure_pkgs(c("terra", "ggplot2", "tidyterra", "ggspatial",
              "patchwork", "cowplot", "scales", "sf", "dplyr", "RColorBrewer"))

suppressPackageStartupMessages({
  library(terra)
  library(ggplot2)
  library(tidyterra)
  library(ggspatial)
  library(patchwork)
  library(scales)
  library(sf)
  library(dplyr)
})

out_dir <- "figures/publication"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ---- Helper: clip raster at percentile -----------------------------------
clip_pct <- function(r, lo = 0.01, hi = 0.99) {
  v <- values(r)
  v <- v[is.finite(v)]
  clamp(r, as.numeric(quantile(v, lo)), as.numeric(quantile(v, hi)))
}

# ---- Helper: standard map theme (Milos Agathon style) -------------------
theme_map <- function(base_size = 13) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title    = element_text(face = "bold", hjust = 0.5, size = base_size + 1),
      plot.subtitle = element_text(hjust = 0.5, colour = "grey40", size = base_size - 1),
      plot.caption  = element_text(hjust = 0, colour = "grey55", size = 9),
      axis.title    = element_blank(),
      axis.text     = element_text(size = 8, colour = "grey50"),
      legend.position  = "right",
      legend.title     = element_text(size = 10, face = "bold"),
      legend.text      = element_text(size = 9),
      panel.grid.major = element_line(colour = "grey90", linewidth = 0.3),
      panel.grid.minor = element_blank(),
      plot.background  = element_rect(fill = "white", colour = NA),
      panel.background = element_rect(fill = "#f0f4f8", colour = NA)
    )
}

caption_text <- paste0(
  "Data: Google Satellite Embeddings V1 (64-band, 10m) via Google Earth Engine\n",
  "Study area: Yellow River Delta (118.35–119.35°E, 37.35–38.15°N) | ",
  YEAR_BASELINE, "–", YEAR_TARGET
)

# ========================================================================
# Figure 1: MAD Change Map with scale bar and north arrow
# ========================================================================
cat("Figure 1: MAD change map...\n")

mad_path <- if (file.exists(PATHS$mad_roi)) PATHS$mad_roi else
  "results/embeddings_delta/mad_2018_2024.tif"

if (file.exists(mad_path)) {
  mad_r <- clip_pct(rast(mad_path))

  p_mad <- ggplot() +
    geom_spatraster(data = mad_r) +
    scale_fill_distiller(
      palette  = "YlOrRd",
      direction = 1,
      name     = "MAD",
      na.value = "transparent",
      labels   = label_number(accuracy = 0.01)
    ) +
    annotation_scale(
      location = "bl", width_hint = 0.25,
      text_col = "grey30", bar_cols = c("grey30", "white")
    ) +
    annotation_north_arrow(
      location = "tr",
      style    = north_arrow_fancy_orienteering(
        fill = c("grey30", "white"), text_col = "grey30"
      ),
      height = unit(1.2, "cm"), width = unit(1.2, "cm")
    ) +
    labs(
      title    = "Land Cover Change — Mean Absolute Difference",
      subtitle = paste0(YEAR_BASELINE, " \u2192 ", YEAR_TARGET,
                        "  |  Yellow River Delta, Shandong Province"),
      caption  = caption_text
    ) +
    theme_map()

  ggsave(file.path(out_dir, "fig1_mad_change.png"),
         p_mad, width = 9, height = 6.5, dpi = 300)
  cat("  Saved fig1_mad_change.png\n")
}

# ========================================================================
# Figure 2: Cosine Change Map
# ========================================================================
cat("Figure 2: Cosine change map...\n")

cos_path <- if (file.exists(PATHS$cos_roi)) PATHS$cos_roi else
  "results/embeddings_delta/cosine_change_2018_2024.tif"

if (file.exists(cos_path)) {
  cos_r <- clip_pct(rast(cos_path))

  p_cos <- ggplot() +
    geom_spatraster(data = cos_r) +
    scale_fill_distiller(
      palette  = "Spectral",
      direction = -1,
      name     = "1 - cosine",
      na.value = "transparent",
      labels   = label_number(accuracy = 0.001)
    ) +
    annotation_scale(
      location = "bl", width_hint = 0.25,
      text_col = "grey30", bar_cols = c("grey30", "white")
    ) +
    annotation_north_arrow(
      location = "tr",
      style    = north_arrow_fancy_orienteering(
        fill = c("grey30", "white"), text_col = "grey30"
      ),
      height = unit(1.2, "cm"), width = unit(1.2, "cm")
    ) +
    labs(
      title    = "Land Cover Change — Cosine Dissimilarity",
      subtitle = paste0(YEAR_BASELINE, " \u2192 ", YEAR_TARGET,
                        "  |  Yellow River Delta, Shandong Province"),
      caption  = caption_text
    ) +
    theme_map()

  ggsave(file.path(out_dir, "fig2_cosine_change.png"),
         p_cos, width = 9, height = 6.5, dpi = 300)
  cat("  Saved fig2_cosine_change.png\n")
}

# ========================================================================
# Figure 3: Dynamic World land cover — 2018 vs 2024 side-by-side
# ========================================================================
cat("Figure 3: Dynamic World 2018 vs 2024...\n")

if (file.exists(PATHS$dw_mode_2018) && file.exists(PATHS$dw_mode_2024)) {
  dw18 <- as.factor(rast(PATHS$dw_mode_2018))
  dw24 <- as.factor(rast(PATHS$dw_mode_2024))

  present_ids <- as.integer(union(
    na.omit(unique(values(dw18))),
    na.omit(unique(values(dw24)))
  ))
  present_labels <- DW_CLASSES[as.character(present_ids)]
  present_colors <- DW_COLORS[present_labels]

  make_dw_map <- function(r, year) {
    ggplot() +
      geom_spatraster(data = r) +
      scale_fill_manual(
        values   = present_colors,
        labels   = present_labels,
        na.value = "transparent",
        name     = "Land cover"
      ) +
      annotation_scale(
        location = "bl", width_hint = 0.20,
        text_col = "grey30", bar_cols = c("grey30", "white")
      ) +
      labs(title = paste("Dynamic World", year)) +
      theme_map(base_size = 11) +
      theme(legend.position = "none")
  }

  p_dw18 <- make_dw_map(dw18, YEAR_BASELINE)
  p_dw24 <- make_dw_map(dw24, YEAR_TARGET)

  # Shared legend
  p_legend_r <- dw24
  legend_data <- data.frame(
    fill  = factor(present_labels, levels = present_labels),
    x = 1, y = seq_along(present_labels)
  )
  p_legend <- ggplot(legend_data, aes(x, y, fill = fill)) +
    geom_tile() +
    scale_fill_manual(values = present_colors, name = "Land cover class") +
    theme_void() +
    theme(legend.position = "right",
          legend.title = element_text(face = "bold", size = 10))
  shared_legend <- cowplot::get_legend(p_legend)

  combined <- (p_dw18 | p_dw24) +
    plot_annotation(
      title    = "Dynamic World Land Cover Classification",
      subtitle = "Yellow River Delta, Shandong Province, China",
      caption  = caption_text,
      theme    = theme(
        plot.title    = element_text(face = "bold", hjust = 0.5),
        plot.subtitle = element_text(hjust = 0.5, colour = "grey40"),
        plot.caption  = element_text(hjust = 0, colour = "grey55", size = 9)
      )
    )

  ggsave(file.path(out_dir, "fig3_dynamic_world_comparison.png"),
         combined, width = 14, height = 6, dpi = 300)
  cat("  Saved fig3_dynamic_world_comparison.png\n")
}

# ========================================================================
# Figure 4: Three-panel summary (MAD | DW change | Clusters K=5)
# ========================================================================
cat("Figure 4: Three-panel summary...\n")

clust_path <- "results/embeddings_delta/clusters_2024_K5.tif"

if (file.exists(mad_path) && file.exists(clust_path)) {
  mad_r2   <- clip_pct(rast(mad_path))
  clust_r  <- as.factor(rast(clust_path))

  cluster_pal <- c("#E41A1C", "#377EB8", "#4DAF4A", "#984EA3", "#FF7F00")

  p1 <- ggplot() +
    geom_spatraster(data = mad_r2) +
    scale_fill_distiller(palette = "YlOrRd", direction = 1,
                         name = "MAD", na.value = "transparent") +
    annotation_scale(location = "bl", width_hint = 0.3,
                     text_col = "grey30", bar_cols = c("grey30", "white")) +
    labs(title = "MAD Change") +
    theme_map(base_size = 11)

  p2 <- ggplot() +
    geom_spatraster(data = clust_r) +
    scale_fill_manual(
      values   = cluster_pal,
      na.value = "transparent",
      name     = "Cluster",
      labels   = paste("C", 0:4)
    ) +
    labs(title = "K-means Clusters K=5 (2024)") +
    theme_map(base_size = 11)

  # Area change bar chart (from CSV)
  dw_area_path <- "results/DW_area_change_stats.csv"
  if (file.exists(dw_area_path)) {
    dw_stats <- read.csv(dw_area_path)
    # Normalise column names
    names(dw_stats) <- tolower(trimws(names(dw_stats)))

    # Try to detect columns
    class_col <- grep("class|label|name", names(dw_stats), value = TRUE)[1]
    area_col  <- grep("area|km2|ha|count", names(dw_stats), value = TRUE)[1]

    if (!is.na(class_col) && !is.na(area_col)) {
      dw_stats$class_label <- as.character(dw_stats[[class_col]])
      dw_stats$area_val    <- as.numeric(dw_stats[[area_col]])

      p3 <- ggplot(dw_stats, aes(x = reorder(class_label, area_val), y = area_val)) +
        geom_col(fill = "#2B83BA") +
        coord_flip() +
        scale_y_continuous(labels = label_comma()) +
        labs(
          title = "Area by DW Class (2024)",
          x = NULL, y = "Area (km\u00b2)"
        ) +
        theme_map(base_size = 11) +
        theme(panel.background = element_rect(fill = "white", colour = NA))
    } else {
      p3 <- ggplot() +
        annotate("text", x = 0.5, y = 0.5, label = "Area stats\nnot available",
                 size = 5, colour = "grey50") +
        theme_void()
    }
  } else {
    p3 <- ggplot() +
      annotate("text", x = 0.5, y = 0.5, label = "Area stats\nnot available",
               size = 5, colour = "grey50") +
      theme_void()
  }

  summary_fig <- (p1 | p2 | p3) +
    plot_annotation(
      title   = paste0("Yellow River Delta — Land Cover Analysis Summary (",
                       YEAR_BASELINE, "\u2013", YEAR_TARGET, ")"),
      caption = caption_text,
      theme   = theme(
        plot.title   = element_text(face = "bold", hjust = 0.5, size = 15),
        plot.caption = element_text(hjust = 0, colour = "grey55", size = 8)
      )
    )

  ggsave(file.path(out_dir, "fig4_summary_panel.png"),
         summary_fig, width = 18, height = 6, dpi = 300)
  cat("  Saved fig4_summary_panel.png\n")
}

# ========================================================================
# Figure 5: Bivariate overlay — MAD hotspots × Extreme precipitation
# (inspired by Milos Agathon's bivariate climate maps)
# ========================================================================
cat("Figure 5: Bivariate MAD × precipitation overlay...\n")

precip_path <- "figures/YRDelta_extremeFreq_p95_2018_2024.tif"

if (file.exists(mad_path) && file.exists(precip_path)) {
  mad_bv    <- clip_pct(rast(mad_path), lo = 0, hi = 0.95)
  precip_bv <- clip_pct(rast(precip_path), lo = 0, hi = 0.95)

  # Resample precip to match MAD grid
  if (!compareGeom(mad_bv, precip_bv, stopOnError = FALSE)) {
    precip_bv <- resample(precip_bv, mad_bv, method = "bilinear")
  }

  # Classify each layer into 3 quantile bins (→ 9 bivariate classes)
  bin3 <- function(r) {
    v <- values(r)
    v_fin <- v[is.finite(v)]
    breaks <- as.numeric(quantile(v_fin, c(0, 1/3, 2/3, 1), names = FALSE))
    classify(r, rcl = matrix(c(
      breaks[1], breaks[2], 1,
      breaks[2], breaks[3], 2,
      breaks[3], breaks[4], 3
    ), ncol = 3, byrow = TRUE))
  }

  mad_bin    <- bin3(mad_bv)
  precip_bin <- bin3(precip_bv)

  # Combine: bivariate class = (mad_bin - 1) * 3 + precip_bin → 1..9
  biv <- (mad_bin - 1) * 3 + precip_bin
  biv <- as.factor(biv)

  # 9-colour bivariate palette (red=high MAD, blue=high precip, purple=both)
  biv_colors <- c(
    "1" = "#e8e8e8",  # low MAD, low precip
    "2" = "#ace4e4",  # low MAD, mid precip
    "3" = "#5ac8c8",  # low MAD, high precip
    "4" = "#dfb0d6",  # mid MAD, low precip
    "5" = "#a5b3cc",  # mid MAD, mid precip
    "6" = "#5698b9",  # mid MAD, high precip
    "7" = "#be64ac",  # high MAD, low precip
    "8" = "#8c62aa",  # high MAD, mid precip
    "9" = "#3b4994"   # high MAD, high precip
  )

  present_biv <- as.character(na.omit(unique(values(biv))))

  p_biv <- ggplot() +
    geom_spatraster(data = biv) +
    scale_fill_manual(
      values   = biv_colors[present_biv],
      na.value = "transparent",
      name     = NULL,
      guide    = "none"
    ) +
    annotation_scale(
      location = "bl", width_hint = 0.25,
      text_col = "grey30", bar_cols = c("grey30", "white")
    ) +
    annotation_north_arrow(
      location = "tr",
      style    = north_arrow_fancy_orienteering(
        fill = c("grey30", "white"), text_col = "grey30"
      ),
      height = unit(1.2, "cm"), width = unit(1.2, "cm")
    ) +
    labs(
      title    = "Bivariate Map: Land Cover Change \u00d7 Extreme Precipitation",
      subtitle = paste0("Purple = high change AND high precipitation  |  ",
                        YEAR_BASELINE, "\u2013", YEAR_TARGET),
      caption  = caption_text
    ) +
    theme_map()

  # Bivariate legend (3×3 grid inset)
  legend_df <- expand.grid(mad_bin = 1:3, precip_bin = 1:3)
  legend_df$class <- (legend_df$mad_bin - 1) * 3 + legend_df$precip_bin
  legend_df$color <- biv_colors[as.character(legend_df$class)]

  p_legend_biv <- ggplot(legend_df,
                         aes(x = precip_bin, y = mad_bin, fill = color)) +
    geom_tile(colour = "white", linewidth = 0.5) +
    scale_fill_identity() +
    scale_x_continuous(breaks = c(1, 3),
                       labels = c("Low precip", "High precip")) +
    scale_y_continuous(breaks = c(1, 3),
                       labels = c("Low\nchange", "High\nchange")) +
    labs(x = "Extreme precipitation \u2192",
         y = "Land cover change \u2192") +
    theme_minimal(base_size = 9) +
    theme(
      axis.title = element_text(size = 8, colour = "grey30"),
      axis.text  = element_text(size = 7, colour = "grey40"),
      panel.grid = element_blank(),
      plot.background = element_rect(fill = "white", colour = "grey80")
    )

  # Combine map + legend inset
  final_biv <- p_biv +
    inset_element(p_legend_biv,
                  left = 0.02, bottom = 0.52,
                  right = 0.22, top = 0.88)

  ggsave(file.path(out_dir, "fig5_bivariate_change_precip.png"),
         final_biv, width = 10, height = 7, dpi = 300)
  cat("  Saved fig5_bivariate_change_precip.png\n")
} else {
  cat("  Skipping bivariate figure — rasters not found.\n")
}

cat("\n=== All publication figures saved to figures/publication/ ===\n")
