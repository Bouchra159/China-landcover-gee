# ========================================================================
# Part 3 (DELTA): Embeddings analysis — K-means (2024) + change (2018→2024)
# Inputs:
#   data/embeddings_delta/YR_delta_embeddings_2018.tif
#   data/embeddings_delta/YR_delta_embeddings_2024.tif
# Outputs:
#   results/embeddings_delta/*.tif
#   figures/embeddings_delta/*.png
# ========================================================================

source("Scripts/config.R")   # sets PROJECT_ROOT, terra options, KMEANS_K

dir.create("results/embeddings_delta", showWarnings = FALSE, recursive = TRUE)
dir.create("figures/embeddings_delta", showWarnings = FALSE, recursive = TRUE)

suppressPackageStartupMessages({
  library(ggplot2)
  library(tidyterra)
  library(dplyr)
})

# ---- Paths ----
f18 <- "data/embeddings_delta/YR_delta_embeddings_2018.tif"
f24 <- "data/embeddings_delta/YR_delta_embeddings_2024.tif"

if (!file.exists(f18)) stop("Missing: ", f18)
if (!file.exists(f24)) stop("Missing: ", f24)

emb18 <- rast(f18)
emb24 <- rast(f24)

cat("Loaded 2018 bands:", nlyr(emb18), "\n")
cat("Loaded 2024 bands:", nlyr(emb24), "\n")

# ---- Align grids (safe) ----
emb24a <- emb24
if (!compareGeom(emb18, emb24a, stopOnError = FALSE)) {
  cat("Resampling 2024 to match 2018 grid...\n")
  emb24a <- resample(emb24a, emb18, method = "bilinear")
}

# ---- Valid overlap mask (robust) ----
min_valid_dims <- 10  # if too strict, set to 1

cat("Computing valid overlap mask...\n")
valid_count <- app(
  is.finite(emb18) & is.finite(emb24a),
  fun = sum,
  filename = "results/embeddings_delta/valid_count.tif",
  overwrite = TRUE,
  wopt = list(datatype = "INT2S")
)

valid_overlap <- valid_count > min_valid_dims
overlap_frac <- global(valid_overlap, "mean", na.rm = FALSE)[1, 1]
cat("Valid overlap fraction =", overlap_frac, "\n")

emb18v <- mask(emb18,  valid_overlap, maskvalues = 0)
emb24v <- mask(emb24a, valid_overlap, maskvalues = 0)

# ========================================================================
# A) K-means clustering (2024 only)
# ========================================================================

set.seed(42)

# For Windows/no GPU: keep sampling moderate
n_samples <- 20000  # if fast enough, try 50000

cat("Sampling 2024 pixels for K-means...\n")
s <- spatSample(
  emb24v,
  size   = n_samples,
  method = "random",
  na.rm  = TRUE,
  as.df  = TRUE,
  values = TRUE
)

s <- s %>% select(where(is.numeric))
if (nrow(s) < 1000) stop("Too few valid samples. Try min_valid_dims <- 1")

cat("Scaling features...\n")
s_scaled <- scale(s)
center_vec <- attr(s_scaled, "scaled:center")
scale_vec  <- attr(s_scaled, "scaled:scale")

run_kmeans_map <- function(k) {
  cat("Running k-means K =", k, "...\n")

  km <- kmeans(s_scaled, centers = k, nstart = 10, iter.max = 100)
  centers <- km$centers   # (k x p), scaled space

  assign_fun <- function(v) {
    v <- as.matrix(v)

    # mark invalid pixels
    bad <- !apply(is.finite(v), 1, all)

    # SCALE LIKE TRAINING 
    p <- ncol(v)
    v <- sweep(v, 2, center_vec[1:p], "-")
    v <- sweep(v, 2, scale_vec[1:p], "/")
    
    # squared Euclidean distance
    v2 <- rowSums(v * v)
    c2 <- rowSums(centers * centers)
    vc <- v %*% t(centers)
    d  <- v2 + matrix(c2, nrow(v), k, byrow = TRUE) - 2 * vc

    cls <- max.col(-d) - 1   # 0..k-1 (EE-style)
    cls[bad] <- NA
    cls
  }

  terra::app(
    emb24v,
    fun = assign_fun,
    filename = sprintf(
      "results/embeddings_delta/clusters_2024_K%d.tif", k
    ),
    overwrite = TRUE,
    wopt = list(datatype = "INT2S")
  )
}

cl_k5  <- run_kmeans_map(5)
cl_k10 <- run_kmeans_map(10)

plot_clusters <- function(r, k) {
  ggplot() +
    geom_spatraster(data = as.factor(r)) +
    labs(title = paste0("Satellite Embeddings Clusters (2024) — K=", k)) +
    theme_minimal() +
    theme(legend.position = "none",
          plot.title = element_text(hjust = 0.5))
}

ggsave("figures/embeddings_delta/clusters_2024_K5.png",
       plot_clusters(cl_k5, 5), width = 7, height = 5, dpi = 220)

ggsave("figures/embeddings_delta/clusters_2024_K10.png",
       plot_clusters(cl_k10, 10), width = 7, height = 5, dpi = 220)

# ========================================================================
# B) Change detection (2018 → 2024): MAD + Cosine change
# ========================================================================

cat("Computing MAD...\n")
mad <- app(
  abs(emb24v - emb18v),
  fun = mean,
  na.rm = TRUE,
  filename = "results/embeddings_delta/mad_2018_2024.tif",
  overwrite = TRUE,
  wopt = list(datatype = "FLT4S")
)

cat("Computing cosine change...\n")
dot_r <- app(
  emb18v * emb24v,
  fun = sum,
  na.rm = TRUE,
  filename = "results/embeddings_delta/dot.tif",
  overwrite = TRUE,
  wopt = list(datatype = "FLT4S")
)

norm18 <- sqrt(app(
  emb18v * emb18v,
  fun = sum,
  na.rm = TRUE,
  filename = "results/embeddings_delta/norm18.tif",
  overwrite = TRUE,
  wopt = list(datatype = "FLT4S")
))

norm24 <- sqrt(app(
  emb24v * emb24v,
  fun = sum,
  na.rm = TRUE,
  filename = "results/embeddings_delta/norm24.tif",
  overwrite = TRUE,
  wopt = list(datatype = "FLT4S")
))

eps <- 1e-6
den <- norm18 * norm24
den[den < eps] <- NA

dot_r[valid_count <= min_valid_dims] <- NA
den[valid_count <= min_valid_dims]   <- NA

cos_sim <- clamp(dot_r / den, -1, 1)
cos_change <- 1 - cos_sim

writeRaster(cos_sim,
            "results/embeddings_delta/cosine_sim_2018_2024.tif",
            overwrite = TRUE, datatype = "FLT4S")

writeRaster(cos_change,
            "results/embeddings_delta/cosine_change_2018_2024.tif",
            overwrite = TRUE, datatype = "FLT4S")

# ---- Figures: clip at P99 for clean visuals ----
clip_p99 <- function(r) {
  v <- values(r)
  v <- v[is.finite(v)]
  if (length(v) == 0) return(r)
  p99 <- as.numeric(quantile(v, 0.99, names = FALSE))
  clamp(r, lower = 0, upper = p99)
}

mad_clip <- clip_p99(mad)
cos_clip <- clip_p99(cos_change)

p_mad <- ggplot() +
  geom_spatraster(data = mad_clip) +
  scale_fill_viridis_c(name = "MAD") +
  labs(title = "MAD change (2018 → 2024), clipped at P99",
       subtitle = paste0("min_valid_dims > ", min_valid_dims)) +
  theme_minimal() +
  theme(plot.title = element_text(hjust = 0.5))

ggsave("figures/embeddings_delta/mad_2018_2024_p99.png",
       p_mad, width = 7, height = 5, dpi = 220)

p_cos <- ggplot() +
  geom_spatraster(data = cos_clip) +
  scale_fill_viridis_c(name = "1 - cosine") +
  labs(title = "Cosine change (2018 → 2024), clipped at P99",
       subtitle = paste0("min_valid_dims > ", min_valid_dims)) +
  theme_minimal() +
  theme(plot.title = element_text(hjust = 0.5))

ggsave("figures/embeddings_delta/cosine_change_2018_2024_p99.png",
       p_cos, width = 7, height = 5, dpi = 220)

cat("\nDONE ✅\nSaved rasters -> results/embeddings_delta/\nSaved figures -> figures/embeddings_delta/\n")
