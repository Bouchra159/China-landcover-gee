# ========================================================================
# cluster_labeling.R
# Assign semantic land cover labels to K-means clusters by computing the
# majority Dynamic World class within each cluster.
#
# For each K (3, 5, 10):
#   1. Cross-tabulate cluster IDs against DW 2024 labels
#   2. Assign the dominant DW class as the cluster's semantic label
#   3. Save a labelled cluster raster and a composition summary CSV
#   4. Produce a publication-quality map with named legend entries
#
# Outputs:
#   results/cluster_labels/cluster_composition_K{k}.csv
#   figures/publication/fig_clusters_labeled_K{k}.png
# ========================================================================

source("Scripts/config.R")

ensure_pkgs <- function(pkgs) {
  miss <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(miss)) install.packages(miss, dependencies = TRUE)
}
ensure_pkgs(c("terra", "ggplot2", "tidyterra", "dplyr", "tidyr",
              "ggspatial", "scales", "RColorBrewer"))

suppressPackageStartupMessages({
  library(ggplot2)
  library(tidyterra)
  library(dplyr)
  library(tidyr)
  library(ggspatial)
  library(scales)
})

dir.create("results/cluster_labels",  showWarnings = FALSE, recursive = TRUE)
dir.create("figures/publication",     showWarnings = FALSE, recursive = TRUE)

# ---- Paths --------------------------------------------------------------
dw_path <- PATHS$dw_label  # DW_label_2024_delta.tif — already on embedding grid
# Fallback: use the raw DW mode if the label file is missing
if (!file.exists(dw_path)) dw_path <- PATHS$dw_mode_2024

cluster_paths <- list(
  K3  = "clusters_gee/K3/YR_clusters_2024_k3.tif",
  K5  = "results/embeddings_delta/clusters_2024_K5.tif",
  K10 = "results/embeddings_delta/clusters_2024_K10.tif"
)
# Normalise: keep only clusters that exist
cluster_paths <- Filter(file.exists, cluster_paths)

if (!file.exists(dw_path))      stop("DW label raster not found: ", dw_path)
if (length(cluster_paths) == 0) stop("No cluster rasters found.")

dw <- rast(dw_path)
cat("DW raster loaded:", nlyr(dw), "layer(s)\n")

# ---- Helper: semantic colour for each DW class --------------------------
dw_color <- function(class_name) {
  DW_COLORS[class_name]
}

# ---- Process each K value -----------------------------------------------
all_compositions <- list()

for (k_name in names(cluster_paths)) {

  cat("\n====", k_name, "====\n")
  k_val <- as.integer(sub("K", "", k_name))

  cl <- rast(cluster_paths[[k_name]])
  cat("Cluster raster loaded:", nrow(cl), "x", ncol(cl), "\n")

  # Align DW to cluster grid (nearest neighbour — categorical)
  dw_aligned <- dw
  if (!compareGeom(cl, dw_aligned, stopOnError = FALSE)) {
    cat("  Resampling DW to cluster grid...\n")
    dw_aligned <- resample(dw_aligned, cl, method = "near")
  }

  # Stack cluster IDs and DW labels; extract non-NA pixels
  stack2 <- c(cl, dw_aligned)
  names(stack2) <- c("cluster_id", "dw_class")

  df <- as.data.frame(stack2, na.rm = TRUE)
  df$cluster_id <- as.integer(df$cluster_id)
  df$dw_class   <- as.integer(df$dw_class)
  df$dw_name    <- DW_CLASSES[as.character(df$dw_class)]

  # Cross-tabulation: pixel count per (cluster × DW class)
  composition <- df %>%
    count(cluster_id, dw_name, name = "n_pixels") %>%
    group_by(cluster_id) %>%
    mutate(
      total_pixels   = sum(n_pixels),
      pct            = 100 * n_pixels / total_pixels
    ) %>%
    ungroup() %>%
    arrange(cluster_id, desc(pct))

  # Majority label per cluster
  majority <- composition %>%
    group_by(cluster_id) %>%
    slice_max(n_pixels, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    transmute(
      cluster_id,
      majority_class = dw_name,
      majority_pct   = round(pct, 1)
    )

  # Create a unique label: "C0 — Crops (87%)"
  majority$label <- sprintf("C%d — %s (%.0f%%)",
                             majority$cluster_id,
                             majority$majority_class,
                             majority$majority_pct)

  cat("  Cluster labels:\n")
  print(majority[, c("cluster_id", "label")])

  # Merge composition with majority label
  composition <- composition %>%
    left_join(majority[, c("cluster_id", "majority_class", "majority_pct", "label")],
              by = "cluster_id")

  # Save CSV
  out_csv <- sprintf("results/cluster_labels/cluster_composition_%s.csv", k_name)
  write.csv(composition, out_csv, row.names = FALSE)
  cat("  Saved:", out_csv, "\n")

  all_compositions[[k_name]] <- composition

  # ---- Labelled composition bar chart -----------------------------------
  top_classes <- composition %>%
    group_by(cluster_id) %>%
    slice_max(pct, n = 4, with_ties = FALSE) %>%   # top-4 DW classes per cluster
    ungroup() %>%
    mutate(
      cluster_label = factor(
        sprintf("C%d", cluster_id),
        levels = sprintf("C%d", sort(unique(cluster_id)))
      ),
      dw_color = unname(DW_COLORS[dw_name])
    )

  # Use DW colours for fill where available
  color_map <- setNames(DW_COLORS[unique(top_classes$dw_name)],
                        unique(top_classes$dw_name))

  p_bar <- ggplot(top_classes,
                  aes(x = cluster_label, y = pct, fill = dw_name)) +
    geom_col(position = "stack", colour = "white", linewidth = 0.3) +
    scale_fill_manual(values = color_map, name = "DW Class") +
    scale_y_continuous(labels = label_number(suffix = "%")) +
    labs(
      title    = sprintf("K-means Cluster Composition (%s) — Majority Dynamic World Class", k_name),
      subtitle = "Proportion of pixels per DW class within each cluster · Yellow River Delta 2024",
      x        = "Cluster",
      y        = "% of pixels"
    ) +
    theme_minimal(base_size = 13) +
    theme(
      plot.title    = element_text(face = "bold", hjust = 0.5),
      plot.subtitle = element_text(hjust = 0.5, colour = "grey40"),
      legend.position = "right"
    )

  ggsave(sprintf("figures/publication/fig_cluster_composition_%s.png", k_name),
         p_bar, width = 10, height = 5.5, dpi = 300)
  cat("  Saved: figures/publication/fig_cluster_composition_", k_name, ".png\n", sep = "")

  # ---- Labelled spatial map ----------------------------------------------
  # Recode cluster raster so each cluster has a factor level with the full label
  rcl_mat <- cbind(from  = majority$cluster_id,
                   to    = seq_along(majority$cluster_id))
  cl_recoded <- classify(cl, rcl_mat, others = NA)
  cl_factor  <- as.factor(cl_recoded)

  levels_df <- data.frame(
    value = seq_along(majority$label),
    label = majority$label
  )
  levels(cl_factor) <- levels_df

  # Colour per majority DW class
  map_colors <- unname(DW_COLORS[majority$majority_class])

  p_map <- ggplot() +
    geom_spatraster(data = cl_factor) +
    scale_fill_manual(
      values   = map_colors,
      na.value = "transparent",
      name     = "Cluster"
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
      title    = sprintf("Semantically Labelled Clusters (%s) — Yellow River Delta 2024", k_name),
      subtitle = "Labels assigned by majority Dynamic World class within each cluster",
      caption  = paste0(
        "Data: Google Satellite Embeddings V1 (64-band, 10m) + Google Dynamic World V1\n",
        "Study area: 118.35–119.35°E, 37.35–38.15°N"
      )
    ) +
    theme_minimal(base_size = 13) +
    theme(
      plot.title    = element_text(face = "bold", hjust = 0.5),
      plot.subtitle = element_text(hjust = 0.5, colour = "grey40"),
      plot.caption  = element_text(colour = "grey55", size = 8),
      panel.background = element_rect(fill = "#f0f4f8", colour = NA)
    )

  ggsave(sprintf("figures/publication/fig_clusters_labeled_%s.png", k_name),
         p_map, width = 9, height = 6.5, dpi = 300)
  cat("  Saved: figures/publication/fig_clusters_labeled_", k_name, ".png\n", sep = "")
}

# ---- Summary table: all K values ----------------------------------------
summary_all <- bind_rows(lapply(names(all_compositions), function(k_name) {
  all_compositions[[k_name]] %>%
    group_by(cluster_id) %>%
    slice_max(n_pixels, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    transmute(K = k_name, cluster_id, majority_class, majority_pct, total_pixels)
}))

write.csv(summary_all, "results/cluster_labels/cluster_majority_summary.csv",
          row.names = FALSE)
cat("\nSummary saved: results/cluster_labels/cluster_majority_summary.csv\n")

cat("\n=== cluster_labeling.R complete ===\n")
