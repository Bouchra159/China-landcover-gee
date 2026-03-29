# ========================================================================
# Part 2 (FINAL ROBUST): Download Dynamic World exports + maps + statistics
# Yellow River Delta (2018–2024)
# Author: Bouchra Daddaoui
# ========================================================================

# NOTE: Run this script from the project root directory (land_cover_gis/).
# e.g.  setwd("path/to/land_cover_gis"); source("Scripts/part2_download_and_maps.r")

dir.create("data/DW_delta", showWarnings = FALSE, recursive = TRUE)
dir.create("figures", showWarnings = FALSE, recursive = TRUE)
dir.create("results", showWarnings = FALSE, recursive = TRUE)

# --- SAFETY: if dplyr/tibble are attached, detach them for this script ---
# (prevents the "tibble NA column index" error)
if ("package:dplyr" %in% search())  detach("package:dplyr", unload = TRUE, character.only = TRUE)
if ("package:tibble" %in% search()) detach("package:tibble", unload = TRUE, character.only = TRUE)

suppressPackageStartupMessages({
  library(googledrive)
  library(terra)
  library(ggplot2)
  library(tidyterra)
})

# ---- A) Authenticate Drive ----
drive_auth()

# ---- B) Download files from Drive folder ----
folder_name <- "YR_delta_exports"
files <- drive_ls(folder_name)

targets <- c(
  "DW_mode_2018_delta.tif",
  "DW_mode_2024_delta.tif",
  "DW_changed_2018_2024_delta.tif",
  "DW_transition_2018_2024_delta.tif"
)

for (f in targets) {
  hit <- files[files$name == f, ]
  if (nrow(hit) == 0) stop("Missing in Drive folder: ", f)

  drive_download(hit, path = file.path("data/DW_delta", f), overwrite = TRUE)
  cat("Downloaded:", f, "\n")
}

# ---- C) Load rasters ----
dw18 <- rast("data/DW_delta/DW_mode_2018_delta.tif")
dw24 <- rast("data/DW_delta/DW_mode_2024_delta.tif")
dw_changed <- rast("data/DW_delta/DW_changed_2018_2024_delta.tif")
dw_trans <- rast("data/DW_delta/DW_transition_2018_2024_delta.tif")

# Align grids if needed (safe)
if (!compareGeom(dw18, dw24, stopOnError = FALSE))       dw24       <- resample(dw24, dw18, method = "near")
if (!compareGeom(dw18, dw_changed, stopOnError = FALSE)) dw_changed <- resample(dw_changed, dw18, method = "near")
if (!compareGeom(dw18, dw_trans, stopOnError = FALSE))   dw_trans   <- resample(dw_trans, dw18, method = "near")

# ---- D) Dynamic World class names (0..8) ----
dw_levels <- 0:8
dw_labels <- c(
  "Water", "Trees", "Grass", "Flooded vegetation",
  "Crops", "Shrub & scrub", "Built area",
  "Bare ground", "Snow & ice"
)

labels_tbl <- data.frame(value = dw_levels, class = dw_labels)

# ---- E) Maps: mode (2018, 2024) ----
dw18_cat <- as.factor(dw18)
dw24_cat <- as.factor(dw24)

# set categorical labels
levels(dw18_cat) <- labels_tbl
levels(dw24_cat) <- labels_tbl

plot_mode <- function(r_cat, title) {
  ggplot() +
    tidyterra::geom_spatraster(data = r_cat) +
    scale_fill_viridis_d(name = "Class", drop = FALSE) +
    labs(title = title) +
    theme_minimal() +
    theme(
      plot.title = element_text(hjust = 0.5),
      legend.title = element_text(size = 10),
      legend.text = element_text(size = 9)
    )
}

p18 <- plot_mode(dw18_cat, "Dominant Land Cover (2018) — Yellow River Delta")
p24 <- plot_mode(dw24_cat, "Dominant Land Cover (2024) — Yellow River Delta")

ggsave("figures/DW_mode_2018.png", p18, width = 7, height = 6, dpi = 220)
ggsave("figures/DW_mode_2024.png", p24, width = 7, height = 6, dpi = 220)

# ---- F) Map: changed mask (0/1) ----
dw_changed_cat <- as.factor(dw_changed)
levels(dw_changed_cat) <- data.frame(value = c(0, 1), class = c("Stable", "Changed"))

p_change <- ggplot() +
  tidyterra::geom_spatraster(data = dw_changed_cat) +
  scale_fill_manual(
    values = c("Stable" = "grey85", "Changed" = "red3"),
    name = "Change",
    drop = FALSE
  ) +
  labs(title = "Land Cover Change Mask (2018–2024) — Yellow River Delta") +
  theme_minimal() +
  theme(plot.title = element_text(hjust = 0.5))

ggsave("figures/DW_changed_mask.png", p_change, width = 7, height = 6, dpi = 220)

# ---- G) Area stats (km²): force fixed 0..8 output, aggregate duplicates ----
px_km2 <- cellSize(dw18, unit = "km")

area_by_class_fixed <- function(mode_raster, px_area, labels_tbl) {
  mode_int <- as.int(mode_raster)

  # freq table (value, count) — may include duplicates depending on terra version
  f <- as.data.frame(freq(mode_int, digits = 0))
  f <- f[, 1:2]
  colnames(f) <- c("value", "count")
  f <- f[!is.na(f$value), ]
  f$value <- as.integer(f$value)
  # aggregate duplicates
  f <- aggregate(count ~ value, data = f, sum)

  # zonal area sum (value, area_km2) — may include duplicates
  z <- as.data.frame(zonal(px_area, mode_int, fun = "sum", na.rm = TRUE))
  z <- z[, 1:2]
  colnames(z) <- c("value", "area_km2")
  z <- z[!is.na(z$value), ]
  z$value <- as.integer(z$value)
  # aggregate duplicates
  z <- aggregate(area_km2 ~ value, data = z, sum)

  # map into fixed 0..8 table
  out <- labels_tbl
  out$count <- 0
  out$area_km2 <- 0

  m1 <- match(f$value, out$value)
  out$count[m1[!is.na(m1)]] <- f$count[!is.na(m1)]

  m2 <- match(z$value, out$value)
  out$area_km2[m2[!is.na(m2)]] <- z$area_km2[!is.na(m2)]

  out
}

a18 <- area_by_class_fixed(dw18, px_km2, labels_tbl)
a24 <- area_by_class_fixed(dw24, px_km2, labels_tbl)

stats <- data.frame(
  class = labels_tbl$class,
  area_2018_km2 = a18$area_km2,
  area_2024_km2 = a24$area_km2
)
stats$change_km2 <- stats$area_2024_km2 - stats$area_2018_km2
stats <- stats[order(-abs(stats$change_km2)), ]

write.csv(stats, "results/DW_area_change_stats.csv", row.names = FALSE)

# ---- H) Bar plot of area change ----
p_bar <- ggplot(stats, aes(x = reorder(class, change_km2), y = change_km2)) +
  geom_col() +
  coord_flip() +
  labs(
    title = "Land Cover Area Change (2018–2024) — Yellow River Delta",
    x = "",
    y = "Area change (km²)"
  ) +
  theme_minimal() +
  theme(plot.title = element_text(hjust = 0.5))

ggsave("figures/DW_area_change_bar.png", p_bar, width = 8, height = 5.5, dpi = 220)

cat("\n✅ Part 2 finished: check figures/ and results/\n")
