# ========================================================================
# Part 2 (CLEAN + ROBUST): ROI crop-first VRT + MAD + Cosine change + figures
# Yellow River subregion (tutorial-style) — 2018 vs 2024 embeddings
# Author: Bouchra Daddaoui
# ========================================================================

# ---- 0) Setup ----
source("Scripts/config.R")   # sets PROJECT_ROOT, terra options, DW_CLASSES

dir.create("results", showWarnings = FALSE, recursive = TRUE)
dir.create("results/change_detection", showWarnings = FALSE, recursive = TRUE)
dir.create("figures", showWarnings = FALSE, recursive = TRUE)

suppressPackageStartupMessages({
  library(ggplot2)
  library(tidyterra)
})

# ---- 1) Inputs ----
tiles_dir_2018 <- "data/embeddings/2018_tiles"
tiles_dir_2024 <- "data/embeddings/2024_tiles"

tiles18 <- list.files(tiles_dir_2018, pattern = "\\.tif$", full.names = TRUE)
tiles24 <- list.files(tiles_dir_2024, pattern = "\\.tif$", full.names = TRUE)

if (length(tiles18) == 0) stop("No .tif tiles found in: ", tiles_dir_2018)
if (length(tiles24) == 0) stop("No .tif tiles found in: ", tiles_dir_2024)

cat("2018 tiles:", length(tiles18), "\n")
cat("2024 tiles:", length(tiles24), "\n")
cat("Example 2018 tile:", basename(tiles18[1]), "\n")
cat("Example 2024 tile:", basename(tiles24[1]), "\n\n")

# ---- 2) Choose ONE small region (tutorial-style ROI) ----
# Option A: Zhengzhou / Huayuankou (recommended)
xmin <- 118.55; xmax <- 119.45
ymin <- 37.35;  ymax <- 38.10
# You can later switch ROI to another Yellow River subregion by editing these numbers.
roi <- ext(xmin, xmax, ymin, ymax)

# Minimum number of valid embedding dimensions required per pixel
# (Start with 1 for lenient; 10–20 is stricter/cleaner)
min_valid_dims <- 1

# ---- 3) Build VRTs (virtual mosaics) + crop first (fast) ----
emb18_vrt <- vrt(tiles18)
emb24_vrt <- vrt(tiles24)

emb18 <- crop(emb18_vrt, roi)
emb24 <- crop(emb24_vrt, roi)

cat("Bands 2018:", nlyr(emb18), " Bands 2024:", nlyr(emb24), "\n")

# ---- 4) Align 2024 to 2018 grid ----
emb24a <- emb24
if (!compareGeom(emb18, emb24a, stopOnError = FALSE)) {
  cat("Resampling 2024 to match 2018 grid...\n")
  emb24a <- resample(emb24a, emb18, method = "bilinear")
}

# ---- 5) Valid overlap across ALL bands ----
# Count how many embedding dims are finite in BOTH years at each pixel
cat("Computing valid dimension count...\n")
valid_count <- app(
  is.finite(emb18) & is.finite(emb24a),
  fun = sum,
  filename = "results/change_detection/valid_count_roi.tif",
  overwrite = TRUE,
  wopt = list(datatype = "INT2S")
)

valid_overlap <- valid_count > min_valid_dims

overlap_frac <- global(valid_overlap, "mean", na.rm = FALSE)[1, 1]
cat("Valid overlap fraction (all bands) =", overlap_frac, "\n")
cat("Min valid dims threshold =", min_valid_dims, "\n\n")

emb18v <- mask(emb18,  valid_overlap, maskvalues = 0)
emb24v <- mask(emb24a, valid_overlap, maskvalues = 0)

# ---- 6) MAD change (mean absolute diff across bands) ----
cat("Computing MAD...\n")
mad <- app(
  abs(emb24v - emb18v),
  fun = mean,
  na.rm = TRUE,
  filename = "results/change_detection/mad_2018_2024_roi.tif",
  overwrite = TRUE,
  wopt = list(datatype = "FLT4S")
)
cat("Saved MAD ROI.\n\n")

# ---- 7) Cosine similarity + cosine change (robust) ----
cat("Computing cosine similarity...\n")
stopifnot(nlyr(emb18v) == nlyr(emb24v))

# Dot product sum across bands (ignoring NA dims)
dot_r <- app(
  emb18v * emb24v,
  fun = sum,
  na.rm = TRUE,
  filename = "results/change_detection/dot_roi.tif",
  overwrite = TRUE,
  wopt = list(datatype = "FLT4S")
)

# Norms
norm18 <- sqrt(app(
  emb18v * emb18v,
  fun = sum,
  na.rm = TRUE,
  filename = "results/change_detection/norm18_roi.tif",
  overwrite = TRUE,
  wopt = list(datatype = "FLT4S")
))

norm24 <- sqrt(app(
  emb24v * emb24v,
  fun = sum,
  na.rm = TRUE,
  filename = "results/change_detection/norm24_roi.tif",
  overwrite = TRUE,
  wopt = list(datatype = "FLT4S")
))

eps <- 1e-6  # small stabilizer
den <- norm18 * norm24
den[den < eps] <- NA   # treat truly tiny vectors as missing

# Make sure pixels with 0 valid dims are NA (prevents cosine being NA everywhere)
dot_r[valid_count <= min_valid_dims] <- NA
den[valid_count <= min_valid_dims] <- NA

cos_sim <- dot_r / den
cos_sim <- clamp(cos_sim, -1, 1)
cos_change <- 1 - cos_sim

writeRaster(
  cos_sim,
  "results/change_detection/cosine_sim_2018_2024_roi.tif",
  overwrite = TRUE,
  datatype = "FLT4S"
)

writeRaster(
  cos_change,
  "results/change_detection/cosine_change_2018_2024_roi.tif",
  overwrite = TRUE,
  datatype = "FLT4S"
)

cat("Saved cosine ROI.\n\n")

# ---- 8) Figures (clipped at P99) ----
cat("Saving figures...\n")
mad_vals <- values(mad)
cos_vals <- values(cos_change)

mad_vals <- mad_vals[is.finite(mad_vals)]
cos_vals <- cos_vals[is.finite(cos_vals)]

if (length(mad_vals) == 0) stop("MAD has no finite values in ROI. Check valid_count threshold.")
if (length(cos_vals) == 0) {
  warning("Cosine change has no finite values in ROI; skipping cosine figure.")
} else {
  # make cosine figure here
}

mad_p99 <- as.numeric(quantile(mad_vals, 0.99, names = FALSE))
cos_p99 <- as.numeric(quantile(cos_vals, 0.99, names = FALSE))

if (!is.finite(mad_p99)) mad_p99 <- max(mad_vals)
if (!is.finite(cos_p99)) cos_p99 <- max(cos_vals)

mad_clip <- clamp(mad, lower = 0, upper = mad_p99)
cos_clip <- clamp(cos_change, lower = 0, upper = cos_p99)

p1 <- ggplot() +
  geom_spatraster(data = mad_clip) +
  scale_fill_viridis_c(name = "MAD") +
  labs(title = "MAD (ROI, clipped at P99)",
       subtitle = paste0("2018 → 2024 | min_valid_dims > ", min_valid_dims)) +
  theme_minimal()

ggsave("figures/mad_roi_p99.png", p1, width = 7, height = 5, dpi = 200)

p2 <- ggplot() +
  geom_spatraster(data = cos_clip) +
  scale_fill_viridis_c(name = "1 - cosine") +
  labs(title = "Cosine change (ROI, clipped at P99)",
       subtitle = paste0("2018 → 2024 | min_valid_dims > ", min_valid_dims)) +
  theme_minimal()

ggsave("figures/cosine_change_roi_p99.png", p2, width = 7, height = 5, dpi = 200)

cat("Figures saved in figures/ ✅\n")
cat("DONE ✅\n")
