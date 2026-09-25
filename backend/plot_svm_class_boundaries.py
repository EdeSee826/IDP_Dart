import json
import warnings
from pathlib import Path

import joblib
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.colors import ListedColormap
from sklearn.decomposition import PCA


BASE_DIR = Path(__file__).resolve().parent
MODEL_PATH = BASE_DIR / "svm_rfe_model (1).pkl"
OUTPUT_PATH = BASE_DIR / "svm_class_boundaries_pca.png"
METADATA_PATH = BASE_DIR / "svm_class_boundaries_pca.json"

CLASS_COLORS = [
    "#D1495B",
    "#7B2CBF",
    "#F28E2B",
    "#2A9D8F",
    "#277DA1",
    "#59A14F",
]


def support_vector_labels(svm):
    return np.concatenate(
        [np.full(count, class_index) for class_index, count in enumerate(svm.n_support_)]
    )


def main():
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        pipeline = joblib.load(MODEL_PATH)

    rfe = pipeline.named_steps["rfe"]
    svm = pipeline.named_steps["svm"]
    support_vectors = svm.support_vectors_
    labels = support_vector_labels(svm)

    pca = PCA(n_components=2)
    support_2d = pca.fit_transform(support_vectors)

    # Focus on the central 99% so a small number of extreme support vectors do
    # not compress the clinically relevant class-boundary structure.
    x_low, x_high = np.percentile(support_2d[:, 0], [0.5, 99.5])
    y_low, y_high = np.percentile(support_2d[:, 1], [0.5, 99.5])
    x_padding = (x_high - x_low) * 0.08
    y_padding = (y_high - y_low) * 0.08
    x_min, x_max = x_low - x_padding, x_high + x_padding
    y_min, y_max = y_low - y_padding, y_high + y_padding
    xx, yy = np.meshgrid(
        np.linspace(x_min, x_max, 500),
        np.linspace(y_min, y_max, 500),
    )

    # Inverse PCA maps this grid into a 20D slice through the mean of the
    # selected-feature support-vector distribution. Predictions therefore come
    # from the fitted SVM itself, while the figure remains viewable in 2D.
    grid_20d = pca.inverse_transform(np.c_[xx.ravel(), yy.ravel()])
    prediction_labels = svm.predict(grid_20d)
    class_to_index = {name: index for index, name in enumerate(svm.classes_)}
    zz = np.array([class_to_index[name] for name in prediction_labels]).reshape(xx.shape)

    figure, axis = plt.subplots(figsize=(12, 8.5))
    figure.subplots_adjust(left=0.09, right=0.98, top=0.90, bottom=0.16)
    cmap = ListedColormap(CLASS_COLORS[: len(svm.classes_)])
    axis.contourf(
        xx,
        yy,
        zz,
        levels=np.arange(len(svm.classes_) + 1) - 0.5,
        cmap=cmap,
        alpha=0.22,
        antialiased=True,
    )
    axis.contour(
        xx,
        yy,
        zz,
        levels=np.arange(len(svm.classes_) - 1) + 0.5,
        colors="#263238",
        linewidths=0.75,
        alpha=0.55,
    )

    for class_index, class_name in enumerate(svm.classes_):
        mask = labels == class_index
        axis.scatter(
            support_2d[mask, 0],
            support_2d[mask, 1],
            s=25,
            color=CLASS_COLORS[class_index],
            edgecolor="white",
            linewidth=0.35,
            alpha=0.82,
            label=f"{class_name.replace('_', ' ').title()} ({mask.sum()} SVs)",
        )

    axis.set_title("SVM Class-Boundary Projection", fontsize=18, weight="bold", pad=14)
    axis.set_xlabel(f"Support-vector PCA component 1 ({pca.explained_variance_ratio_[0] * 100:.1f}% variance)")
    axis.set_ylabel(f"Support-vector PCA component 2 ({pca.explained_variance_ratio_[1] * 100:.1f}% variance)")
    axis.set_xlim(x_min, x_max)
    axis.set_ylim(y_min, y_max)
    axis.grid(color="#CFD8DC", linewidth=0.5, alpha=0.7)
    axis.legend(loc="upper right", frameon=True, fontsize=9)
    figure.text(
        0.5,
        0.045,
        "Actual RBF-SVM predictions on a 2D PCA slice; points are stored support vectors. "
        "Axes show the central 99% of the support-vector distribution.",
        ha="center",
        fontsize=9,
        color="#455A64",
    )
    figure.savefig(OUTPUT_PATH, dpi=220, facecolor="white")
    plt.close(figure)

    selected_indices = np.flatnonzero(rfe.support_).tolist()
    metadata = {
        "model": "RFE followed by multiclass RBF SVC",
        "original_feature_count": int(pipeline.n_features_in_),
        "selected_feature_count": int(rfe.n_features_),
        "selected_feature_indices_zero_based": selected_indices,
        "classes": svm.classes_.tolist(),
        "support_vectors_per_class": {
            class_name: int(count) for class_name, count in zip(svm.classes_, svm.n_support_)
        },
        "total_support_vectors": int(len(support_vectors)),
        "pca_explained_variance_ratio": pca.explained_variance_ratio_.tolist(),
        "plot_interpretation": (
            "Actual SVM predictions evaluated on a 2D PCA slice through the mean of the "
            "20-dimensional selected-feature support-vector distribution."
        ),
    }
    METADATA_PATH.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print(f"Saved plot: {OUTPUT_PATH}")
    print(f"Saved metadata: {METADATA_PATH}")


if __name__ == "__main__":
    main()
