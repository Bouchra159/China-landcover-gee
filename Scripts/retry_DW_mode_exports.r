library(reticulate)

Sys.setenv(RETICULATE_PYTHON = "C:/Python313/python.exe")
ee <- import("ee")

ee$Authenticate()
ee$Initialize(project = "ee-yellow-river-481216")

# Same AOI as before
xmin <- 118.35; xmax <- 119.35
ymin <- 37.35; ymax <- 38.15

region <- ee$Geometry$Rectangle(
  coords = list(xmin, ymin, xmax, ymax),
  proj = "EPSG:4326",
  geodesic = FALSE
)

drive_folder <- "YR_delta_exports"
scale_m <- 10

dw <- ee$ImageCollection("GOOGLE/DYNAMICWORLD/V1")$
  filterBounds(region)$
  select("label")

dw_mode_year <- function(year) {
  start <- sprintf("%d-01-01", year)
  end   <- sprintf("%d-12-31", year)

  dw$filterDate(start, end)$
    reduce(ee$Reducer$mode())$
    rename("dw_mode")$
    toInt()$
    clip(region)
}

dw2018 <- dw_mode_year(2018L)
dw2024 <- dw_mode_year(2024L)

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

export_to_drive(dw2018, "DW_mode_2018_delta_retry", "DW_mode_2018_delta")
export_to_drive(dw2024, "DW_mode_2024_delta_retry", "DW_mode_2024_delta")

cat("\n✅ Re-export submitted. Now go to Tasks and click RUN.\n")
