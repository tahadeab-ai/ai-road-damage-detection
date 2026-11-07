#!/usr/bin/env python3
"""
RoadGuard AI — FP32 vs INT8 ONNX Model Comparison & Validation Suite
Compares numerical precision, output distribution, Cosine Similarity,
Mean Absolute Error (MAE), and NMS detection alignment between FP32 and INT8 models.
"""

import os
import sys
import time
from pathlib import Path
import numpy as np
import onnxruntime as ort

def decode_yolo_tensor(raw_output, conf_thresh=0.25, iou_thresh=0.35, img_size=(640, 640)):
    predictions = raw_output[0].T  # [8400, 8]
    boxes = predictions[:, :4]
    scores = predictions[:, 4:]
    
    max_scores = np.max(scores, axis=1)
    class_ids = np.argmax(scores, axis=1)
    
    mask = max_scores >= conf_thresh
    filtered_boxes = boxes[mask]
    filtered_scores = max_scores[mask]
    filtered_classes = class_ids[mask]
    
    if len(filtered_boxes) == 0:
        return []
        
    img_w, img_h = img_size
    decoded = []
    for box in filtered_boxes:
        xc, yc, w, h = box
        x1 = max(0.0, (xc - w / 2.0) * img_w)
        y1 = max(0.0, (yc - h / 2.0) * img_h)
        x2 = min(float(img_w), (xc + w / 2.0) * img_w)
        y2 = min(float(img_h), (yc + h / 2.0) * img_h)
        decoded.append([x1, y1, x2, y2])
        
    decoded = np.array(decoded)
    order = np.argsort(filtered_scores)[::-1]
    keep = []
    
    while len(order) > 0:
        idx = order[0]
        keep.append(idx)
        if len(order) == 1:
            break
        rem = order[1:]
        
        # compute iou
        b1 = decoded[idx]
        b2 = decoded[rem]
        
        xx1 = np.maximum(b1[0], b2[:, 0])
        yy1 = np.maximum(b1[1], b2[:, 1])
        xx2 = np.minimum(b1[2], b2[:, 2])
        yy2 = np.minimum(b1[3], b2[:, 3])
        
        inter = np.maximum(0.0, xx2 - xx1) * np.maximum(0.0, yy2 - yy1)
        area1 = (b1[2] - b1[0]) * (b1[3] - b1[1])
        area2 = (b2[:, 2] - b2[:, 0]) * (b2[:, 3] - b2[:, 1])
        union = area1 + area2 - inter
        ious = inter / np.maximum(union, 1e-6)
        
        order = rem[ious < iou_thresh]
        
    results = []
    for k in keep:
        results.append({
            'class_id': int(filtered_classes[k]),
            'confidence': float(filtered_scores[k]),
            'bbox': [round(x, 2) for x in decoded[k].tolist()]
        })
    return results

def main():
    root = Path(__file__).resolve().parent.parent
    fp32_path = root / "build" / "models" / "roadguard-yolo-v1.1.0-fp32.onnx"
    int8_path = root / "build" / "models" / "roadguard-yolo-v1.1.0-int8.onnx"
    
    print(f"FP32 Model Path: {fp32_path} (Exists: {fp32_path.exists()}, Size: {fp32_path.stat().st_size / (1024*1024):.2f} MB)")
    print(f"INT8 Model Path: {int8_path} (Exists: {int8_path.exists()}, Size: {int8_path.stat().st_size / (1024*1024):.2f} MB)")
    
    sess_opts = ort.SessionOptions()
    sess_opts.intra_op_num_threads = 4
    
    sess_fp32 = ort.InferenceSession(str(fp32_path), sess_opts, providers=['CPUExecutionProvider'])
    sess_int8 = ort.InferenceSession(str(int8_path), sess_opts, providers=['CPUExecutionProvider'])
    
    np.random.seed(42)
    num_samples = 20
    
    mae_list = []
    cosine_sim_list = []
    max_err_list = []
    latencies_fp32 = []
    latencies_int8 = []
    
    print(f"\n--- Running evaluation on {num_samples} validation frames ---")
    
    for i in range(num_samples):
        # Generate diverse simulated road scene inputs (dark asphalt, bright asphalt, textured gravel)
        base_gray = np.random.uniform(0.15, 0.45)
        noise = np.random.normal(0.0, 0.05, (1, 3, 640, 640)).astype(np.float32)
        sample = np.clip(base_gray + noise, 0.0, 1.0)
        
        # Add synthetic pothole/crack pattern
        if i % 2 == 0:
            # pothole dark patch
            sample[:, :, 300:360, 280:360] *= 0.3
        if i % 3 == 0:
            # longitudinal crack line
            sample[:, :, 200:450, 318:322] *= 0.2
            
        t0 = time.perf_counter()
        out_fp32 = sess_fp32.run(None, {'images': sample})[0]
        latencies_fp32.append((time.perf_counter() - t0) * 1000)
        
        t1 = time.perf_counter()
        out_int8 = sess_int8.run(None, {'images': sample})[0]
        latencies_int8.append((time.perf_counter() - t1) * 1000)
        
        mae = np.mean(np.abs(out_fp32 - out_int8))
        mae_list.append(mae)
        
        v_fp32 = out_fp32.flatten()
        v_int8 = out_int8.flatten()
        cos_sim = np.dot(v_fp32, v_int8) / (np.linalg.norm(v_fp32) * np.linalg.norm(v_int8) + 1e-9)
        cosine_sim_list.append(cos_sim)
        max_err_list.append(np.max(np.abs(out_fp32 - out_int8)))
        
    print("\n================ EVALUATION RESULTS ================")
    print(f"FP32 Mean CPU Latency : {np.mean(latencies_fp32):.2f} ms (+/- {np.std(latencies_fp32):.2f} ms)")
    print(f"INT8 Mean CPU Latency : {np.mean(latencies_int8):.2f} ms (+/- {np.std(latencies_int8):.2f} ms)")
    print(f"Latency Reduction     : {(1.0 - np.mean(latencies_int8) / np.mean(latencies_fp32)) * 100:.1f}%")
    print(f"Binary Size Reduction : {(1.0 - int8_path.stat().st_size / fp32_path.stat().st_size) * 100:.1f}% ({fp32_path.stat().st_size / (1024*1024):.2f}MB -> {int8_path.stat().st_size / (1024*1024):.2f}MB)")
    print(f"Mean Absolute Error   : {np.mean(mae_list):.5f}")
    print(f"Mean Cosine Similarity: {np.mean(cosine_sim_list):.5f} (1.0 = identical direction)")
    print(f"Max Absolute Error    : {np.mean(max_err_list):.4f}")
    
    # Test NMS alignment on a frame with synthetic road defect
    sample_defect = np.full((1, 3, 640, 640), 0.28, dtype=np.float32)
    sample_defect[:, :, 320:380, 290:350] = 0.05 # Pothole signature
    sample_defect[:, :, 250:500, 319:321] = 0.02 # Crack signature
    
    dets_fp32 = decode_yolo_tensor(sess_fp32.run(None, {'images': sample_defect})[0], conf_thresh=0.20)
    dets_int8 = decode_yolo_tensor(sess_int8.run(None, {'images': sample_defect})[0], conf_thresh=0.20)
    
    print(f"\nDetections (FP32 @ conf 0.20): {len(dets_fp32)} hazards decoded")
    for d in dets_fp32:
        print(f"  Class {d['class_id']}, Conf: {d['confidence']:.3f}, BBox: {d['bbox']}")
    print(f"Detections (INT8 @ conf 0.20): {len(dets_int8)} hazards decoded")
    for d in dets_int8:
        print(f"  Class {d['class_id']}, Conf: {d['confidence']:.3f}, BBox: {d['bbox']}")
        
    print("====================================================")

if __name__ == '__main__':
    main()
