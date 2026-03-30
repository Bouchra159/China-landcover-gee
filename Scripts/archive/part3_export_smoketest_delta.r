# ========================================================================
# Drive export SMOKE TEST (Delta ROI) via Earth Engine Python API
# Goal: confirm EE + project + Drive export works from R on your machine.
# Exports: a small SRTM elevation image (not embeddings) for the Delta ROI.
# ========================================================================

library(reticulate)
use_condaenv("rgee", required = TRUE)

ee <- import("ee")
ee$Initialize(project = "ee-yellow-river-481216")

# ---- ROI (Delta) ----
roi_bbox <- list(xmin = 118.72, xmax = 118.88,
                 ymin =  37.73, ymax =  37.87)

roi <- ee$Geometry$Rectangle(
  coords = list(roi_bbox$xmin, roi_bbox$ymin, roi_bbox$xmax, roi_bbox$ymax),
  proj = "EPSG:4326",
  geodesic = FALSE
)

# ---- Image to export (SMOKE TEST) ----
# SRTM is guaranteed available and lightweight
img <- ee$Image("CGIAR/SRTM90_V4")$select("elevation")$clip(roi)

# ---- Export helper ----
export_to_drive <- function(img, description,
                            folder = "land_cover_gis_exports",
                            scale = 90,
                            crs = "EPSG:4326",
                            fileDimensions = list(2048, 2048)) {

  task <- ee$batch$Export$image$toDrive(
    image = img,
    description = description,
    folder = folder,
    fileNamePrefix = description,
    region = roi,
    scale = scale,
    crs = crs,
    maxPixels = 1e13,
    fileFormat = "GeoTIFF",
    fileDimensions = fileDimensions
  )
  task$start()
  cat("✅ Started Drive export task:", description, "\n")
  invisible(task)
}

# ---- Start task ----
desc <- "SMOKETEST_SRTM_Delta"
export_to_drive(img, desc)

cat("\nNext:\n",
    "1) Go to Google Drive -> folder 'land_cover_gis_exports'\n",
    "2) Wait for task to finish (in Drive/EE Tasks)\n",
    "3) Download SMOKETEST_SRTM_Delta.tif\n", sep = "")
