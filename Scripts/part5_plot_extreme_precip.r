library(terra)
library(tidyterra)
library(ggplot2)
library(scales)

tif_path <- "C:/Users/BOUCHRA/Downloads/YRDelta_extremeFreq_p95_2018_2024.tif"
out_png  <- "C:/Users/BOUCHRA/Downloads/extreme_precip_freq_p95_2018_2024.png"

ext_freq <- rast(tif_path)

# Compute min/max safely (ignore NA)
mm <- terra::global(ext_freq, fun = range, na.rm = TRUE)
vmin <- mm[1,1]
vmax <- mm[1,2]
print(mm)

p <- ggplot() +
  geom_spatraster(data = ext_freq) +
  coord_sf() +  # <-- IMPORTANT FIX
  scale_fill_viridis_c(
    name = "Extreme\nfrequency",
    limits = c(0, max(0.08, vmax)),
    labels = percent_format(accuracy = 1)
  ) +
  theme_minimal(base_size = 13) +
  labs(
    title = "Extreme Precipitation Frequency (p95)",
    subtitle = "Yellow River Delta (2018–2024)",
    caption = "Daily precipitation > local 95th percentile\nData: GPM IMERG"
  )

print(p)

ggsave(out_png, p, width = 7, height = 6, dpi = 300)
cat("Saved figure to:", out_png, "\n")
