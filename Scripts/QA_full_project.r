# =========================================================
# QA_full_project.R — Land cover GIS project sanity check
# Run from project root: C:/Users/BOUCHRA/Documents/land_cover_gis
# =========================================================

cat("\n================= FULL PROJECT QA =================\n")

# ---- 0) Paths ----
proj <- getwd()
cat("Working dir:", proj, "\n")

need_dirs <- c("data", "results", "figures", "Scripts", "tmp")
cat("\n[DIR CHECK]\n")
for (d in need_dirs) {
  cat(sprintf(" - %-10s : %s\n", d, ifelse(dir.exists(d), "OK", "MISSING")))
}

# ---- 1) Script inventory ----
cat("\n[SCRIPTS CHECK]\n")
scripts <- list.files("Scripts", pattern="\\.[Rr]$", full.names=TRUE)
cat("Scripts found:", length(scripts), "\n")
print(basename(scripts))

must_scripts <- c(
  "part3_export_smoketest_delta.R",
  "part3_embeddings_analysis_delta.R"
)
for (s in must_scripts) {
  fp <- file.path("Scripts", s)
  cat(sprintf(" - %-35s : %s\n", s, ifelse(file.exists(fp), "OK", "MISSING")))
}

# ---- 2) Key data inputs check (edit these if your paths differ) ----
cat("\n[KEY INPUT FILES]\n")

key_files <- c(
  # Delta embeddings you exported from EE and downloaded
  "data/embeddings_delta/YR_delta_embeddings_2018.tif",
  "data/embeddings_delta/YR_delta_embeddings_2024.tif"
)

for (f in key_files) {
  cat(sprintf(" - %-60s : %s\n", f, ifelse(file.exists(f), "OK", "MISSING")))
}

# Optional: check if empty placeholder folders exist (safe)
cat("\n[INPUT FOLDERS]\n")
key_dirs <- c(
  "data/embeddings_delta",
  "data/embeddings_delta/2018_tiles",
  "data/embeddings_delta/2024_tiles",
  "data/embeddings_henan"
)
for (d in key_dirs) {
  cat(sprintf(" - %-40s : %s\n", d, ifelse(dir.exists(d), "OK", "MISSING")))
  if (dir.exists(d)) {
    n <- length(list.files(d, recursive=TRUE))
    cat("    items:", n, "\n")
  }
}

# ---- 3) Outputs check ----
cat("\n[RESULTS OUTPUTS]\n")
out_dirs <- c("results", "results/embeddings_delta", "results/change_detection")
for (d in out_dirs) {
  cat(sprintf(" - %-30s : %s\n", d, ifelse(dir.exists(d), "OK", "MISSING")))
  if (dir.exists(d)) {
    f <- list.files(d, recursive=TRUE)
    cat("    files:", length(f), "\n")
    if (length(f) > 0) cat("    sample:", paste(head(f, 5), collapse=" | "), "\n")
  }
}

cat("\n[FIGURES OUTPUTS]\n")
fig_dirs <- c("figures", "figures/embeddings_delta")
for (d in fig_dirs) {
  cat(sprintf(" - %-30s : %s\n", d, ifelse(dir.exists(d), "OK", "MISSING")))
  if (dir.exists(d)) {
    f <- list.files(d, recursive=TRUE)
    cat("    files:", length(f), "\n")
    if (length(f) > 0) cat("    sample:", paste(head(f, 5), collapse=" | "), "\n")
  }
}

# ---- 4) Raster integrity checks (core outputs) ----
suppressPackageStartupMessages(library(terra))

cat("\n[RASTER INTEGRITY]\n")

check_raster <- function(path) {
  if (!file.exists(path)) {
    cat(" -", path, ": MISSING\n")
    return(invisible(NULL))
  }
  r <- try(rast(path), silent=TRUE)
  if (inherits(r, "try-error")) {
    cat(" -", path, ": FAILED TO READ (corrupt?)\n")
    return(invisible(NULL))
  }
  cat(" -", path, "\n")
  cat("    nlyr:", nlyr(r), " | ncell:", ncell(r), "\n")
  cat("    crs :", ifelse(is.na(crs(r)), "NA", "OK"), "\n")
  cat("    res :", paste(res(r), collapse=", "), "\n")
  cat("    ext :", paste(as.vector(ext(r)), collapse=", "), "\n")
  invisible(r)
}

# Core results expected from your delta analysis
core_out <- c(
  "results/embeddings_delta/mad_2018_2024.tif",
  "results/embeddings_delta/cosine_sim_2018_2024.tif",
  "results/embeddings_delta/cosine_change_2018_2024.tif",
  "results/embeddings_delta/clusters_2024_K5.tif",
  "results/embeddings_delta/clusters_2024_K10.tif",
  "results/embeddings_delta/valid_count.tif"
)

ras <- list()
for (p in core_out) ras[[p]] <- check_raster(p)

# ---- 5) Value sanity checks ----
cat("\n[VALUE SANITY]\n")

if (!is.null(ras[["results/embeddings_delta/mad_2018_2024.tif"]])) {
  mad <- ras[["results/embeddings_delta/mad_2018_2024.tif"]]
  print(global(mad, c("min","max","mean"), na.rm=TRUE))
}

if (!is.null(ras[["results/embeddings_delta/cosine_sim_2018_2024.tif"]])) {
  cs <- ras[["results/embeddings_delta/cosine_sim_2018_2024.tif"]]
  print(global(cs, c("min","max","mean"), na.rm=TRUE))
}

if (!is.null(ras[["results/embeddings_delta/cosine_change_2018_2024.tif"]])) {
  cc <- ras[["results/embeddings_delta/cosine_change_2018_2024.tif"]]
  print(global(cc, c("min","max","mean"), na.rm=TRUE))
}
# ---- Cluster frequency checks ----

if (!is.null(ras[["results/embeddings_delta/clusters_2024_K5.tif"]])) {
  k5 <- ras[["results/embeddings_delta/clusters_2024_K5.tif"]]

  cat("\nCluster freq K5:\n")
  f <- freq(k5)
  f <- f[!is.na(f$value), ]
  f$pct <- 100 * f$count / sum(f$count)
  print(f)
}

if (!is.null(ras[["results/embeddings_delta/clusters_2024_K10.tif"]])) {
  k10 <- ras[["results/embeddings_delta/clusters_2024_K10.tif"]]

  cat("\nCluster freq K10:\n")
  f <- freq(k10)
  f <- f[!is.na(f$value), ]
  f$pct <- 100 * f$count / sum(f$count)
  print(f)
}
cat("\n================= QA DONE =================\n")
