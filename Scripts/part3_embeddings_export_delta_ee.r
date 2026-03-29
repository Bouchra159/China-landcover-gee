# ========================================================================
# Export embeddings to Google Drive using Earth Engine Python API (via reticulate)
# Year: 2024 first (required)
# ROI: Yellow River Delta small box
# ========================================================================

library(reticulate)
use_condaenv("rgee", required = TRUE)
ee <- import("ee")

# Initialize EE with your Cloud Project
ee$Initialize(project = "ee-yellow-river-481216")

# ---- ROI (Delta) ----
roi_bbox <- list(xmin = 118.72, xmax = 118.88,
                 ymin =  37.73, ymax =  37.87)

roi <- ee$Geometry$Rectangle(
  coords = list(roi_bbox$xmin, roi_bbox$ymin, roi_bbox$xmax, roi_bbox$ymax),
  proj = "EPSG:4326",
  geodesic = FALSE
)

# ========================================================================
# IMPORTANT: plug your embeddings image builder here
# You MUST reuse the same embedding source/model you used for Henan tiles.
# ========================================================================

get_embeddings_image <- function(year, roi) {
  # Google Satellite Embeddings V1 — 64-band 10m foundation model embeddings
  # GEE catalog: https://developers.google.com/earth-engine/datasets/catalog/GOOGLE_SATELLITE_EMBEDDING_V1
  # Collection ID: GOOGLE/SATELLITE_EMBEDDING/V1
  # Each image already has exactly 64 float bands — no .select() needed.
  # Filter to Q3 (Jun–Sep): peak growing/flooding season for Yellow River Delta.
  col <- ee$ImageCollection("GOOGLE/SATELLITE_EMBEDDING/V1")$
    filterBounds(roi)$
    filterDate(paste0(year, "-06-01"), paste0(year, "-09-30"))
  ee$Image(col$mosaic())
}

# ---- Coverage check (band-1 mask mean) ----
coverage_fraction <- function(img, roi, scale = 10) {
  mask_mean <- img$select(0)$mask()$reduceRegion(
    reducer = ee$Reducer$mean(),
    geometry = roi,
    scale = scale,
    maxPixels = 1e13,
    bestEffort = TRUE
  )
  # get first value in dict
  k <- mask_mean$keys()$get(0)
  mask_mean$get(k)
}

# ---- Export helper ----
export_to_drive <- function(img, year, roi,
                            folder = "land_cover_gis_exports",
                            prefix = "YR_delta_embeddings",
                            scale = 10,
                            crs = "EPSG:4326",
                            fileDimensions = list(2048, 2048)) {

  desc <- paste0(prefix, "_", year)
  task <- ee$batch$Export$image$toDrive(
    image = img,
    description = desc,
    folder = folder,
    fileNamePrefix = desc,
    region = roi,
    scale = scale,
    crs = crs,
    maxPixels = 1e13,
    fileFormat = "GeoTIFF",
    fileDimensions = fileDimensions
  )
  task$start()
  cat("Started task:", desc, "\n")
  invisible(task)
}

# ---- RUN 2024 ----
emb24 <- get_embeddings_image(2024, roi)

cat("Checking 2024 coverage...\n")
cov24 <- coverage_fraction(emb24, roi, scale = 10)
print(cov24)
cat("Rule: coverage >= 0.30 is OK, >= 0.50 is great\n")

# If coverage looks good, export
task24 <- export_to_drive(emb24, 2024, roi)
