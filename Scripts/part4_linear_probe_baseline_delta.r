# part4_linear_probe_baseline_delta.R
# Linear probe baseline vs Random Forest on Satellite Embeddings
# + Confusion matrix heatmap
# + Spatial prediction & error maps (poster-grade)

Sys.setenv(RETICULATE_PYTHON = "C:/Users/BOUCHRA/Documents/.virtualenvs/r-reticulate/Scripts/python.exe")
setwd("C:/Users/BOUCHRA/Documents/land_cover_gis")

dir.create("results/linear_probe", recursive = TRUE, showWarnings = FALSE)
dir.create("figures/linear_probe", recursive = TRUE, showWarnings = FALSE)
dir.create("tmp", recursive = TRUE, showWarnings = FALSE)

# Increase download timeout (Earth Engine can be slow)
options(timeout = max(600, getOption("timeout")))

# --------------------------
# 0) Helper: install missing packages
# --------------------------
ensure_pkgs <- function(pkgs) {
  missing <- pkgs[!vapply(pkgs, requireNamespace, FUN.VALUE = logical(1), quietly = TRUE)]
  if (length(missing) > 0) {
    install.packages(missing, dependencies = TRUE)
  }
}
ensure_pkgs(c("terra", "ggplot2", "dplyr", "tidyr", "reticulate", "glmnet", "ranger"))

suppressPackageStartupMessages({
  library(terra)
  library(ggplot2)
  library(dplyr)
  library(tidyr)
  library(reticulate)
  library(glmnet)
  library(ranger)
})

terraOptions(tempdir = file.path(getwd(), "tmp"), memfrac = 0.6, progress = 1)

# --------------------------
# A) Load embeddings (2024)
# --------------------------
emb_path <- "data/embeddings_delta/YR_delta_embeddings_2024.tif"
if (!file.exists(emb_path)) stop("Missing embeddings: ", emb_path)

emb <- rast(emb_path)
cat("Embeddings loaded. Bands:", nlyr(emb), "\n")

emb_crs <- crs(emb, proj = TRUE)
cat("Emb CRS:", emb_crs, "\n")

e <- ext(emb)
stopifnot(e$xmin < e$xmax, e$ymin < e$ymax)
cat(sprintf("Emb extent (native CRS): xmin=%.3f xmax=%.3f ymin=%.3f ymax=%.3f\n",
            e$xmin, e$xmax, e$ymin, e$ymax))

# Convert bbox to EPSG:4326 for Earth Engine ROI definition
bbox_native <- as.polygons(e)
crs(bbox_native) <- emb_crs
bbox_ll <- project(bbox_native, "EPSG:4326")
bb <- ext(bbox_ll)

cat(sprintf("BBox in EPSG:4326: xmin=%.6f xmax=%.6f ymin=%.6f ymax=%.6f\n",
            bb$xmin, bb$xmax, bb$ymin, bb$ymax))

# --------------------------
# B) Build / load Dynamic World label raster (GEE)
# --------------------------
dw_label_path <- "data/embeddings_delta/DW_label_2024_delta.tif"

if (!file.exists(dw_label_path)) {
  cat("\n[DW] Label raster not found -> generating via GEE...\n")

  cfg <- py_config()
  cat("[PY] Using Python:", cfg$python, "\n")

  ee <- import("ee", delay_load = FALSE)
  ee$Initialize(project = "ee-yellow-river-481216")

  roi <- ee$Geometry$Rectangle(
    coords = list(bb$xmin, bb$ymin, bb$xmax, bb$ymax),
    proj = "EPSG:4326",
    geodesic = FALSE
  )

  dw_ic <- ee$ImageCollection("GOOGLE/DYNAMICWORLD/V1")$
    filterDate("2024-01-01", "2025-01-01")$
    filterBounds(roi)$
    select("label")

  dw_mode <- dw_ic$reduce(ee$Reducer$mode())$
    rename("dw_label")$
    clip(roi)$
    toInt()

  region_coords <- list(list(
    list(bb$xmin, bb$ymin),
    list(bb$xmax, bb$ymin),
    list(bb$xmax, bb$ymax),
    list(bb$xmin, bb$ymax),
    list(bb$xmin, bb$ymin)
  ))

  DW_SCALE <- 20
  cat(sprintf("[DW] Requesting download (scale=%dm) ...\n", DW_SCALE))

  url <- dw_mode$getDownloadURL(list(
    name = "DW_label_2024_delta",
    scale = DW_SCALE,
    region = region_coords,
    crs = "EPSG:4326",
    fileFormat = "GeoTIFF"
  ))

  cat("[DW] Downloading label (robust)...\n")

  tmp_download <- file.path("tmp", "DW_label_2024_delta_download.bin")
  if (file.exists(tmp_download)) file.remove(tmp_download)

  ok_dl <- FALSE
  for (attempt in 1:3) {
    cat(sprintf("[DW] Download attempt %d/3 (timeout=%ds)\n", attempt, getOption("timeout")))
    res <- try(download.file(url, tmp_download, mode = "wb", quiet = TRUE), silent = TRUE)
    if (!inherits(res, "try-error") && file.exists(tmp_download) && file.info(tmp_download)$size > 0) {
      ok_dl <- TRUE
      break
    }
    Sys.sleep(2 * attempt)
  }
  if (!ok_dl) stop("[DW] Download failed after 3 attempts (timeout). Try again or use a different network.")

  hdr <- readBin(tmp_download, what = "raw", n = 4)
  is_zip <- length(hdr) == 4 && as.integer(hdr[1]) == 0x50 && as.integer(hdr[2]) == 0x4B

  if (is_zip) {
    cat("[DW] Download is ZIP -> extracting...\n")
    unzip(tmp_download, exdir = "tmp")
    tif_files <- list.files("tmp", pattern = "\\.tif(f)?$", full.names = TRUE, ignore.case = TRUE)
    if (length(tif_files) == 0) stop("[DW] ZIP extracted but no .tif found in tmp/.")
    file.copy(tif_files[1], dw_label_path, overwrite = TRUE)
    cat("[DW] Extracted and saved:", dw_label_path, "\n")
  } else {
    file.copy(tmp_download, dw_label_path, overwrite = TRUE)
    ok <- FALSE
    try({ rast(dw_label_path); ok <- TRUE }, silent = TRUE)
    if (!ok) {
      cat("\n[DW] Downloaded file is not a valid GeoTIFF.\n")
      cat("[DW] First 50 lines (likely error HTML/text):\n\n")
      txt <- readLines(dw_label_path, warn = FALSE)
      cat(paste(head(txt, 50), collapse = "\n"), "\n")
      stop("\n[DW] Download failed: not a valid GeoTIFF (see message above).")
    } else {
      cat("[DW] Saved:", dw_label_path, "\n")
    }
  }

} else {
  cat("\n[DW] Found existing label raster:", dw_label_path, "\n")
}

dw <- rast(dw_label_path)

# Put DW on same CRS + grid as embeddings
if (!compareGeom(emb[[1]], dw, stopOnError = FALSE)) {
  cat("[DW] Projecting labels to match embeddings CRS/grid...\n")
  dw <- project(dw, emb[[1]], method = "near")
}

# --------------------------
# C) Sample pixels: X=embeddings, y=DW label
# --------------------------
set.seed(42)
valid <- app(is.finite(emb), fun = function(v) as.integer(all(v)), cores = 1)
valid <- (valid == 1)

stack_all <- c(dw, emb)
names(stack_all)[1] <- "y"

N_TOTAL <- 15000
cat("\nSampling up to", N_TOTAL, "points...\n")

stack_all <- mask(stack_all, valid)
stack_all <- mask(stack_all, !is.na(stack_all$y))

samp <- spatSample(stack_all, size = N_TOTAL, method = "random", as.df = TRUE, na.rm = TRUE)
samp$y <- as.integer(samp$y)
samp <- samp[is.finite(samp$y), ]

cat("Sampled rows:", nrow(samp), "\n")
cat("Unique classes in sample:", length(unique(samp$y)), "\n")

set.seed(42)
idx <- sample(seq_len(nrow(samp)), size = floor(0.8 * nrow(samp)))
train <- samp[idx, ]
test  <- samp[-idx, ]
x_cols <- setdiff(colnames(train), "y")

macro_f1 <- function(y_true, y_pred) {
  y_true <- factor(y_true)
  y_pred <- factor(y_pred, levels = levels(y_true))
  classes <- levels(y_true)
  f1s <- sapply(classes, function(cl) {
    tp <- sum(y_true == cl & y_pred == cl)
    fp <- sum(y_true != cl & y_pred == cl)
    fn <- sum(y_true == cl & y_pred != cl)
    prec <- ifelse(tp + fp == 0, 0, tp / (tp + fp))
    rec  <- ifelse(tp + fn == 0, 0, tp / (tp + fn))
    ifelse(prec + rec == 0, 0, 2 * prec * rec / (prec + rec))
  })
  mean(f1s)
}
acc <- function(y_true, y_pred) mean(y_true == y_pred)

# --------------------------
# E) Linear probe (ridge multinomial)
# --------------------------
cat("\nTraining LINEAR PROBE (ridge multinomial)...\n")
x_train <- as.matrix(train[, x_cols])
y_train <- factor(train$y)
x_test  <- as.matrix(test[, x_cols])
y_test  <- factor(test$y, levels = levels(y_train))

fit_lp <- cv.glmnet(
  x_train, y_train,
  family = "multinomial",
  alpha = 0,
  type.measure = "class",
  nfolds = 5
)

pred_lp <- as.vector(predict(fit_lp, newx = x_test, s = "lambda.min", type = "class"))
lp_acc <- acc(y_test, pred_lp)
lp_f1  <- macro_f1(y_test, pred_lp)

cat("Linear probe ACC:", lp_acc, "\n")
cat("Linear probe macro-F1:", lp_f1, "\n")

# --------------------------
# F) Random Forest
# --------------------------
cat("\nTraining RANDOM FOREST...\n")
rf_df_train <- train; rf_df_train$y <- factor(rf_df_train$y)
rf_df_test  <- test;  rf_df_test$y  <- factor(rf_df_test$y, levels = levels(rf_df_train$y))

fit_rf <- ranger(
  y ~ .,
  data = rf_df_train,
  num.trees = 300,
  mtry = floor(sqrt(length(x_cols))),
  min.node.size = 5,
  importance = "impurity"
)

pred_rf <- predict(fit_rf, data = rf_df_test)$predictions
rf_acc <- acc(rf_df_test$y, pred_rf)
rf_f1  <- macro_f1(rf_df_test$y, pred_rf)

cat("RF ACC:", rf_acc, "\n")
cat("RF macro-F1:", rf_f1, "\n")

# --------------------------
# I) Confusion matrix + per-class metrics (RF)
# --------------------------
dw_classes <- c(
  "Water", "Trees", "Grass", "Flooded vegetation", "Crops",
  "Shrub & scrub", "Built area", "Bare ground", "Snow & ice"
)

y_true <- factor(rf_df_test$y, levels = levels(rf_df_train$y))
y_pred <- factor(pred_rf, levels = levels(y_true))

cm <- table(y_true, y_pred)
cm_norm <- prop.table(cm, margin = 1)

precision <- ifelse(colSums(cm) == 0, NA, diag(cm) / colSums(cm))
recall    <- ifelse(rowSums(cm) == 0, NA, diag(cm) / rowSums(cm))
f1        <- ifelse(is.na(precision) | is.na(recall) | (precision + recall == 0),
                    0, 2 * precision * recall / (precision + recall))

per_class_metrics <- data.frame(
  class_id = as.integer(levels(y_true)),
  class_name = dw_classes[as.integer(levels(y_true)) + 1],
  precision = precision,
  recall = recall,
  f1 = f1,
  support = as.integer(rowSums(cm)),
  row.names = NULL
)

write.csv(per_class_metrics, "results/linear_probe/per_class_metrics_rf.csv", row.names = FALSE)

cm_long <- as.data.frame(as.table(cm_norm))
colnames(cm_long) <- c("true_class", "pred_class", "fraction")
cm_long$true_class_name <- dw_classes[as.integer(as.character(cm_long$true_class)) + 1]
cm_long$pred_class_name <- dw_classes[as.integer(as.character(cm_long$pred_class)) + 1]

write.csv(cm_long, "results/linear_probe/confusion_matrix_rf_normalized.csv", row.names = FALSE)

# Per-class F1 plot with sample support
per_class_metrics$label_n <- paste0("n=", per_class_metrics$support)

p_f1 <- ggplot(per_class_metrics,
               aes(x = reorder(class_name, f1), y = f1)) +
  geom_col() +
  geom_text(aes(label = label_n), hjust = -0.1, size = 3) +
  coord_flip() +
  ylim(0, 1.05) +
  theme_minimal(base_size = 14) +
  labs(
    title = "Per-class F1 (Random Forest, 2024) with sample support",
    x = NULL,
    y = "F1 score"
  )

ggsave("figures/linear_probe/per_class_f1_rf.png",
       p_f1, width = 8.5, height = 5.5, dpi = 300)

cat("\nSaved:\n- results/linear_probe/per_class_metrics_rf.csv\n- results/linear_probe/confusion_matrix_rf_normalized.csv\n- figures/linear_probe/per_class_f1_rf.png\n")

# --------------------------
# J) Confusion matrix HEATMAP (poster-grade)
# --------------------------
cm_long_plot <- cm_long
cm_long_plot$true_class_name <- factor(cm_long_plot$true_class_name,
                                       levels = rev(unique(cm_long_plot$true_class_name)))
cm_long_plot$pred_class_name <- factor(cm_long_plot$pred_class_name,
                                       levels = unique(cm_long_plot$pred_class_name))

p_cm <- ggplot(cm_long_plot, aes(x = pred_class_name, y = true_class_name, fill = fraction)) +
  geom_tile() +
  theme_minimal(base_size = 13) +
  labs(
    title = "Normalized confusion matrix (Random Forest, 2024)",
    x = "Predicted class",
    y = "True class",
    fill = "Fraction"
  ) +
  theme(
    axis.text.x = element_text(angle = 35, hjust = 1),
    panel.grid = element_blank()
  )

ggsave("figures/linear_probe/confusion_matrix_rf_normalized.png",
       p_cm, width = 8.8, height = 6.2, dpi = 300)

cat("Saved: figures/linear_probe/confusion_matrix_rf_normalized.png\n")

# --------------------------
# G) Save overall metrics + plot
# --------------------------
metrics <- data.frame(
  model = c("Linear probe (ridge)", "Random Forest"),
  accuracy = c(lp_acc, rf_acc),
  macro_f1 = c(lp_f1, rf_f1)
)

write.csv(metrics, "results/linear_probe/metrics_linear_vs_rf.csv", row.names = FALSE)

p <- ggplot(metrics |> pivot_longer(c(accuracy, macro_f1)),
            aes(x = model, y = value)) +
  geom_col() +
  facet_wrap(~name, scales = "free_y") +
  theme_minimal(base_size = 14) +
  labs(
    title = "Dynamic World label prediction from 64-band embeddings (Delta ROI, 2024)",
    x = NULL, y = NULL
  ) +
  theme(axis.text.x = element_text(angle = 12, hjust = 1))

ggsave("figures/linear_probe/linear_probe_vs_rf.png", p, width = 9, height = 4.8, dpi = 300)

cat("\nSaved:\n- results/linear_probe/metrics_linear_vs_rf.csv\n- figures/linear_probe/linear_probe_vs_rf.png\n")

# --------------------------
# H) Coefficients (optional interpretability)
# --------------------------
coef_list <- coef(fit_lp, s = "lambda.min")
cls_names <- names(coef_list)

topK <- 15
top_table <- do.call(rbind, lapply(seq_along(coef_list), function(i) {
  cf <- as.matrix(coef_list[[i]])
  cf <- cf[rownames(cf) != "(Intercept)", , drop = FALSE]
  ord <- order(abs(cf[,1]), decreasing = TRUE)[1:min(topK, nrow(cf))]
  data.frame(
    class = cls_names[i],
    band = rownames(cf)[ord],
    weight = cf[ord,1],
    abs_weight = abs(cf[ord,1]),
    row.names = NULL
  )
}))

write.csv(top_table, "results/linear_probe/top_linear_probe_weights.csv", row.names = FALSE)
cat("Saved: results/linear_probe/top_linear_probe_weights.csv\n")

# --------------------------
# K) Spatial maps: RF prediction + disagreement with DW (EO/GIS poster gold)
# --------------------------
cat("\n[MAP] Generating spatial prediction + error maps...\n")

# We need a predictor stack for the whole ROI (all 64 bands)
# Predict in chunks to avoid memory issues
# terra::predict works with ranger if we provide a wrapper
predict_fun <- function(model, data) {
  if (is.matrix(data)) data <- as.data.frame(data)
  preds <- predict(model, data = data)$predictions
  as.numeric(as.character(preds))
}

# Use same factor levels mapping (class IDs are 0..8)
# Create a clean predictor raster stack
pred_stack <- emb

# Run prediction
rf_pred <- terra::predict(
  pred_stack, fit_rf, fun = predict_fun,
  filename = "results/linear_probe/rf_predicted_labels_2024.tif",
  overwrite = TRUE
)

# Ensure DW labels are aligned (already projected)
dw_aligned <- dw

# Disagreement map (1 = mismatch, 0 = match)
err_map <- (rf_pred != dw_aligned)
err_map <- classify(err_map, rbind(c(0,0), c(1,1)), others = NA)  # keep 0/1 clean

writeRaster(err_map, "results/linear_probe/rf_disagreement_map_2024.tif",
            overwrite = TRUE, datatype = "INT1U")

# Quick plot maps (PNG)
# 1) RF prediction map
png("figures/linear_probe/rf_prediction_map_2024.png", width = 1400, height = 900, res = 150)
plot(rf_pred, main = "RF predicted Dynamic World labels (Delta ROI, 2024)")
dev.off()

# 2) Disagreement map
png("figures/linear_probe/rf_disagreement_map_2024.png", width = 1400, height = 900, res = 150)
plot(err_map, main = "RF vs Dynamic World disagreement (1=mismatch)", col = c("white", "black"))
dev.off()

cat("Saved:\n- results/linear_probe/rf_predicted_labels_2024.tif\n- results/linear_probe/rf_disagreement_map_2024.tif\n- figures/linear_probe/rf_prediction_map_2024.png\n- figures/linear_probe/rf_disagreement_map_2024.png\n")

cat("\nDONE\n")
