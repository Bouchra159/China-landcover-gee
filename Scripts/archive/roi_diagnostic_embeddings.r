# ========================================================================
# ROI Diagnostic for Embeddings (2018 + 2024) — Yellow River Delta
# Checks: (1) ROI overlaps tiles, (2) % valid pixels, (3) norms > 0
# ========================================================================

setwd("C:/Users/BOUCHRA/Documents/land_cover_gis")

suppressPackageStartupMessages({
  library(terra)
  library(dplyr)
})

tiles18 <- list.files("data/embeddings/2018_tiles", pattern="\\.tif$", full.names=TRUE)
tiles24 <- list.files("data/embeddings/2024_tiles", pattern="\\.tif$", full.names=TRUE)

stopifnot(length(tiles18) > 0, length(tiles24) > 0)

emb18_vrt <- vrt(tiles18)
emb24_vrt <- vrt(tiles24)

candidates <- list(
  ROI_A_delta_core   = ext(118.55, 119.35, 37.55, 38.15),
  ROI_B_river_mouth  = ext(119.00, 119.45, 37.65, 38.05),
  ROI_C_inland_mix   = ext(118.35, 118.95, 37.45, 37.95)
)

roi_report <- function(roi, name){

  # First: check overlap with total extent
  if (!relate(ext(emb24_vrt), roi, "intersects")) {
    return(data.frame(roi=name, ok=FALSE, reason="No overlap with 2024 tiles"))
  }
  if (!relate(ext(emb18_vrt), roi, "intersects")) {
    return(data.frame(roi=name, ok=FALSE, reason="No overlap with 2018 tiles"))
  }

  e18 <- crop(emb18_vrt[[1]], roi)  # just band1 for coverage check
  e24 <- crop(emb24_vrt[[1]], roi)

  # If crop produced empty (can happen)
  if (ncell(e18) == 0 || ncell(e24) == 0) {
    return(data.frame(roi=name, ok=FALSE, reason="Crop resulted in 0 cells"))
  }

  # % valid (non-NA) pixels in band1
  v18 <- global(!is.na(e18), "mean", na.rm=FALSE)[1,1]
  v24 <- global(!is.na(e24), "mean", na.rm=FALSE)[1,1]

  # Quick “vector norm” check (use small sample of bands to save time)
  # If norms are ~0 everywhere, cosine change will break.
  e18s <- crop(emb18_vrt[[1:8]], roi)
  e24s <- crop(emb24_vrt[[1:8]], roi)

  if (!compareGeom(e18s, e24s, stopOnError = FALSE)) {
    e24s <- resample(e24s, e18s, method="bilinear")
  }

  n18 <- sqrt(app(e18s*e18s, fun=sum, na.rm=TRUE))
  n24 <- sqrt(app(e24s*e24s, fun=sum, na.rm=TRUE))

  r18 <- global(n18, range, na.rm=TRUE)
  r24 <- global(n24, range, na.rm=TRUE)

  data.frame(
    roi=name,
    ok = TRUE,
    valid18 = round(v18, 3),
    valid24 = round(v24, 3),
    norm18_min = round(r18[1,1], 4),
    norm18_max = round(r18[1,2], 4),
    norm24_min = round(r24[1,1], 4),
    norm24_max = round(r24[1,2], 4)
  )
}

out <- bind_rows(lapply(names(candidates), function(nm) roi_report(candidates[[nm]], nm)))
print(out)

cat("\nRULE OF THUMB:\n")
cat("- valid18 and valid24 should be >= 0.30 (>=0.50 is excellent)\n")
cat("- norm*_max should be > 0 (not all zeros)\n")
