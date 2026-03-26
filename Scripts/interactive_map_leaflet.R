# ========================================================================
# interactive_map_leaflet.R
# Interactive HTML map of Yellow River Delta change analysis
# Outputs: figures/interactive_map.html  (standalone, shareable)
#
# Layers (toggle on/off in the browser):
#   - MAD change 2018→2024 (continuous, viridis)
#   - Cosine change 2018→2024 (continuous, plasma)
#   - Dynamic World land cover 2018 (classified)
#   - Dynamic World land cover 2024 (classified)
#   - K-means clusters K=5 (categorical)
#   - Extreme precipitation hotspots (P95)
#
# Usage: source("Scripts/interactive_map_leaflet.R")
# ========================================================================

source("Scripts/config.R")

# ---- 0) Packages --------------------------------------------------------
ensure_pkgs <- function(pkgs) {
  miss <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(miss)) install.packages(miss, dependencies = TRUE)
}
ensure_pkgs(c("leaflet", "leafem", "terra", "htmlwidgets", "RColorBrewer", "scales"))

suppressPackageStartupMessages({
  library(leaflet)
  library(leafem)
  library(terra)
  library(htmlwidgets)
  library(scales)
})

dir.create(PATHS$fig_dir, showWarnings = FALSE, recursive = TRUE)

# ---- 1) Helper: raster to EPSG:4326 PNG tile ----------------------------
# leafem::addGeotiff is the cleanest way to add large rasters to leaflet.
# We project to WGS84 and clip at the 1–99 percentile for colour mapping.

prep_raster <- function(r, percentile_clip = TRUE) {
  if (!compareGeom(r, rast(ext(r), crs = "EPSG:4326"), stopOnError = FALSE)) {
    r <- project(r, "EPSG:4326", method = "bilinear")
  }
  if (percentile_clip && nlyr(r) == 1) {
    v <- values(r)
    v <- v[is.finite(v)]
    lo <- as.numeric(quantile(v, 0.01, names = FALSE))
    hi <- as.numeric(quantile(v, 0.99, names = FALSE))
    r <- clamp(r, lower = lo, upper = hi)
  }
  r
}

# ---- 2) Load rasters ----------------------------------------------------
cat("Loading rasters...\n")

# MAD change map
mad_path <- PATHS$mad_roi
if (!file.exists(mad_path)) {
  mad_path <- "results/embeddings_delta/mad_2018_2024.tif"
}

# Cosine change map
cos_path <- PATHS$cos_roi
if (!file.exists(cos_path)) {
  cos_path <- "results/embeddings_delta/cosine_change_2018_2024.tif"
}

# Dynamic World land cover
dw18_path <- PATHS$dw_mode_2018
dw24_path <- PATHS$dw_mode_2024

# K-means clusters K=5
clust_path <- "results/embeddings_delta/clusters_2024_K5.tif"

# Extreme precipitation
precip_path <- "figures/YRDelta_extremeFreq_p95_2018_2024.tif"

# ---- 3) Colour palettes -------------------------------------------------
viridis_pal <- colorNumeric("viridis",  domain = NULL, na.color = "transparent")
plasma_pal  <- colorNumeric("plasma",   domain = NULL, na.color = "transparent")

dw_pal <- colorFactor(
  palette = unname(DW_COLORS),
  levels  = as.integer(names(DW_CLASSES)),
  na.color = "transparent"
)

cluster_colors <- c("#E41A1C", "#377EB8", "#4DAF4A", "#984EA3", "#FF7F00")
clust_pal <- colorFactor(cluster_colors, domain = 0:4, na.color = "transparent")

# ---- 4) Build map -------------------------------------------------------
cat("Building interactive map...\n")

map <- leaflet() |>
  # Base tiles
  addProviderTiles("Esri.WorldImagery",        group = "Satellite (Esri)") |>
  addProviderTiles("CartoDB.Positron",         group = "CartoDB Light") |>
  addProviderTiles("OpenStreetMap.Mapnik",     group = "OpenStreetMap") |>
  setView(lng = 118.85, lat = 37.75, zoom = 10)

# ---- MAD change layer ---------------------------------------------------
if (file.exists(mad_path)) {
  mad_r <- prep_raster(rast(mad_path))
  tmp_mad <- tempfile(fileext = ".tif")
  writeRaster(mad_r, tmp_mad, overwrite = TRUE)
  mad_vals <- values(mad_r)
  mad_vals <- mad_vals[is.finite(mad_vals)]
  mad_pal  <- colorNumeric("YlOrRd", domain = range(mad_vals), na.color = "transparent")

  map <- map |>
    addGeotiff(
      file   = tmp_mad,
      colorOptions = colorOptions(
        palette    = scales::col_numeric("YlOrRd", domain = range(mad_vals)),
        domain     = range(mad_vals),
        na.color   = "transparent"
      ),
      opacity = 0.75,
      group   = "MAD Change (2018→2024)"
    )
  cat("  MAD layer added.\n")
} else {
  cat("  MAD raster not found, skipping.\n")
}

# ---- Cosine change layer ------------------------------------------------
if (file.exists(cos_path)) {
  cos_r <- prep_raster(rast(cos_path))
  tmp_cos <- tempfile(fileext = ".tif")
  writeRaster(cos_r, tmp_cos, overwrite = TRUE)
  cos_vals <- values(cos_r)
  cos_vals <- cos_vals[is.finite(cos_vals)]

  map <- map |>
    addGeotiff(
      file   = tmp_cos,
      colorOptions = colorOptions(
        palette  = scales::col_numeric("plasma", domain = range(cos_vals)),
        domain   = range(cos_vals),
        na.color = "transparent"
      ),
      opacity = 0.75,
      group   = "Cosine Change (2018→2024)"
    )
  cat("  Cosine change layer added.\n")
} else {
  cat("  Cosine change raster not found, skipping.\n")
}

# ---- Dynamic World 2018 -------------------------------------------------
if (file.exists(dw18_path)) {
  dw18 <- project(rast(dw18_path), "EPSG:4326", method = "near")
  tmp_dw18 <- tempfile(fileext = ".tif")
  writeRaster(dw18, tmp_dw18, overwrite = TRUE, datatype = "INT1U")
  dw_vals <- as.integer(na.omit(unique(values(dw18))))

  map <- map |>
    addGeotiff(
      file   = tmp_dw18,
      colorOptions = colorOptions(
        palette  = scales::col_factor(
          unname(DW_COLORS[as.character(dw_vals)]),
          domain = dw_vals
        ),
        domain   = dw_vals,
        na.color = "transparent"
      ),
      opacity = 0.8,
      group   = "Dynamic World 2018"
    )
  cat("  Dynamic World 2018 layer added.\n")
} else {
  cat("  DW 2018 not found, skipping.\n")
}

# ---- Dynamic World 2024 -------------------------------------------------
if (file.exists(dw24_path)) {
  dw24 <- project(rast(dw24_path), "EPSG:4326", method = "near")
  tmp_dw24 <- tempfile(fileext = ".tif")
  writeRaster(dw24, tmp_dw24, overwrite = TRUE, datatype = "INT1U")
  dw_vals24 <- as.integer(na.omit(unique(values(dw24))))

  map <- map |>
    addGeotiff(
      file   = tmp_dw24,
      colorOptions = colorOptions(
        palette  = scales::col_factor(
          unname(DW_COLORS[as.character(dw_vals24)]),
          domain = dw_vals24
        ),
        domain   = dw_vals24,
        na.color = "transparent"
      ),
      opacity = 0.8,
      group   = "Dynamic World 2024"
    )
  cat("  Dynamic World 2024 layer added.\n")
} else {
  cat("  DW 2024 not found, skipping.\n")
}

# ---- K-means clusters K=5 -----------------------------------------------
if (file.exists(clust_path)) {
  cl5 <- project(rast(clust_path), "EPSG:4326", method = "near")
  tmp_cl5 <- tempfile(fileext = ".tif")
  writeRaster(cl5, tmp_cl5, overwrite = TRUE, datatype = "INT1U")
  cl_vals <- as.integer(na.omit(unique(values(cl5))))

  map <- map |>
    addGeotiff(
      file   = tmp_cl5,
      colorOptions = colorOptions(
        palette  = scales::col_factor(
          cluster_colors[seq_along(cl_vals)],
          domain = cl_vals
        ),
        domain   = cl_vals,
        na.color = "transparent"
      ),
      opacity = 0.75,
      group   = "K-means Clusters K=5 (2024)"
    )
  cat("  Clusters K=5 layer added.\n")
} else {
  cat("  Cluster raster not found, skipping.\n")
}

# ---- Extreme precipitation ----------------------------------------------
if (file.exists(precip_path)) {
  precip_r <- prep_raster(rast(precip_path))
  tmp_pr   <- tempfile(fileext = ".tif")
  writeRaster(precip_r, tmp_pr, overwrite = TRUE)
  pr_vals  <- values(precip_r)
  pr_vals  <- pr_vals[is.finite(pr_vals)]

  map <- map |>
    addGeotiff(
      file   = tmp_pr,
      colorOptions = colorOptions(
        palette  = scales::col_numeric("Blues", domain = range(pr_vals)),
        domain   = range(pr_vals),
        na.color = "transparent"
      ),
      opacity = 0.6,
      group   = "Extreme Precip P95 (2018–2024)"
    )
  cat("  Extreme precipitation layer added.\n")
} else {
  cat("  Extreme precip raster not found, skipping.\n")
}

# ---- ROI bounding box ---------------------------------------------------
map <- map |>
  addRectangles(
    lng1 = ROI_PRIMARY$xmin, lat1 = ROI_PRIMARY$ymin,
    lng2 = ROI_PRIMARY$xmax, lat2 = ROI_PRIMARY$ymax,
    fillColor = "transparent",
    color = "#FFFFFF", weight = 2, dashArray = "5,5",
    group = "Study Area ROI",
    label = "Yellow River Delta — Study Area"
  )

# ---- Layer controls + legends -------------------------------------------
map <- map |>
  addLayersControl(
    baseGroups = c("Satellite (Esri)", "CartoDB Light", "OpenStreetMap"),
    overlayGroups = c(
      "MAD Change (2018→2024)",
      "Cosine Change (2018→2024)",
      "Dynamic World 2018",
      "Dynamic World 2024",
      "K-means Clusters K=5 (2024)",
      "Extreme Precip P95 (2018–2024)",
      "Study Area ROI"
    ),
    options = layersControlOptions(collapsed = FALSE)
  ) |>
  hideGroup(c(
    "Cosine Change (2018→2024)",
    "Dynamic World 2018",
    "K-means Clusters K=5 (2024)",
    "Extreme Precip P95 (2018–2024)"
  )) |>
  addScaleBar(position = "bottomleft") |>
  addMiniMap(toggleDisplay = TRUE, minimized = TRUE) |>
  addControl(
    html = paste0(
      "<div style='background:rgba(255,255,255,0.9);padding:10px;",
      "border-radius:6px;font-family:Arial,sans-serif;font-size:13px;",
      "max-width:240px;'>",
      "<b>Yellow River Delta</b><br>",
      "Land Cover Change Detection<br>",
      "2018 \u2192 2024<br><br>",
      "<span style='color:#888'>Shandong Province, China</span><br>",
      "<span style='color:#888'>Google Satellite Embeddings V1</span><br>",
      "<span style='color:#888'>64-band \u00d7 10m resolution</span>",
      "</div>"
    ),
    position = "topleft"
  )

# ---- 5) Save ------------------------------------------------------------
out_path <- file.path(PATHS$fig_dir, "interactive_map.html")
saveWidget(map, out_path, selfcontained = TRUE, title = "Yellow River Delta — Land Cover Change 2018–2024")

cat("\nSaved interactive map to:", out_path, "\n")
cat("Open in any browser — fully standalone HTML (no server needed).\n")
