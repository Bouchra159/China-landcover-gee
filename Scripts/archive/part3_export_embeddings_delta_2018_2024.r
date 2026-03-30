# ========================================================================
# Export Satellite Embeddings to Google Drive (Delta ROI)
# Dataset: GOOGLE/SATELLITE_EMBEDDING/V1/ANNUAL
# Years: 2018 and 2024
# Uses Earth Engine Python API via reticulate (no rgee asset-home issues)
# ========================================================================

library(reticulate)
use_condaenv("rgee", required = TRUE)

ee <- import("ee")
ee$Initialize(project = "ee-yellow-river-481216")

# ---- ROI (Yellow River Delta, small box) ----
roi_bbox <- list(
  xmin = 118.72, xmax = 118.88,
  ymin =  37.73, ymax =  37.87
)

roi <- ee$Geometry$Rectangle(
  coords = list(roi_bbox$xmin, roi_bbox$ymin, roi_bbox$xmax, roi_bbox$ymax),
  proj = "EPSG:4326",
  geodesic = FALSE
)

# ---- Build embeddings for a specific year ----
get_embeddings_image <- function(year, roi) {
  start <- sprintf("%d-01-01", year)
  end   <- sprintf("%d-01-01", year + 1)

  img <- ee$ImageCollection("GOOGLE/SATELLITE_EMBEDDING/V1/ANNUAL")$
    filterDate(start, end)$
    filterBounds(roi)$
    mosaic()$
    clip(roi)$
    toFloat()

  img
}

# ---- Coverage check using A00 mask ----
coverage_fraction <- function(img, roi, scale = 10) {
  mask_mean <- img$select("A00")$mask()$reduceRegion(
    reducer   = ee$Reducer$mean(),
    geometry  = roi,
    scale     = scale,
    maxPixels = 1e13,
    bestEffort = TRUE
  )
  mask_mean$get("A00")
}

# ---- Export helper ----
export_to_drive <- function(img, description,
                            folder = "land_cover_gis_exports",
                            scale = 10,
                            crs = "EPSG:3857",
                            fileDimensions = list(2048, 2048)) {

  task <- ee$batch$Export$image$toDrive(
    image = img,
    description = description,
    folder = folder,
    fileNamePrefix = description,
    region = roi,
    scale = scale,
    crs = crs,
    fileFormat = "GeoTIFF",
    maxPixels = 1e13,
    fileDimensions = fileDimensions
  )
  task$start()
  cat("✅ Started Drive export task:", description, "\n")
  invisible(task)
}

# ========================================================================
# RUN: 2024 then 2018
# ========================================================================

# ---- 2024 ----
emb24 <- get_embeddings_image(2024, roi)
cat("Checking coverage 2024...\n")
cov24 <- coverage_fraction(emb24, roi, scale = 10)
print(cov24)
export_to_drive(emb24, "YR_delta_embeddings_2024")

# ---- 2018 ----
emb18 <- get_embeddings_image(2018, roi)
cat("Checking coverage 2018...\n")
cov18 <- coverage_fraction(emb18, roi, scale = 10)
print(cov18)
export_to_drive(emb18, "YR_delta_embeddings_2018")

cat("\nNext:\n",
    "1) Open Google Drive -> folder 'land_cover_gis_exports'\n",
    "2) Download YR_delta_embeddings_2024.tif and YR_delta_embeddings_2018.tif\n",
    "3) Save them to data/embeddings_delta/2024/ and data/embeddings_delta/2018/\n", sep = "")
