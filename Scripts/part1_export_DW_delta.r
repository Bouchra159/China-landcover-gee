# ========================================================================
# Part 1A: Yellow River Delta — Dynamic World (Strategy 1)
# Exports:
#   - DW_mode_2018 (dominant class)
#   - DW_mode_2024 (dominant class)
#   - DW_changed_2018_2024 (0/1 change mask)
#   - DW_transition_2018_2024 (from*10 + to ; compact transition code)
#
# Project: ee-yellow-river-481216
# Author: Bouchra Daddaoui
# ========================================================================

source("Scripts/config.R")   # sets PROJECT_ROOT, PYTHON_PATH, GEE_PROJECT

suppressPackageStartupMessages({
  library(reticulate)
})

ee <- import("ee")

# Authenticate (token can expire)
ee$Authenticate()

ee$Initialize(project = GEE_PROJECT)

# ---- AOI: Yellow River Delta (robust polygon box) ----
# This bbox covers the modern delta + estuary near Dongying (Shandong).
# You can tweak later, but start with this.
xmin <- 118.35
xmax <- 119.35
ymin <- 37.35
ymax <- 38.15

region <- ee$Geometry$Rectangle(
  coords = list(xmin, ymin, xmax, ymax),
  proj = "EPSG:4326",
  geodesic = FALSE
)

# ---- Dynamic World collection ----
dw <- ee$ImageCollection("GOOGLE/DYNAMICWORLD/V1")$
  filterBounds(region)$
  select("label") # integer class 0..8

# Helper: get annual mode (dominant label) from DW
dw_mode_year <- function(year) {
  start <- sprintf("%d-01-01", year)
  end   <- sprintf("%d-12-31", year)

  ic <- dw$filterDate(start, end)

  # mode reducer gives the most frequent class per pixel
  mode_img <- ic$reduce(ee$Reducer$mode())$rename("dw_mode")$toInt()

  mode_img$clip(region)
}

dw2018 <- dw_mode_year(2018L)
dw2024 <- dw_mode_year(2024L)

# ---- Change products ----
changed <- dw2018$neq(dw2024)$rename("changed")$toInt()$clip(region)

# Transition code: from*10 + to (e.g., 23 means class2->class3)
transition <- dw2018$multiply(10)$add(dw2024)$rename("transition")$toInt()$clip(region)

# ---- Export settings ----
drive_folder <- "YR_delta_exports"
scale_m <- 10  # Dynamic World native is 10m

export_to_drive <- function(img, desc, fname) {
  task <- ee$batch$Export$image$toDrive(
    image = img,
    description = desc,
    folder = drive_folder,
    fileNamePrefix = fname,
    region = region,
    scale = scale_m,
    maxPixels = 1e13,
    fileFormat = "GeoTIFF"
  )
  task$start()
  cat("Started task:", desc, "\n")
}

export_to_drive(dw2018,    "DW_mode_2018_delta",        "DW_mode_2018_delta")
export_to_drive(dw2024,    "DW_mode_2024_delta",        "DW_mode_2024_delta")
export_to_drive(changed,   "DW_changed_2018_2024_delta","DW_changed_2018_2024_delta")
export_to_drive(transition,"DW_transition_2018_2024_delta","DW_transition_2018_2024_delta")

cat("\n✅ Exports started.\n")
cat("Go to Earth Engine Code Editor -> Tasks tab -> Run each task.\n")
cat("They will appear in Google Drive folder:", drive_folder, "\n")
