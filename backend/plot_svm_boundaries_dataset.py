import json
import warnings
from pathlib import Path

import joblib
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from matplotlib.colors import ListedColormap
from sklearn.decomposition import PCA
from sklearn.metrics import accuracy_score, confusion_matrix


BASE_DIR = Path(__file__).resolve().parent
DATASET_PATH = Path(r"C:\Users\User\Desktop\Vs Codes\IDP_GitHub\final_dataset_1sec_4classes_trim500_energy_only.csv")
MODEL_PATH = BASE_DIR / "svm_rfe_model (1).pkl"
SCALER_PATH = BASE_DIR / "scaler (1).pkl"
PLOT_PATH = BASE_DIR / "svm_class_boundaries_dataset_pca.png"
METRICS_PATH = BASE_DIR / "svm_class_boundaries_dataset_metrics.json"
RANDOM_SEED = 42
POINTS_PER_CLASS = 1800

CLASS_COLORS = ["#D1495B", "#7B2CBF", "#F28E2B", "#2A9D8F", "#277DA1", "#59A14F"]


def balanced_indices(labels, classes, points_per_class):
    rng = np.random.default_rng(RANDOM_SEED)
    selected = []
    for class_name in classes:
        candidates = np.flatnonzero(labels == class_name)
        selected.extend(rng.choice(candidates, size=min(points_per_class, len(candidates)), replace=False))
    return np.array(selected)


def main():
    data = pd.read_csv(DATASET_PATH)
    feature_columns = [str(index) for index in range(60)]
    x = data[feature_columns].to_numpy(dtype=float)
    y = data["label"].astype(str).to_numpy()

    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        scaler = joblib.load(SCALER_PATH)
        pipeline = joblib.load(MODEL_PATH)

    rfe = pipeline.named_steps["rfe"]
    svm = pipeline.named_steps["svm"]
    classes = svm.classes_

    x_scaled = scaler.transform(x)
    x_selected = rfe.transform(x_scaled)
    predictions = svm.predict(x_selected)
    accuracy = accuracy_score(y, predictions)
    matrix = confusion_matrix(y, predictions, labels=classes)

    pca = PCA(n_components=2, random_state=RANDOM_SEED)
    x_2d = pca.fit_transform(x_selected)

    x_low, x_high = np.percentile(x_2d[:, 0], [0.5, 99.5])
    y_low, y_high = np.percentile(x_2d[:, 1], [0.5, 99.5])
    x_padding = (x_high - x_low) * 0.08
    y_padding = (y_high - y_low) * 0.08
    x_min, x_max = x_low - x_padding, x_high + x_padding
    y_min, y_max = y_low - y_padding, y_high + y_padding

    xx, yy = np.meshgrid(np.linspace(x_min, x_max, 450), np.linspace(y_min, y_max, 450))
    grid_selected = pca.inverse_transform(np.c_[xx.ravel(), yy.ravel()])
    grid_predictions = svm.predict(grid_selected)
    class_to_index = {name: index for index, name in enumerate(classes)}
    zz = np.array([class_to_index[name] for name in grid_predictions]).reshape(xx.shape)

    figure, axis = plt.subplots(figsize=(12, 8.5))
    figure.subplots_adjust(left=0.09, right=0.98, top=0.89, bottom=0.17)
    cmap = ListedColormap(CLASS_COLORS[: len(classes)])
    axis.contourf(
        xx,
        yy,
        zz,
        levels=np.arange(len(classes) + 1) - 0.5,
        cmap=cmap,
        alpha=0.22,
        antialiased=True,
    )
    axis.contour(
        xx,
        yy,
        zz,
        levels=np.arange(len(classes) - 1) + 0.5,
        colors="#263238",
        linewidths=0.75,
        alpha=0.55,
    )

    plot_indices = balanced_indices(y, classes, POINTS_PER_CLASS)
    for class_index, class_name in enumerate(classes):
        class_indices = plot_indices[y[plot_indices] == class_name]
        axis.scatter(
            x_2d[class_indices, 0],
            x_2d[class_indices, 1],
            s=10,
            color=CLASS_COLORS[class_index],
            edgecolor="white",
            linewidth=0.15,
            alpha=0.48,
            label=f"{class_name.replace('_', ' ').title()} (n={np.sum(y == class_name):,})",
        )

    axis.set_xlim(x_min, x_max)
    axis.set_ylim(y_min, y_max)
    axis.set_title(f"Dataset-Based SVM Class-Boundary Projection | Accuracy: {accuracy * 100:.2f}%", fontsize=16, weight="bold", pad=14)
    axis.set_xlabel(f"Dataset PCA component 1 ({pca.explained_variance_ratio_[0] * 100:.1f}% variance)")
    axis.set_ylabel(f"Dataset PCA component 2 ({pca.explained_variance_ratio_[1] * 100:.1f}% variance)")
    axis.grid(color="#CFD8DC", linewidth=0.5, alpha=0.7)
    axis.legend(loc="upper right", frameon=True, fontsize=8.5)
    figure.text(
        0.5,
        0.04,
        "Points are labelled samples from the supplied dataset after saved scaling and RFE selection. "
        "Backgrounds are predictions from a 2D PCA slice of the saved 20-feature RBF SVM.",
        ha="center",
        fontsize=9,
        color="#455A64",
    )
    figure.savefig(PLOT_PATH, dpi=220, facecolor="white")
    plt.close(figure)

    per_class = {}
    for index, class_name in enumerate(classes):
        total = int(matrix[index].sum())
        correct = int(matrix[index, index])
        per_class[class_name] = {
            "samples": total,
            "correct": correct,
            "accuracy": correct / total if total else None,
            "predicted_counts": {
                predicted_class: int(matrix[index, predicted_index])
                for predicted_index, predicted_class in enumerate(classes)
            },
        }

    metrics = {
        "dataset": str(DATASET_PATH),
        "samples": int(len(data)),
        "subjects": sorted(data["subject"].astype(str).unique().tolist()),
        "classes": classes.tolist(),
        "overall_accuracy": float(accuracy),
        "pca_explained_variance_ratio": pca.explained_variance_ratio_.tolist(),
        "confusion_matrix_labels": classes.tolist(),
        "confusion_matrix": matrix.tolist(),
        "per_class_results": per_class,
        "interpretation": (
            "This measures the saved model against the supplied dataset. If this dataset was used for training, "
            "the accuracy is training-set performance and does not estimate performance on unseen subjects."
        ),
    }
    METRICS_PATH.write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    print(f"Samples: {len(data):,}")
    print(f"Accuracy: {accuracy * 100:.2f}%")
    print(f"Saved plot: {PLOT_PATH}")
    print(f"Saved metrics: {METRICS_PATH}")


if __name__ == "__main__":
    main()
