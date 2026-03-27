# ---- Extreme precipitation × land-change exposure (DELTA) ----
source("Scripts/config.R")

suppressPackageStartupMessages({
  library(tidyterra)
  library(ggplot2)
  library(dplyr)
  library(scales)
})

# Paths
ext_path <- "figures/YRDelta_extremeFreq_p95_2018_2024.tif"
mad3857_path <- "results/embeddings_delta/mad_2018_2024.tif"

# Outputs
mad_reproj_path <- "results/change_detection/mad_delta_reprojected_to_ext.tif"
hot_path <- "results/change_detection/mad_highchange_delta_95_on_ext.tif"
overlay_png <- "figures/overlay_extremeFreq_p95__MADhotspots.png"
box_png <- "figures/boxplot_extremeFreq_p95__MADhotspots.png"

# Load
ext <- rast(ext_path)
mad3857 <- rast(mad3857_path)

# Reproject MAD to precip grid
mad_on_ext <- project(mad3857, ext, method = "bilinear")
writeRaster(mad_on_ext, mad_reproj_path, overwrite = TRUE)

# Hotspot mask (p95)
thr <- global(mad_on_ext, "quantile", probs = 0.95, na.rm = TRUE)[1,1]
mad_hot <- mad_on_ext > thr
writeRaster(mad_hot, hot_path, overwrite = TRUE)

cat("MAD p95 threshold:", thr, "\n")
cat("Hotspot cells:", global(mad_hot == 1, "sum", na.rm = TRUE)[1,1], "\n")

# Exposure stats
df <- as.data.frame(c(ext, mad_hot), na.rm = TRUE)
colnames(df) <- c("extreme_freq", "hotspot")
df$group <- ifelse(df$hotspot == 1, "High-change (MAD p95)", "Other")

summary_tbl <- df %>%
  group_by(group) %>%
  summarise(mean_extreme = mean(extreme_freq),
            median_extreme = median(extreme_freq),
            n = n(),
            .groups = "drop")

print(summary_tbl)

# Overlay map
hot_mask <- mad_hot
values(hot_mask) <- ifelse(values(mad_hot) == 1, 1, NA)

p_overlay <- ggplot() +
  geom_spatraster(data = ext) +
  coord_sf() +
  scale_fill_viridis_c(name = "Extreme\nfrequency",
                       labels = percent_format(accuracy = 1)) +
  geom_spatraster(data = hot_mask, alpha = 0.35) +
  theme_minimal(base_size = 13) +
  labs(
    title = "Extreme Precipitation Frequency (p95) + Land-Change Hotspots",
    subtitle = "Hotspots = embedding MAD > p95 (2018–2024)",
    caption = "Extreme precipitation: daily precip > local 95th percentile (GPM IMERG)"
  )

ggsave(overlay_png, p_overlay, width = 7.5, height = 6.5, dpi = 300)

# Boxplot
p_box <- ggplot(df, aes(x = group, y = extreme_freq)) +
  geom_boxplot(outlier.size = 0.5) +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  theme_minimal(base_size = 13) +
  labs(
    title = "Extreme Precipitation Exposure vs Land-Change Hotspots",
    subtitle = "Inside vs outside MAD hotspots",
    x = NULL,
    y = "Extreme precipitation frequency (p95)"
  )

ggsave(box_png, p_box, width = 7.5, height = 5.5, dpi = 300)

cat("Saved:", overlay_png, "\n")
cat("Saved:", box_png, "\n")
