import os, cv2, numpy as np

DATA_DIR = r'D:\python+pycharm\Project\simple-car-plate-recognition-master\dataset'
classes = sorted([d for d in os.listdir(DATA_DIR) if os.path.isdir(os.path.join(DATA_DIR, d)) and not d.startswith('.')])
xiang_idx = classes.index('zh_xiang')

# Load int16 weights
w0 = np.load(r'D:\python+pycharm\Project\train_CNN\layer0_w.npy').astype(np.int32)
b0 = np.load(r'D:\python+pycharm\Project\train_CNN\layer0_b.npy').astype(np.int32)
w1 = np.load(r'D:\python+pycharm\Project\train_CNN\layer1_w.npy').astype(np.int32)
b1 = np.load(r'D:\python+pycharm\Project\train_CNN\layer1_b.npy').astype(np.int32)
w2 = np.load(r'D:\python+pycharm\Project\train_CNN\layer2_w.npy').astype(np.int32)
b2 = np.load(r'D:\python+pycharm\Project\train_CNN\layer2_b.npy').astype(np.int32)

def int16_infer(x_int32):
    h = (x_int32.dot(w0) + b0) >> 15
    h = np.maximum(h, 0).clip(0, 32767)
    h = (h.dot(w1) + b1) >> 15
    h = np.maximum(h, 0).clip(0, 32767)
    h = (h.dot(w2) + b2) >> 15
    return h

# Load test image
img_test = cv2.imread(r'D:\MATLAB\PIC\single_word_debug\char_0.bmp', cv2.IMREAD_GRAYSCALE)
img_small = cv2.resize(img_test, (16, 32))

# Test 1: Original (no inversion)
x1 = img_small.flatten().astype(np.int32)
out1 = int16_infer(x1)
p1 = np.argmax(out1)

print('=== 原始 (不反转) ===')
print(f'预测: {classes[p1]} (idx={p1})')
top5 = np.argsort(out1)[-5:][::-1]
for i, idx in enumerate(top5):
    print(f'  {i+1}. {classes[idx]:10s} score={out1[idx]:6d}')
print(f'  zh_xiang(湘) score={out1[xiang_idx]:6d}')

# Test 2: Inverted
x2 = (255 - img_small).flatten().astype(np.int32)
out2 = int16_infer(x2)
p2 = np.argmax(out2)

print()
print('=== 反转 (255 - pixel) ===')
print(f'预测: {classes[p2]} (idx={p2})')
top5 = np.argsort(out2)[-5:][::-1]
for i, idx in enumerate(top5):
    print(f'  {i+1}. {classes[idx]:10s} score={out2[idx]:6d}')
print(f'  zh_xiang(湘) score={out2[xiang_idx]:6d}')

# Check all 8 test images with inversion
print()
print('=== 所有8张测试图 (反转) ===')
for i in range(8):
    fname = f'char_{i}.bmp'
    img = cv2.imread(f'D:\\MATLAB\\PIC\\single_word_debug\\{fname}', cv2.IMREAD_GRAYSCALE)
    if img is None:
        print(f'{fname}: 无法加载')
        continue
    img_s = cv2.resize(img, (16, 32))
    x = (255 - img_s).flatten().astype(np.int32)
    out = int16_infer(x)
    p = np.argmax(out)
    top3 = np.argsort(out)[-3:][::-1]
    scores_str = ', '.join([f'{classes[j]}({out[j]})' for j in top3])
    print(f'  {fname}: 预测={classes[p]:10s} | Top3: {scores_str}')

# Check all 8 test images WITHOUT inversion
print()
print('=== 所有8张测试图 (不反转) ===')
for i in range(8):
    fname = f'char_{i}.bmp'
    img = cv2.imread(f'D:\\MATLAB\\PIC\\single_word_debug\\{fname}', cv2.IMREAD_GRAYSCALE)
    if img is None:
        print(f'{fname}: 无法加载')
        continue
    img_s = cv2.resize(img, (16, 32))
    x = img_s.flatten().astype(np.int32)
    out = int16_infer(x)
    p = np.argmax(out)
    top3 = np.argsort(out)[-3:][::-1]
    scores_str = ', '.join([f'{classes[j]}({out[j]})' for j in top3])
    print(f'  {fname}: 预测={classes[p]:10s} | Top3: {scores_str}')
