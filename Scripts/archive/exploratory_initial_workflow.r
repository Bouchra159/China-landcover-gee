# Google Satellite Embeddings Visualization 
# Clustering and change detection analysis
# ========================================================================
# Author: Bouchra Daddaoui
# ========================================================================
install.packages(c(
  "googledrive",
  "terra",
  "tidyterra",
  "ggplot2",
  "grafify",
  "patchwork",
  "dplyr"
))


# ---------------- SECTION 1: Packages & Python setup --------------------

# Use Python 3.13 with reticulate
Sys.setenv(RETICULATE_PYTHON = "C:/Python313/python.exe")

# Package loading helper (optional but handy)
if (!requireNamespace("pacman", quietly = TRUE)) {
  install.packages("pacman")
}

pacman::p_load(
  reticulate,      # R–Python bridge
  devtools,        # for source_url()
  grafify,         # palettes
  leaflet          # interactive maps (needed by ee_leaflet_map)
  # you can add: tidyverse, terra, tidyterra, googledrive, patchwork if you use them
)

# Check that Python is correctly set
py_config()   # should show C:/Python313/python.exe


# ---------------- SECTION 2: Earth Engine init --------------------------

ee <- reticulate::import("ee")

# You only need this the first time or when token expires.
# After it works once, you can comment it out to avoid browser popping up.
ee$Authenticate()

# IMPORTANT: correct project ID (with 't' at the end)
ee$Initialize(project = "ee-land-cover-gis-project")

# Connectivity test - should return 3
connectivity_test <- ee$Number(1)$add(2)$getInfo()
print(connectivity_test)


# ---------------- SECTION 3: Area of Interest (AOI) ---------------------

# Coordinates format: longitude, latitude (WGS84)
# Box: 106.000000,31.000000,115.000000,40.000000  (Henan + Shanxi big box)

xmin <- 106.000000
ymin <- 31.000000
xmax <- 115.000000
ymax <- 40.000000

# Create Earth Engine geometry object for the region
region <- ee$Geometry$Polygon(list(list(
  c(xmin, ymin), c(xmin, ymax),
  c(xmax, ymax), c(xmax, ymin)
)))


# ---------------- SECTION 4: Embeddings Image ---------------------------

embeddings_image <- ee$ImageCollection(
  "GOOGLE/SATELLITE_EMBEDDING/V1/ANNUAL"
)$filterDate("2023-10-01", "2025-10-01")$
  filterBounds(region)$mosaic()$clip(region)$toFloat()


# ---------------- SECTION 5: Sampling for K-means -----------------------

n_samples <- 2000L

training <- embeddings_image$sample(
  region = region,
  scale = 10,
  numPixels = n_samples,
  seed = 100L,
  geometries = FALSE
)


# ---------------- SECTION 6: K-means Clustering function ----------------

get_clusters <- function(nClusters) {
  clusterer <- ee$Clusterer$wekaKMeans(
    nClusters = as.integer(nClusters)
  )$train(training)

  clustered <- embeddings_image$cluster(clusterer)
  return(clustered)
}

# Example clustering result for K = 5
clustered_k5 <- get_clusters(5)


# ---------------- SECTION 7: Leaflet helper function --------------------

# Pull your custom map helper from GitHub
devtools::source_url(
  "https://raw.githubusercontent.com/Bouchra159/China-landcover-gee/main/Map_viewer_gee.r"
)
# This must define `ee_leaflet_map()`


# ---------------- SECTION 8: Interactive Map Display --------------------

# Define visualization parameters for K=5 clustering
kelly <- grafify::graf_palettes[["kelly"]]

vis_k5 <- list(
  min = 0,
  max = 4,
  palette = kelly[1:5],
  center = c(xmin, ymin)  # center is actually passed again below
)

# Create and display interactive map
map_k5 <- ee_leaflet_map(
  clustered_k5$toInt(),
  vis_params  = vis_k5,
  center      = c((xmin + xmax) / 2, (ymin + ymax) / 2),
  zoom        = 13,
  satellite_base = TRUE,
  layer_name  = "K=5 clusters"
)

map_k5
# ---- SECTION 9: Batch Export and Download Functions ----
# Authenticate with Google Drive (same account as Earth Engine)
googledrive::drive_auth()

# Create export folder on Drive if it doesn't already exist
export_folder_name <- "earthengine-exports"

existing_folder <- tryCatch(
  googledrive::drive_get(export_folder_name),
  error = function(e) NULL
)

if (is.null(existing_folder) || nrow(existing_folder) == 0) {
  googledrive::drive_mkdir(export_folder_name)
  existing_folder <- googledrive::drive_get(export_folder_name)
}

export_folder <- existing_folder

# (Optional) list what is currently in the folder
drive_files <- googledrive::drive_ls(export_folder)
print(drive_files)

# Function to export clustering results to Google Drive
export_raster <- function(k) {
  clustered <- get_clusters(k)
  clustered_int <- clustered$toInt()$clip(region)

  description <- sprintf("clusters_k%d_export", k)
  filename_prefix <- sprintf("clusters_k%d", k)

  task <- ee$batch$Export$image$toDrive(
    image = clustered_int,
    description = description,
    folder = export_folder_name,
    fileNamePrefix = filename_prefix,
    scale = 10,
    region = region,
    fileFormat = "GeoTIFF",
    maxPixels = 1e13
  )

  task$start()
}

# ---- SECTION 10: Batch Processing Multiple K Values ----
# Define range of K values to analyze
cluster_values <- c(3L, 5L, 10L)

# Start export tasks for all clustering results
lapply(cluster_values, export_raster)

cat("Export tasks started. Check the 'Tasks' tab in the Earth Engine Code Editor.\n")
cat("   When all tasks are DONE, run the download section below.\n")

# ---- SECTION 11: Download and Visualization ----

# Helper to refresh the file list from Drive
refresh_drive_files <- function() {
  googledrive::drive_ls(export_folder)
}

# Function to download exported files from Google Drive
download_raster <- function(k, fs) {
  filename_prefix <- sprintf("clusters_k%d", k)
  pattern <- paste0("^", filename_prefix)

  matching_files <- fs |>
    dplyr::filter(grepl(pattern, name))

  if (nrow(matching_files) == 0) {
    stop("Could not find exported file for K = ", k, " in Drive folder.")
  }

  # Prefer .tif over .zip if both exist
  chosen_file <- matching_files |>
    dplyr::arrange(dplyr::desc(grepl("\\.tif$", name))) |>
    dplyr::slice(1)

  local_filename <- chosen_file$name

  googledrive::drive_download(
    chosen_file,
    path = local_filename,
    overwrite = TRUE
  )

  cat("Downloaded:", local_filename, "\n")
}

# ---- RUN THIS *AFTER* EE EXPORT TASKS ARE COMPLETE ----
# Refresh file list and download all clustering results
drive_files <- refresh_drive_files()

lapply(
  cluster_values,
  function(k) download_raster(k, drive_files)
)
# ---- SECTION 12: Multi-panel Visualization Creation ----
# 0. Go to your project folder
setwd("C:/Users/BOUCHRA/Documents/land_cover_gis")

# 1. Load packages (safe even if already loaded)
library(terra)
library(tidyterra)
library(ggplot2)
library(grafify)
library(patchwork)

# 2. List all local raster tiles exported from EE
cluster_files <- list.files(
  pattern   = "^clusters_k[0-9]+-.*\\.tif$",  # matches k3/k5/k10 tiles
  full.names = TRUE
)

# Quick sanity check
length(cluster_files)
head(cluster_files)

if (length(cluster_files) == 0) {
  stop("No 'clusters_k*.tif' files found in the working directory. ",
       "Make sure the GeoTIFFs are downloaded into this folder.")
}

# 3. Helper: extract K value (3, 5, 10, ...) from filenames
get_k_from_name <- function(fn) {
  as.integer(sub(".*clusters_k([0-9]+).*", "\\1", basename(fn)))
}

k_vals <- sapply(cluster_files, get_k_from_name)

# 4. Group file paths by K value → list '$3', '$5', '$10'
tiles_by_k <- split(cluster_files, k_vals)

# 5. Mosaic tiles for each K value
rasters_by_k <- lapply(tiles_by_k, function(file_vec) {
  r_list <- lapply(file_vec, terra::rast)   # load each tile
  do.call(terra::mosaic, r_list)           # mosaic into single raster
})

# 6. Order by numeric K so we get K3, K5, K10 in order
k_order      <- sort(as.integer(names(rasters_by_k)))
rasters_by_k <- rasters_by_k[as.character(k_order)]
names(rasters_by_k) <- paste0("K", k_order)  # "K3", "K5", "K10"

# 7. Function to create a cluster map for one K
make_cluster_plot <- function(r, title) {
  ggplot() +
    tidyterra::geom_spatraster(data = as.factor(r)) +  # discrete classes
    grafify::scale_fill_grafify(
      palette = "kelly",
      drop    = FALSE,
      guide   = "none"

    ) +
    labs(title = title) +
    theme_minimal() +
    theme(
      plot.title = element_text(hjust = 0.5)
    )
}

# 8. Build one plot per K (K3, K5, K10)
individual_plots <- mapply(
  FUN      = make_cluster_plot,
  r        = rasters_by_k,
  title    = paste0("K = ", k_order),
  SIMPLIFY = FALSE
)

# 9. Combine into a single 3-panel figure
combined_plot <- (
  individual_plots[[1]] +
  individual_plots[[2]] +
  individual_plots[[3]] +
  patchwork::plot_layout(nrow = 1, guides = "collect")
)

combined_plot  # <- this should display the final panel in the Plots pane

 