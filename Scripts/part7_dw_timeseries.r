# ========================================================================
# part7_dw_timeseries.R
# Dynamic World land cover temporal trajectory: 2018–2024
#
# Stage A (GEE) — Export annual DW mode composites for 2019–2023
#   (2018 and 2024 are already in data/DW_delta/)
#
# Stage B (local) — Compute area per class per year from all rasters
#   and produce a publication-quality time-series figure
#
# Outputs:
#   data/DW_timeseries/DW_mode_{year}_delta.tif    (GEE export, Stage A)
#   results/timeseries/dw_area_timeseries.csv
#   figures/publication/fig_dw_timeseries.png
#   figures/publication/fig_dw_timeseries_focus.png  (water, crops, built)
# ========================================================================

source("Scripts/config.R")

ensure_pkgs <- function(pkgs) {
  miss <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(miss)) install.packages(miss, dependencies = TRUE)
}
ensure_pkgs(c("terra", "ggplot2", "dplyr", "tidyr", "scales",
              "ggspatial", "reticulate"))

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(scales)
})

dir.create("data/DW_timeseries",    showWarnings = FALSE, recursive = TRUE)
dir.create("results/timeseries",    showWarnings = FALSE, recursive = TRUE)
dir.create("figures/publication",   showWarnings = FALSE, recursive = TRUE)

# Pixel area conversion: each DW pixel is 10m × 10m = 100 m² = 1e-4 km²
PIXEL_TO_KM2 <- 1e-4

ALL_YEARS <- 2018:2024

# Set TRUE to skip GEE exports and run Stage B only (uses 2018 & 2024 already in data/)
SKIP_GEE_EXPORT <- TRUE

# ========================================================================
# STAGE A — Export missing years from GEE
# ========================================================================
# Check which years we already have
existing_years <- c()
for (yr in ALL_YEARS) {
  p <- sprintf("data/DW_timeseries/DW_mode_%d_delta.tif", yr)
  # Also check the main DW_delta folder (2018 and 2024 stored there)
  p_orig <- sprintf("data/DW_delta/DW_mode_%d_delta.tif", yr)
  if (file.exists(p) || file.exists(p_orig)) {
    existing_years <- c(existing_years, yr)
  }
}

missing_years <- if (SKIP_GEE_EXPORT) c() else setdiff(ALL_YEARS, existing_years)
cat("Years already available:", paste(existing_years, collapse = ", "), "\n")
if (SKIP_GEE_EXPORT) cat("Stage A skipped (SKIP_GEE_EXPORT = TRUE) — running Stage B only.\n") else
  cat("Years to export from GEE:", paste(missing_years, collapse = ", "), "\n")

if (length(missing_years) > 0) {

  gee_ok <- tryCatch({
    suppressPackageStartupMessages(library(reticulate))
    ee <- import("ee")
    ee$Authenticate()
    ee$Initialize(project = GEE_PROJECT)
    TRUE
  }, error = function(e) {
    message("GEE Stage A skipped (auth failed): ", conditionMessage(e))
    message("Continuing to Stage B with available years only.")
    FALSE
  })

  if (!gee_ok) {
    cat("Skipping GEE exports — running Stage B with existing data.\n")
  } else {

  roi <- ee$Geometry$Rectangle(
    coords   = list(ROI_PRIMARY$xmin, ROI_PRIMARY$ymin,
                    ROI_PRIMARY$xmax, ROI_PRIMARY$ymax),
    proj     = "EPSG:4326",
    geodesic = FALSE
  )

  options(timeout = max(600, getOption("timeout")))

  for (yr in missing_years) {

    cat(sprintf("\n[GEE] Exporting DW mode %d ...\n", yr))

    dw_ic <- ee$ImageCollection("GOOGLE/DYNAMICWORLD/V1")$
      filterDate(sprintf("%d-01-01", yr), sprintf("%d-12-31", yr))$
      filterBounds(roi)$
      select("label")

    n_imgs <- dw_ic$size()$getInfo()
    cat(sprintf("  Images in collection: %d\n", n_imgs))

    if (n_imgs == 0) {
      warning(sprintf("No DW images found for %d — skipping.", yr))
      next
    }

    dw_mode <- dw_ic$
      reduce(ee$Reducer$mode())$
      rename("dw_label")$
      clip(roi)$
      toInt()

    region_coords <- list(list(
      list(ROI_PRIMARY$xmin, ROI_PRIMARY$ymin),
      list(ROI_PRIMARY$xmax, ROI_PRIMARY$ymin),
      list(ROI_PRIMARY$xmax, ROI_PRIMARY$ymax),
      list(ROI_PRIMARY$xmin, ROI_PRIMARY$ymax),
      list(ROI_PRIMARY$xmin, ROI_PRIMARY$ymin)
    ))

    url <- dw_mode$getDownloadURL(list(
      name       = sprintf("DW_mode_%d_delta", yr),
      scale      = DW_EXPORT_SCALE,
      region     = region_coords,
      crs        = "EPSG:4326",
      fileFormat = "GeoTIFF"
    ))

    out_path <- sprintf("data/DW_timeseries/DW_mode_%d_delta.tif", yr)
    tmp_dl   <- file.path("tmp", sprintf("DW_mode_%d_delta.bin", yr))
    if (file.exists(tmp_dl)) file.remove(tmp_dl)

    ok <- FALSE
    for (attempt in 1:3) {
      cat(sprintf("  Download attempt %d/3 ...\n", attempt))
      res <- try(download.file(url, tmp_dl, mode = "wb", quiet = TRUE),
                 silent = TRUE)
      if (!inherits(res, "try-error") &&
          file.exists(tmp_dl) && file.info(tmp_dl)$size > 1000) {
        ok <- TRUE
        break
      }
      Sys.sleep(3 * attempt)
    }

    if (!ok) {
      warning(sprintf("[GEE] Download failed for %d after 3 attempts.", yr))
      next
    }

    # Handle zip vs raw GeoTIFF
    hdr <- readBin(tmp_dl, "raw", n = 4)
    if (length(hdr) == 4 &&
        as.integer(hdr[1]) == 0x50 && as.integer(hdr[2]) == 0x4B) {
      unzip(tmp_dl, exdir = "tmp")
      tifs <- list.files("tmp", pattern = "\\.tif$", full.names = TRUE,
                         ignore.case = TRUE)
      if (length(tifs) == 0) stop("ZIP extracted but no .tif found.")
      file.copy(tifs[1], out_path, overwrite = TRUE)
    } else {
      file.copy(tmp_dl, out_path, overwrite = TRUE)
    }

    # Verify
    ok_r <- tryCatch({ rast(out_path); TRUE }, error = function(e) FALSE)
    if (ok_r) cat(sprintf("  Saved: %s\n", out_path)) else
      warning(sprintf("  Saved file is not a valid GeoTIFF for %d", yr))
  }
  } # end gee_ok else block
}

# ========================================================================
# STAGE B — Compute area per class per year and visualise
# ========================================================================
cat("\n--- Stage B: computing area time series ---\n")

# Build a unified list of raster paths per year
get_dw_path <- function(yr) {
  candidates <- c(
    sprintf("data/DW_timeseries/DW_mode_%d_delta.tif", yr),
    sprintf("data/DW_delta/DW_mode_%d_delta.tif", yr)
  )
  found <- Filter(file.exists, candidates)
  if (length(found) == 0) return(NULL)
  found[1]
}

area_rows <- list()

for (yr in ALL_YEARS) {

  p <- get_dw_path(yr)
  if (is.null(p)) {
    cat(sprintf("  %d: no raster found, skipping.\n", yr))
    next
  }

  r <- tryCatch(rast(p), error = function(e) NULL)
  if (is.null(r)) {
    cat(sprintf("  %d: could not read raster, skipping.\n", yr))
    next
  }

  cat(sprintf("  %d: processing %s\n", yr, basename(p)))

  freq_df <- freq(r, digits = 0)
  freq_df  <- freq_df[!is.na(freq_df$value), ]

  if (nrow(freq_df) == 0) {
    cat(sprintf("  %d: no valid pixels.\n", yr))
    next
  }

  freq_df$year      <- yr
  freq_df$class_id  <- as.integer(freq_df$value)
  freq_df$class_name <- DW_CLASSES[as.character(freq_df$class_id)]
  freq_df$area_km2  <- freq_df$count * PIXEL_TO_KM2

  area_rows[[as.character(yr)]] <- freq_df[, c("year", "class_id", "class_name", "area_km2")]
}

if (length(area_rows) < 2) {
  cat("\nFewer than 2 years available — run Stage A first to export intermediate years.\n")
  cat("Plotting with available years only.\n")
}

area_ts <- bind_rows(area_rows)
area_ts  <- area_ts[!is.na(area_ts$class_name), ]

write.csv(area_ts, "results/timeseries/dw_area_timeseries.csv", row.names = FALSE)
cat("Saved: results/timeseries/dw_area_timeseries.csv\n")
cat("Years in dataset:", paste(sort(unique(area_ts$year)), collapse = ", "), "\n")

# ---- Figure 1: all classes, full time series ----------------------------
years_available <- sort(unique(area_ts$year))

p_full <- ggplot(area_ts,
                 aes(x = year, y = area_km2,
                     colour = class_name, group = class_name)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2.2) +
  scale_colour_manual(values = DW_COLORS, name = "Land cover class") +
  scale_x_continuous(breaks = years_available) +
  scale_y_continuous(labels = label_comma(suffix = " km²")) +
  labs(
    title    = "Dynamic World Land Cover Trajectories — Yellow River Delta",
    subtitle = sprintf("Annual mode composite · %d–%d · 10 m resolution",
                       min(years_available), max(years_available)),
    x        = NULL,
    y        = "Area (km²)",
    caption  = paste0(
      "Data: Google Dynamic World V1 via Google Earth Engine\n",
      "ROI: 118.35–119.35°E, 37.35–38.15°N (Shandong Province, China)"
    )
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.title    = element_text(face = "bold", hjust = 0.5),
    plot.subtitle = element_text(hjust = 0.5, colour = "grey40"),
    plot.caption  = element_text(colour = "grey55", size = 8, hjust = 0),
    legend.position = "right",
    panel.grid.minor = element_blank()
  )

ggsave("figures/publication/fig_dw_timeseries.png",
       p_full, width = 11, height = 6.5, dpi = 300)
cat("Saved: figures/publication/fig_dw_timeseries.png\n")

# ---- Figure 2: focus panel — the three dominant change classes ----------
focus_classes <- c("Water", "Crops", "Built area", "Flooded vegetation", "Bare ground")
area_focus <- area_ts %>%
  filter(class_name %in% focus_classes) %>%
  mutate(class_name = factor(class_name, levels = focus_classes))

if (nrow(area_focus) > 0) {

  p_focus <- ggplot(area_focus,
                    aes(x = year, y = area_km2,
                        colour = class_name, group = class_name)) +
    geom_ribbon(
      data = area_focus %>%
        group_by(class_name) %>%
        mutate(
          base_area = area_km2[year == min(year)],
          ymin = pmin(area_km2, base_area),
          ymax = pmax(area_km2, base_area)
        ) %>% ungroup(),
      aes(ymin = ymin, ymax = ymax, fill = class_name),
      alpha = 0.12, colour = NA
    ) +
    geom_line(linewidth = 1.1) +
    geom_point(size = 2.8) +
    facet_wrap(~class_name, scales = "free_y", ncol = 3) +
    scale_colour_manual(values = DW_COLORS[focus_classes], guide = "none") +
    scale_fill_manual(values   = DW_COLORS[focus_classes], guide = "none") +
    scale_x_continuous(breaks  = years_available) +
    scale_y_continuous(labels  = label_comma(suffix = " km²")) +
    labs(
      title    = "Key Land Cover Class Trajectories — Yellow River Delta",
      subtitle = sprintf(
        "Shading shows change from %d baseline · Annual DW mode composite",
        min(years_available)
      ),
      x        = NULL,
      y        = "Area (km²)",
      caption  = paste0(
        "Data: Google Dynamic World V1 via Google Earth Engine\n",
        "ROI: 118.35–119.35°E, 37.35–38.15°N (Shandong Province, China)"
      )
    ) +
    theme_minimal(base_size = 13) +
    theme(
      plot.title    = element_text(face = "bold", hjust = 0.5),
      plot.subtitle = element_text(hjust = 0.5, colour = "grey40"),
      plot.caption  = element_text(colour = "grey55", size = 8, hjust = 0),
      strip.text    = element_text(face = "bold"),
      panel.grid.minor = element_blank(),
      axis.text.x   = element_text(angle = 35, hjust = 1)
    )

  ggsave("figures/publication/fig_dw_timeseries_focus.png",
         p_focus, width = 12, height = 7, dpi = 300)
  cat("Saved: figures/publication/fig_dw_timeseries_focus.png\n")
}

# ---- Rate-of-change summary table ---------------------------------------
if (length(years_available) >= 2) {
  yr_min <- min(years_available)
  yr_max <- max(years_available)

  roc <- area_ts %>%
    filter(year %in% c(yr_min, yr_max)) %>%
    pivot_wider(names_from = year, values_from = area_km2,
                names_prefix = "yr_") %>%
    rename(area_start = starts_with("yr_") & ends_with(as.character(yr_min)),
           area_end   = starts_with("yr_") & ends_with(as.character(yr_max))) %>%
    mutate(
      change_km2      = area_end - area_start,
      change_pct      = 100 * (area_end - area_start) / area_start,
      rate_km2_yr     = change_km2 / (yr_max - yr_min)
    ) %>%
    arrange(desc(abs(change_km2)))

  write.csv(roc, "results/timeseries/dw_rate_of_change.csv", row.names = FALSE)
  cat("Saved: results/timeseries/dw_rate_of_change.csv\n")

  cat(sprintf("\n=== Rate of change summary (%d → %d) ===\n", yr_min, yr_max))
  print(roc[, c("class_name", "area_start", "area_end",
                "change_km2", "change_pct", "rate_km2_yr")],
        digits = 3)
}

cat("\n=== part7_dw_timeseries.R complete ===\n")
cat("Run Stage A to fill in intermediate years (2019–2023) from GEE.\n")
cat("Stage B produces figures from whatever years are available.\n")
