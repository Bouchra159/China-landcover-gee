# ========================================================================
# config.R — Centralized configuration for the Yellow River Delta analysis
# Edit ONLY this file to adapt the project to a new machine or GEE project.
# Source this at the top of every script: source("Scripts/config.R")
# ========================================================================

# ---- Project root -------------------------------------------------------
# Set to the absolute path of the land_cover_gis folder on your machine.
PROJECT_ROOT <- "C:/Users/BOUCHRA/Documents/land_cover_gis"
setwd(PROJECT_ROOT)

# ---- Python / Earth Engine ----------------------------------------------
# Path to the Python executable that has earthengine-api installed.
# Find yours with: reticulate::py_discover_config()
PYTHON_PATH <- "C:/Users/BOUCHRA/Documents/.virtualenvs/r-reticulate/Scripts/python.exe"

# Your Google Earth Engine project ID (create one at code.earthengine.google.com)
GEE_PROJECT <- "ee-yellow-river-481216"

# ---- Region of Interest (WGS84 / EPSG:4326) ----------------------------
# Primary ROI — used for Dynamic World export (Part 1)
ROI_PRIMARY <- list(xmin = 118.35, xmax = 119.35, ymin = 37.35, ymax = 38.15)

# Secondary ROI — used for change detection on Henan tiles (Part 2)
ROI_SECONDARY <- list(xmin = 118.55, xmax = 119.45, ymin = 37.35, ymax = 38.10)

# Delta ROI — used for embedding-based analysis (Parts 3–4)
# (derived automatically from the downloaded embedding extent in Part 4)

# Small smoke-test ROI — used to verify GEE exports before full run
ROI_SMOKETEST <- list(xmin = 118.72, xmax = 118.88, ymin = 37.73, ymax = 37.87)

# ---- Analysis years -----------------------------------------------------
YEAR_BASELINE <- 2018
YEAR_TARGET   <- 2024

# ---- Analysis parameters ------------------------------------------------
# Minimum number of valid embedding dimensions required per pixel
# (1 = lenient, good for sparse data; 10–20 = stricter, cleaner results)
MIN_VALID_DIMS <- 10

# Number of pixels to sample for K-means and ML training
KMEANS_SAMPLES <- 20000
ML_SAMPLE_SIZE <- 15000

# K-means cluster counts to run
KMEANS_K <- c(3, 5, 10)

# Random Forest hyperparameters
RF_NUM_TREES   <- 300
RF_MIN_NODE    <- 5
RF_TRAIN_FRAC  <- 0.80       # fraction of samples used for training

# DW export scale (metres) — 10 = native Dynamic World resolution
DW_EXPORT_SCALE <- 10

# ---- terra memory/temp --------------------------------------------------
# Fraction of RAM terra is allowed to use (0.6 = 60%)
TERRA_MEMFRAC <- 0.6
TERRA_TEMPDIR <- file.path(PROJECT_ROOT, "tmp")

# ---- Key file paths (derived — do not edit) -----------------------------
PATHS <- list(
  # Raw data
  emb_2018     = "data/embeddings_delta/YR_delta_embeddings_2018.tif",
  emb_2024     = "data/embeddings_delta/YR_delta_embeddings_2024.tif",
  dw_label     = "data/embeddings_delta/DW_label_2024_delta.tif",
  dw_mode_2018 = "data/DW_delta/DW_mode_2018_delta.tif",
  dw_mode_2024 = "data/DW_delta/DW_mode_2024_delta.tif",
  dw_changed   = "data/DW_delta/DW_changed_2018_2024_delta.tif",

  # Results
  mad_roi      = "results/change_detection/mad_2018_2024_roi.tif",
  cos_roi      = "results/change_detection/cosine_change_2018_2024_roi.tif",

  # Figures output dirs
  fig_dir      = "figures",
  fig_delta    = "figures/embeddings_delta",
  fig_lp       = "figures/linear_probe"
)

# ---- Dynamic World class labels -----------------------------------------
DW_CLASSES <- c(
  "0" = "Water",
  "1" = "Trees",
  "2" = "Grass",
  "3" = "Flooded vegetation",
  "4" = "Crops",
  "5" = "Shrub & scrub",
  "6" = "Built area",
  "7" = "Bare ground",
  "8" = "Snow & ice"
)

DW_COLORS <- c(
  "Water"              = "#419BDF",
  "Trees"              = "#397D49",
  "Grass"              = "#88B053",
  "Flooded vegetation" = "#7A87C6",
  "Crops"              = "#E49635",
  "Shrub & scrub"      = "#DFC35A",
  "Built area"         = "#C4281B",
  "Bare ground"        = "#A59B8F",
  "Snow & ice"         = "#B39FE1"
)

# ---- Apply terra options ------------------------------------------------
suppressPackageStartupMessages(library(terra))
terraOptions(tempdir = TERRA_TEMPDIR, memfrac = TERRA_MEMFRAC, progress = 1)
dir.create(TERRA_TEMPDIR, showWarnings = FALSE, recursive = TRUE)

# ---- Set Python for reticulate (only if reticulate is loaded) -----------
if (requireNamespace("reticulate", quietly = TRUE)) {
  Sys.setenv(RETICULATE_PYTHON = PYTHON_PATH)
}

message("Config loaded. Project root: ", PROJECT_ROOT)
