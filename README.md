# Yellow River Delta: Land Cover Change Detection (2018–2024)

> Satellite embedding-based change analysis of the Yellow River Delta (Shandong Province, China)
> using Google Earth Engine, Google Satellite Embeddings V1, and Dynamic World land cover data.

---

## Study Area

**Yellow River Delta** — Dongying, Shandong Province, China
Bounding box: `118.35–119.35°E`, `37.35–38.15°N`

One of the most dynamically evolving river deltas in the world, the Yellow River Delta experiences rapid land cover transitions driven by sediment deposition, wetland expansion/retreat, agricultural conversion, and infrastructure development.

---

## Methodology Overview

The analysis follows a six-part pipeline, all implemented in R using Google Earth Engine (GEE) as the remote sensing data source.

```
Part 1  →  Export Dynamic World land cover (2018 & 2024)
Part 2  →  Change detection: MAD + Cosine similarity on embeddings
Part 3A →  Export 64-band satellite embeddings from GEE
Part 3B →  Unsupervised K-means clustering (K = 3, 5, 10)
Part 4  →  Supervised classification: Linear Probe + Random Forest
Part 5  →  Extreme precipitation frequency maps
Part 6  →  Overlay: precipitation extremes vs. change hotspots
```

### Data Sources

| Dataset | Resolution | Source |
|---|---|---|
| Google Dynamic World V1 | 10 m | Google Earth Engine |
| Google Satellite Embeddings V1 | 10 m, 64 bands | Google Earth Engine |
| Extreme precipitation (P95) | — | ERA5 / GEE |

### Change Detection Metrics

Two complementary metrics are computed pixel-wise across the 64-dimensional embedding space:

- **MAD (Mean Absolute Difference)** — L1 distance, sensitive to magnitude of change
- **Cosine Change** (1 − cosine similarity) — captures directional shift in spectral signature, scale-invariant

### Machine Learning Classification

Using the 2024 embeddings as input features and Dynamic World labels as targets:

| Model | Approach |
|---|---|
| Linear Probe (Ridge Multinomial) | Fast baseline, interpretable weights |
| Random Forest | Non-linear classifier (300 trees, mtry = √64) |

Both models are evaluated on an 80/20 train/test split with per-class F1 scores, confusion matrices, and spatial prediction maps.

---

## Key Results

### Land Cover Change (2018 → 2024)

| Figure | Description |
|---|---|
| ![MAD map](figures/embeddings_delta/mad_2018_2024_p99.png) | MAD change map (clipped at P99) |
| ![Cosine change](figures/embeddings_delta/cosine_change_2018_2024_p99.png) | Cosine change map (clipped at P99) |
| ![DW 2018](figures/DW_mode_2018.png) | Dynamic World land cover 2018 |
| ![DW 2024](figures/DW_mode_2024.png) | Dynamic World land cover 2024 |

### Unsupervised Clustering (2024 Embeddings)

| K | Figure |
|---|---|
| K = 3 | ![K3](figures/clusters_K3.png) |
| K = 5 | ![K5](figures/embeddings_delta/clusters_2024_K5.png) |
| K = 10 | ![K10](figures/embeddings_delta/clusters_2024_K10.png) |

### Classification Performance

| Figure | Description |
|---|---|
| ![RF prediction](figures/linear_probe/rf_prediction_map_2024.png) | Random Forest land cover prediction (2024) |
| ![Confusion matrix](figures/linear_probe/confusion_matrix_rf_normalized.png) | Normalized confusion matrix |
| ![Per-class F1](figures/linear_probe/per_class_f1_rf.png) | Per-class F1 scores (RF) |
| ![Model comparison](figures/linear_probe/linear_probe_vs_rf.png) | Linear Probe vs. Random Forest |

### Precipitation–Change Overlay

| Figure | Description |
|---|---|
| ![Precip overlay](figures/overlay_extremeFreq_p95__MADhotspots.png) | Extreme precipitation vs. MAD hotspots |
| ![Precip boxplot](figures/boxplot_extremeFreq_p95__MADhotspots.png) | Precipitation frequency at change hotspots |

---

## Repository Structure

```
land_cover_gis/
├── Scripts/
│   ├── part1_export_DW_delta.r              # Dynamic World export from GEE
│   ├── part2_change_detection_clean.r       # MAD + cosine change detection
│   ├── part3_embeddings_export_delta_ee.r   # Export embeddings from GEE
│   ├── part3_embeddings_analysis_delta.r    # K-means clustering
│   ├── part4_linear_probe_baseline_delta.r  # RF + linear probe classification
│   ├── part5_plot_extreme_precip.r          # Precipitation frequency maps
│   ├── part6_extreme_precip_vs_change_hotspots.r  # Precip–change overlay
│   ├── QA_full_project.r                    # Quality assurance checks
│   └── map_viewer_gee.R                     # Interactive map viewer
├── figures/                                 # All output visualizations (PNG)
│   ├── embeddings_delta/                    # Delta-specific change maps
│   └── linear_probe/                        # Classification maps
├── results/
│   ├── change_detection/                    # MAD, cosine, DW transition stats
│   ├── embeddings_delta/                    # K-means cluster rasters
│   └── linear_probe/                        # Model metrics and CSVs
│       ├── metrics_linear_vs_rf.csv
│       ├── per_class_metrics_rf.csv
│       └── confusion_matrix_rf_normalized.csv
└── data/                                    # Not tracked — see Data Access below
```

---

## Data Access

The raw and processed raster data (~22 GB total) are not tracked in this repository due to size constraints.

To reproduce this analysis from scratch:

1. Create a Google Earth Engine project and authenticate
2. Run `Scripts/part1_export_DW_delta.r` to export Dynamic World data to Google Drive
3. Run `Scripts/part3_embeddings_export_delta_ee.r` to export 64-band satellite embeddings
4. Download outputs from Google Drive into `data/`

Alternatively, key output rasters are available on request.

---

## Requirements

### R Packages

```r
install.packages(c(
  "terra",        # raster processing
  "ggplot2",      # visualization
  "tidyterra",    # ggplot2 + terra integration
  "dplyr",        # data manipulation
  "tidyr",        # data reshaping
  "glmnet",       # linear probe (ridge multinomial)
  "ranger",       # random forest
  "reticulate"    # Python/Earth Engine bridge
))
```

### Python (for GEE access)

```bash
pip install earthengine-api
earthengine authenticate
```

Set the Python path in scripts that use `reticulate`:

```r
Sys.setenv(RETICULATE_PYTHON = "/path/to/your/python")
```

### Google Earth Engine

- Project ID: create your own at [code.earthengine.google.com](https://code.earthengine.google.com)
- Replace `"ee-yellow-river-481216"` with your project ID in all scripts

---

## Running the Analysis

Run scripts in order from the `Scripts/` directory. Each script sets `setwd()` to the project root, so open the `.code-workspace` file in VSCode or set your working directory manually:

```r
setwd("/path/to/land_cover_gis")
```

Then run:

```
1. part1_export_DW_delta.r
2. part2_change_detection_clean.r
3. part3_embeddings_export_delta_ee.r  (exports to GEE → download to data/)
3. part3_embeddings_analysis_delta.r
4. part4_linear_probe_baseline_delta.r
5. part5_plot_extreme_precip.r
6. part6_extreme_precip_vs_change_hotspots.r
```

---

## Region of Interest Coordinates

| ROI | Purpose | Bounding Box |
|---|---|---|
| Primary | Dynamic World export | 118.35–119.35°E, 37.35–38.15°N |
| Secondary | Change detection | 118.55–119.45°E, 37.35–38.10°N |
| Small test | Embeddings smoke test | 118.72–118.88°E, 37.73–37.87°N |

---

## Author

**Bouchra Daddaoui**
Research work on remote sensing and land cover change detection.

---

## Acknowledgements

- [Google Dynamic World](https://dynamicworld.app/) — near-real-time global land cover
- [Google Earth Engine](https://earthengine.google.com/) — cloud-based geospatial analysis
- [Google Satellite Embeddings V1](https://developers.google.com/earth-engine/datasets/catalog/GOOGLE_SATELLITE_EMBEDDING_V1) — foundation model embeddings for satellite imagery
