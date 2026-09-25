import json
import warnings
from pathlib import Path

import joblib
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from sklearn.metrics import (
    accuracy_score,
    classification_report,
    confusion_matrix,
)
from sklearn.preprocessing import StandardScaler
from sklearn.svm import SVC


BASE_DIR = Path(__file__).resolve().parent
DATASET_PATH = Path(
    r"C:\Users\User\Desktop\Vs Codes\IDP_GitHub"
    r"\final_dataset_1sec_4classes_trim500_energy_only.csv"
)
MODEL_PATH = BASE_DIR / "svm_rfe_model (1).pkl"
PREDICTIONS_PATH = BASE_DIR / "global_loso_predictions.csv"
METRICS_PATH = BASE_DIR / "global_loso_confusion_matrix_metrics.json"
PLOT_PATH = BASE_DIR / "global_loso_confusion_matrix.png"


def make_fold_svm(saved_svm):
    return SVC(
        C=saved_svm.C,
        kernel=saved_svm.kernel,
        degree=saved_svm.degree,
        gamma=saved_svm.gamma,
        coef0=saved_svm.coef0,
        shrinking=saved_svm.shrinking,
        probability=False,
        tol=saved_svm.tol,
        cache_size=1000,
        class_weight=saved_svm.class_weight,
        verbose=False,
        max_iter=saved_svm.max_iter,
        decision_function_shape=saved_svm.decision_function_shape,
        break_ties=saved_svm.break_ties,
        random_state=saved_svm.random_state,
    )


def draw_matrix(axis, values, display_labels, title, *, normalized=False):
    image = axis.imshow(
        values,
        cmap="YlGnBu" if normalized else "Blues",
        vmin=0,
        vmax=100 if normalized else None,
        aspect="auto",
    )
    axis.set_xticks(range(len(display_labels)), display_labels, rotation=35, ha="right")
    axis.set_yticks(range(len(display_labels)), display_labels)
    axis.set_xlabel("Predicted Label")
    axis.set_ylabel("Actual Label")
    axis.set_title(title, weight="bold")

    threshold = (values.max() if values.size else 0) * 0.55
    for row in range(values.shape[0]):
        for column in range(values.shape[1]):
            value = values[row, column]
            label = f"{value:.1f}" if normalized else f"{int(value):,}"
            axis.text(
                column,
                row,
                label,
                ha="center",
                va="center",
                color="white" if value > threshold else "#172B4D",
                fontsize=9,
                weight="bold",
            )
    return image


def main():
    print("Loading dataset...", flush=True)
    data = pd.read_csv(DATASET_PATH)
    feature_columns = [str(index) for index in range(60)]
    x = data[feature_columns].to_numpy(dtype=np.float64)
    y = data["label"].astype(str).to_numpy()
    subjects = data["subject"].astype(str).to_numpy()

    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        saved_pipeline = joblib.load(MODEL_PATH)

    saved_rfe = saved_pipeline.named_steps["rfe"]
    saved_svm = saved_pipeline.named_steps["svm"]
    selected_indices = np.flatnonzero(saved_rfe.support_)
    labels = saved_svm.classes_.tolist()

    global_actual = []
    global_predicted = []
    global_subjects = []
    per_subject = {}

    unique_subjects = data["subject"].astype(str).drop_duplicates().tolist()
    for fold_number, held_out_subject in enumerate(unique_subjects, start=1):
        print(
            f"[{fold_number}/{len(unique_subjects)}] Held-out subject: "
            f"{held_out_subject}",
            flush=True,
        )
        test_mask = subjects == held_out_subject
        train_mask = ~test_mask

        scaler = StandardScaler()
        x_train_scaled = scaler.fit_transform(x[train_mask])
        x_test_scaled = scaler.transform(x[test_mask])

        x_train_selected = x_train_scaled[:, selected_indices]
        x_test_selected = x_test_scaled[:, selected_indices]

        fold_model = make_fold_svm(saved_svm)
        fold_model.fit(x_train_selected, y[train_mask])
        fold_predictions = fold_model.predict(x_test_selected)
        fold_actual = y[test_mask]

        global_actual.extend(fold_actual.tolist())
        global_predicted.extend(fold_predictions.tolist())
        global_subjects.extend([held_out_subject] * len(fold_actual))

        per_subject[held_out_subject] = {
            "test_samples": int(len(fold_actual)),
            "accuracy": float(accuracy_score(fold_actual, fold_predictions)),
        }
        print(
            f"  Samples: {len(fold_actual):,} | "
            f"Accuracy: {per_subject[held_out_subject]['accuracy'] * 100:.2f}%",
            flush=True,
        )

    # The global matrix is generated once from the pooled discrete labels.
    matrix = confusion_matrix(global_actual, global_predicted, labels=labels)
    normalized = confusion_matrix(
        global_actual,
        global_predicted,
        labels=labels,
        normalize="true",
    )
    global_accuracy = accuracy_score(global_actual, global_predicted)
    report = classification_report(
        global_actual,
        global_predicted,
        labels=labels,
        output_dict=True,
        zero_division=0,
    )

    prediction_frame = pd.DataFrame(
        {
            "subject": global_subjects,
            "actual": global_actual,
            "predicted": global_predicted,
        }
    )
    prediction_frame.to_csv(PREDICTIONS_PATH, index=False)

    metrics = {
        "method": (
            "Leave-one-subject-out evaluation. Discrete actual and predicted "
            "labels from every held-out subject fold were appended to global "
            "lists. The final confusion matrix was calculated once from those "
            "pooled lists; fold confusion matrices were not summed or averaged."
        ),
        "feature_selection_note": (
            "The saved model's fixed 20-feature RFE support mask was reused. "
            "StandardScaler and the SVM were refitted using training subjects "
            "only within every fold."
        ),
        "dataset": str(DATASET_PATH),
        "total_pooled_predictions": len(global_actual),
        "labels": labels,
        "selected_feature_indices_zero_based": selected_indices.tolist(),
        "svm_parameters": saved_svm.get_params(),
        "global_accuracy": float(global_accuracy),
        "global_confusion_matrix": matrix.tolist(),
        "global_normalized_confusion_matrix": normalized.tolist(),
        "classification_report": report,
        "per_subject": per_subject,
    }
    METRICS_PATH.write_text(json.dumps(metrics, indent=2), encoding="utf-8")

    display_labels = [label.replace("_", " ").title() for label in labels]
    figure, axes = plt.subplots(1, 2, figsize=(17, 7), constrained_layout=True)
    draw_matrix(
        axes[0],
        matrix,
        display_labels,
        "Global LOSO Confusion Matrix (Counts)",
    )
    normalized_image = draw_matrix(
        axes[1],
        normalized * 100,
        display_labels,
        "Global LOSO Confusion Matrix (Row-Normalized %)",
        normalized=True,
    )
    colorbar = figure.colorbar(normalized_image, ax=axes[1], shrink=0.82)
    colorbar.set_label("Row percentage (%)")
    figure.suptitle(
        f"Pooled Held-Out Subject Predictions | Accuracy: {global_accuracy * 100:.2f}% "
        f"| n={len(global_actual):,}",
        fontsize=16,
        weight="bold",
    )
    figure.savefig(PLOT_PATH, dpi=220, facecolor="white")
    plt.close(figure)

    print(f"Global pooled accuracy: {global_accuracy * 100:.2f}%", flush=True)
    print(f"Saved predictions: {PREDICTIONS_PATH}", flush=True)
    print(f"Saved metrics: {METRICS_PATH}", flush=True)
    print(f"Saved plot: {PLOT_PATH}", flush=True)


if __name__ == "__main__":
    main()
