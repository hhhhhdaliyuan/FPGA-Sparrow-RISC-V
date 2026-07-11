import os
import numpy as np
import cv2

# ====== 1. Load classes ======
DATA_DIR = r'D:\python+pycharm\Project\simple-car-plate-recognition-master\dataset'
classes = sorted([d for d in os.listdir(DATA_DIR)
                  if os.path.isdir(os.path.join(DATA_DIR, d)) and not d.startswith('.')])
print(f'类别数: {len(classes)}')
print(f'类别: {classes}')
print()

# ====== 2. Load saved int16 weights ======
w0 = np.load(r'D:\python+pycharm\Project\train_CNN\layer0_w.npy').astype(np.int32)  # 512x256
b0 = np.load(r'D:\python+pycharm\Project\train_CNN\layer0_b.npy').astype(np.int32)  # 256
w1 = np.load(r'D:\python+pycharm\Project\train_CNN\layer1_w.npy').astype(np.int32)  # 256x128
b1 = np.load(r'D:\python+pycharm\Project\train_CNN\layer1_b.npy').astype(np.int32)  # 128
w2 = np.load(r'D:\python+pycharm\Project\train_CNN\layer2_w.npy').astype(np.int32)  # 128x65
b2 = np.load(r'D:\python+pycharm\Project\train_CNN\layer2_b.npy').astype(np.int32)  # 65

# ====== 3. Load and preprocess char_0.bmp ======
img = cv2.imread(r'D:\MATLAB\PIC\single_word_debug\char_0.bmp', cv2.IMREAD_GRAYSCALE)
print(f'原始图像: {img.shape}')

# Resize to 16x32 (w=16, h=32) — same as training
img_resized = cv2.resize(img, (16, 32))
print(f'缩放后: {img_resized.shape}')

# Show resized image as ASCII
print('缩放后图像(16x32):')
for r in range(32):
    row = img_resized[r, :]
    line = ''.join(['#' if p < 128 else ' ' for p in row])
    print(f'  {line}')

# ====== 4. Int16 inference (same as C code on RISC-V) ======
x = img_resized.flatten().astype(np.int32)  # 512 pixels, 0-255
print(f'\n输入像素 min={x.min()}, max={x.max()}')

# Layer0: 512 -> 256
h0 = (x.dot(w0) + b0) >> 15  # int16 multiply + shift
h0 = np.maximum(h0, 0).clip(0, 32767).astype(np.int32)  # ReLU
print(f'Layer0 out: min={h0.min()}, max={h0.max()}')

# Layer1: 256 -> 128
h1 = (h0.dot(w1) + b1) >> 15
h1 = np.maximum(h1, 0).clip(0, 32767).astype(np.int32)
print(f'Layer1 out: min={h1.min()}, max={h1.max()}')

# Layer2: 128 -> 65 (output, no ReLU)
h2 = (h1.dot(w2) + b2) >> 15
print(f'Layer2 out (logits): min={h2.min()}, max={h2.max()}')

# Get prediction
pred_idx = np.argmax(h2)
pred_class = classes[pred_idx]
print(f'\n>>> int16模型预测: {pred_class} (索引={pred_idx}, 分数={h2[pred_idx]})')

# Top-5
top5 = np.argsort(h2)[-5:][::-1]
print('\nTop-5 预测:')
for i, idx in enumerate(top5):
    print(f'  {i+1}. {classes[idx]}: score={h2[idx]}')

# ====== 5. Also retrain float model and compare ======
print('\n' + '='*60)
print('重新训练浮点模型进行对比...')
print('='*60)

from sklearn.neural_network import MLPClassifier
from sklearn.model_selection import train_test_split

# Load training data
X_all, y_all = [], []
for idx, cls in enumerate(classes):
    cls_dir = os.path.join(DATA_DIR, cls)
    for fname in os.listdir(cls_dir):
        if not fname.lower().endswith(('.jpg','.png','.jpeg')): continue
        img_t = cv2.imread(os.path.join(cls_dir, fname), cv2.IMREAD_GRAYSCALE)
        if img_t is None: continue
        img_t = cv2.resize(img_t, (16, 32)).flatten() / 255.0
        X_all.append(img_t); y_all.append(idx)
X_all, y_all = np.array(X_all), np.array(y_all)
print(f'总样本: {len(X_all)}')

X_train, X_val, y_train, y_val = train_test_split(X_all, y_all, test_size=0.2, random_state=42)

model = MLPClassifier(hidden_layer_sizes=(256,128), max_iter=200, random_state=42, verbose=False)
model.fit(X_train, y_train)
float_acc = model.score(X_val, y_val)
print(f'浮点模型验证准确率: {float_acc*100:.1f}%')

# Float inference on char_0.bmp
x_float = img_resized.flatten() / 255.0
float_pred = model.predict([x_float])[0]
float_proba = model.predict_proba([x_float])[0]
float_class = classes[float_pred]
print(f'\n>>> 浮点模型预测: {float_class} (索引={float_pred})')

top5_float = np.argsort(float_proba)[-5:][::-1]
print('\n浮点模型 Top-5:')
for i, idx in enumerate(top5_float):
    print(f'  {i+1}. {classes[idx]}: prob={float_proba[idx]:.4f}')

# ====== 6. What the quantized model would get if we quantize correctly ======
print('\n' + '='*60)
print('诊断: 检查int16量化精度损失')
print('='*60)

# Run float inference layer by layer
x_f = x_float.astype(np.float64)
h0_f = x_f.dot(model.coefs_[0]) + model.intercepts_[0]
h0_f = np.maximum(h0_f, 0)
h1_f = h0_f.dot(model.coefs_[1]) + model.intercepts_[1]
h1_f = np.maximum(h1_f, 0)
h2_f = h1_f.dot(model.coefs_[2]) + model.intercepts_[2]
float_pred_v2 = np.argmax(h2_f)
print(f'浮点逐层推理预测: {classes[float_pred_v2]}')

# Compare int16 vs float for this image
print(f'\n浮点输出向量 (前10): {h2_f[:10]}')
print(f'int16输出向量 (前10): {h2[:10]}')
print(f'\n浮点 argmax = {float_pred_v2} ({classes[float_pred_v2]}), score={h2_f[float_pred_v2]:.2f}')
print(f'int16 argmax = {pred_idx} ({pred_class}), score={h2[pred_idx]}')
