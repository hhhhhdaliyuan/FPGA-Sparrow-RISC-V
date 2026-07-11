import os, sys, numpy as np, cv2

# ====== 1. Load classes ======
DATA_DIR = r'D:\python+pycharm\Project\simple-car-plate-recognition-master\dataset'
classes = sorted([d for d in os.listdir(DATA_DIR)
                  if os.path.isdir(os.path.join(DATA_DIR, d)) and not d.startswith('.')])
print(f'类别数: {len(classes)}')
print(f'类别列表: {classes}')
print()

# ====== 2. Load saved int16 weights ======
w0 = np.load(r'D:\python+pycharm\Project\train_CNN\layer0_w.npy').astype(np.int32)
b0 = np.load(r'D:\python+pycharm\Project\train_CNN\layer0_b.npy').astype(np.int32)
w1 = np.load(r'D:\python+pycharm\Project\train_CNN\layer1_w.npy').astype(np.int32)
b1 = np.load(r'D:\python+pycharm\Project\train_CNN\layer1_b.npy').astype(np.int32)
w2 = np.load(r'D:\python+pycharm\Project\train_CNN\layer2_w.npy').astype(np.int32)
b2 = np.load(r'D:\python+pycharm\Project\train_CNN\layer2_b.npy').astype(np.int32)

# ====== 3. Load and preprocess char_0.bmp ======
img = cv2.imread(r'D:\MATLAB\PIC\single_word_debug\char_0.bmp', cv2.IMREAD_GRAYSCALE)
print(f'原始图像 shape: {img.shape}')
print(f'像素值范围: [{img.min()}, {img.max()}], 均值: {img.mean():.1f}')

# Resize to 16x32
img_resized = cv2.resize(img, (16, 32))
print(f'缩放后 shape: {img_resized.shape}')

# ASCII art of resized
print('缩放后(16x32):')
for r in range(32):
    row = img_resized[r, :]
    line = ''.join(['#' if p < 128 else ' ' for p in row])
    print(f'  |{line}|')

# ====== 4. Int16 inference ======
x = img_resized.flatten().astype(np.int32)  # [0, 255]

# Layer0: 512 -> 256  (int16 weights were quantized with a scale factor)
# The weights are already int16 quantized, but we need to find the scale
# From export_v2.py: wq = round(w / s), s = max|w|/32767
# So in inference: (x * wq) >> 15 approximates x * (w * 32767/max|w|) / 32767 = x * w/max|w|
# Wait, let me re-think...
# export_v2.py does: s = max|w| / 32767, wq = round(w / s), x.dot(wq) >> 15
# x is in [0, 255], wq is int16
# x.dot(wq) >> 15 = sum(x_i * wq_i) >> 15
# = sum(x_i * round(w_i / s)) >> 15 ≈ sum(x_i * w_i / s) >> 15
# = sum(x_i * w_i) / (s * 32768) ... this depends on the scale

# Actually the training data was normalized to [0,1], but the int16 inference uses [0,255].
# x = img_resized.flatten() / 255.0 in training, but x = img_resized.flatten() * 255 / 255 = img_resized.flatten() in int16
# Wait, in the export scripts: x = (X_test[i] * 255).astype(np.int32) — they scale from [0,1] to [0,255]
# So the int16 inference uses pixel values [0,255] directly.

# But wait - the npy weights were saved from export_v2.py, which also does validation with (X_test[i] * 255)
# X_test[i] is in [0,1] range (from /255.0 during training data loading)
# So x = X_test[i] * 255 gives [0,255]
# This matches: we read BMP as [0,255], resize (keeps [0,255]), and use directly.

h0 = (x.dot(w0) + b0) >> 15
h0 = np.maximum(h0, 0).clip(0, 32767).astype(np.int32)
print(f'\nLayer0 -> 256: min={h0.min()}, max={h0.max()}')

h1 = (h0.dot(w1) + b1) >> 15
h1 = np.maximum(h1, 0).clip(0, 32767).astype(np.int32)
print(f'Layer1 -> 128: min={h1.min()}, max={h1.max()}')

h2 = (h1.dot(w2) + b2) >> 15
print(f'Layer2 -> 65:  min={h2.min()}, max={h2.max()}')

pred_idx = int(np.argmax(h2))
pred_class = classes[pred_idx]
print(f'\n>>> int16 模型预测: "{pred_class}" (索引={pred_idx}, score={h2[pred_idx]})')

top5 = np.argsort(h2)[-5:][::-1]
print('\nTop-5:')
for i, idx in enumerate(top5):
    print(f'  {i+1}. [{idx:2d}] {classes[idx]:8s}  score={h2[idx]:6d}')

print('\n检查: 湘 = zh_xiang 的索引是', classes.index('zh_xiang') if 'zh_xiang' in classes else 'NOT FOUND')
print('湘 对应的 score =', h2[classes.index('zh_xiang')] if 'zh_xiang' in classes else 'N/A')
