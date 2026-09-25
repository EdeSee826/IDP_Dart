import cv2
import math
import json
import os
import numpy as np
from ultralytics import YOLO

MODEL_PATH = os.path.join(os.path.dirname(__file__), "best.pt")

PICC_CLASS_NAME = "picc"
MARK_CLASS_NAME = "mark"

model = YOLO(MODEL_PATH)


def distance(p1, p2):
    return math.sqrt((p1[0] - p2[0]) ** 2 + (p1[1] - p2[1]) ** 2)


def polygon_centroid(points):
    points = np.array(points)

    if len(points) == 0:
        return None

    x = points[:, 0]
    y = points[:, 1]

    return (float(np.mean(x)), float(np.mean(y)))


def point_near_mask(point, mask, radius=20):
    x, y = int(point[0]), int(point[1])

    mask_uint8 = (mask > 0).astype(np.uint8)

    kernel = np.ones((radius, radius), np.uint8)
    dilated = cv2.dilate(mask_uint8, kernel, iterations=1)

    h, w = dilated.shape

    if x < 0 or x >= w or y < 0 or y >= h:
        return False

    return dilated[y, x] > 0


def scaled_limits(image_shape):
    """Return image-size-aware post-processing limits."""
    height, width = image_shape[:2]
    image_area = height * width
    min_side = min(height, width)

    return {
        "mark_min_area": max(5, int(image_area * 0.000001)),
        "mark_max_area": max(800, int(image_area * 0.0003)),
        "near_mask_radius": max(25, int(min_side * 0.02)),
        "min_mark_distance": max(20, int(min_side * 0.006)),
        "max_mark_distance": max(150, int(min_side * 0.08)),
    }


def picc_length_from_mask(mask):
    mask_uint8 = (mask > 0).astype(np.uint8) * 255

    contours, _ = cv2.findContours(
        mask_uint8,
        cv2.RETR_EXTERNAL,
        cv2.CHAIN_APPROX_SIMPLE
    )

    if not contours:
        return None

    contour = max(contours, key=cv2.contourArea)

    perimeter = cv2.arcLength(contour, closed=True)

    rect = cv2.minAreaRect(contour)
    width, height = rect[1]
    tube_width = min(width, height)

    length_pixels = (perimeter - math.pi * tube_width) / 2.0

    return length_pixels


def analyze_image(image_path, output_path=None, conf=0.3, save_compare_text=None):
    results = model.predict(
        source=image_path,
        imgsz=960,
        conf=conf,
        verbose=False,
        save=False
    )

    result = results[0]
    image = cv2.imread(image_path)
    if image is None:
        raise ValueError("Image file could not be decoded.")
    limits = scaled_limits(image.shape)

    if result.masks is None or result.boxes is None or len(result.boxes) == 0:
        raise ValueError("No segmentation mask detected.")

    class_ids = result.boxes.cls.cpu().numpy().astype(int)
    class_names = result.names
    masks = result.masks.data.cpu().numpy()

    picc_masks = []
    mark_centroids = []

    for i, cls_id in enumerate(class_ids):
        cls_name = class_names[cls_id]
        mask = masks[i]

        mask_resized = cv2.resize(
            mask,
            (image.shape[1], image.shape[0]),
            interpolation=cv2.INTER_NEAREST
        )

        if cls_name == PICC_CLASS_NAME:
            picc_masks.append(mask_resized)

        elif cls_name == MARK_CLASS_NAME:
            mark_polygon = result.masks.xy[i]
            c = polygon_centroid(mark_polygon)

            if c is not None:
                mark_area = np.sum(mask_resized > 0)
                if limits["mark_min_area"] <= mark_area <= limits["mark_max_area"]:
                    mark_centroids.append(c)

    if len(picc_masks) == 0:
        raise ValueError("No PICC line mask detected.")

    picc_mask = np.zeros_like(picc_masks[0], dtype=np.float32)
    for m in picc_masks:
        picc_mask = np.maximum(picc_mask, m)

    mark_centroids = [
        c for c in mark_centroids
        if point_near_mask(c, picc_mask, radius=limits["near_mask_radius"])
    ]

    if len(mark_centroids) < 2:
        raise ValueError("Less than two valid graduation marks detected.")

    pair_distances = []
    for i in range(len(mark_centroids)):
        for j in range(i + 1, len(mark_centroids)):
            d = distance(mark_centroids[i], mark_centroids[j])
            if limits["min_mark_distance"] <= d <= limits["max_mark_distance"]:
                pair_distances.append((d, mark_centroids[i], mark_centroids[j]))

    if len(pair_distances) == 0:
        raise ValueError("No valid graduation mark pair found.")

    pair_distances.sort(key=lambda x: x[0])

    mark_distance_pixels = pair_distances[0][0]
    centroids = [pair_distances[0][1], pair_distances[0][2]]

    picc_pixels = picc_length_from_mask(picc_mask)
    if picc_pixels is None:
        raise ValueError("Cannot calculate PICC pixel length.")

    external_length_cm = picc_pixels / mark_distance_pixels

    overlay = image.copy()

    picc_binary = (picc_mask > 0).astype(np.uint8)
    overlay[picc_binary > 0] = (
        0.6 * overlay[picc_binary > 0] + 0.4 * np.array([0, 255, 0])
    ).astype(np.uint8)

    for idx, c in enumerate(centroids):
        x, y = int(c[0]), int(c[1])
        cv2.circle(overlay, (x, y), 8, (0, 0, 255), -1)
        cv2.putText(
            overlay,
            f"mark{idx+1}",
            (x + 10, y - 10),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.7,
            (0, 0, 255),
            2
        )

    cv2.putText(
        overlay,
        f"Length: {external_length_cm:.2f} cm",
        (30, 50),
        cv2.FONT_HERSHEY_SIMPLEX,
        1.2,
        (255, 255, 255),
        3
    )

    if save_compare_text is not None:
        y0 = 100
        for line in save_compare_text:
            cv2.putText(
                overlay,
                line,
                (30, y0),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.9,
                (255, 255, 0),
                2
            )
            y0 += 35

    if output_path:
        cv2.imwrite(output_path, overlay)

    return {
        "image_path": image_path,
        "picc_pixels": picc_pixels,
        "mark_distance_pixels": mark_distance_pixels,
        "external_length_cm": external_length_cm,
        "output_path": output_path
    }


def save_baseline(baseline_image_path,
                  baseline_output_image="baseline_result.jpeg",
                  baseline_record_file="baseline_record.json"):
    result = analyze_image(
        baseline_image_path,
        output_path=baseline_output_image
    )

    baseline_record = {
        "baseline_image": baseline_image_path,
        "baseline_length_cm": result["external_length_cm"],
        "baseline_output_image": baseline_output_image
    }

    with open(baseline_record_file, "w") as f:
        json.dump(baseline_record, f, indent=4)

    return result


def check_followup(followup_image_path,
                   baseline_record_file="baseline_record.json",
                   followup_output_image="followup_result.jpeg"):
    if not os.path.exists(baseline_record_file):
        raise FileNotFoundError(
            f"Baseline record file '{baseline_record_file}' not found."
        )

    with open(baseline_record_file, "r") as f:
        baseline_record = json.load(f)

    baseline_length = baseline_record["baseline_length_cm"]
    followup_result = analyze_image(
        followup_image_path,
        output_path=None
    )

    followup_length = followup_result["external_length_cm"]
    difference = followup_length - baseline_length

    if abs(difference) < 0.5:
        status = "Likely stable"
    elif abs(difference) < 1.0:
        status = "Warning: possible small migration"
    else:
        status = "Possible PICC dislodgement detected"

    compare_lines = [
        f"Baseline: {baseline_length:.2f} cm",
        f"Follow-up: {followup_length:.2f} cm",
        f"Difference: {difference:+.2f} cm",
        f"Status: {status}"
    ]

    followup_result = analyze_image(
        followup_image_path,
        output_path=followup_output_image,
        save_compare_text=compare_lines
    )

    return {
        "baseline_length_cm": baseline_length,
        "followup_length_cm": followup_length,
        "difference_cm": difference,
        "status": status
    }


if __name__ == "__main__":
    print("Choose mode:")
    print("1 = Save baseline")
    print("2 = Check follow-up")

    choice = input("Enter choice (1 or 2): ").strip()

    if choice == "1":
        baseline_path = input("Enter baseline image filename: ").strip()
        save_baseline(baseline_path)

    elif choice == "2":
        followup_path = input("Enter follow-up image filename: ").strip()
        check_followup(followup_path)

    else:
        print("Invalid choice.")
