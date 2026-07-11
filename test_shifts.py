"""
加载已训练的CNN权重, 测试不同shift值对精度的影响
"""
import os, numpy as np, cv2

DATA_DIR = r'D:\python+pycharm\Project\simple-car-plate-recognition-master\dataset'
IMG_H, IMG_W = 32, 16
CONV1 = 8; CONV2 = 16; FC1 = 64

classes = sorted([d for d in os.listdir(DATA_DIR)
                  if os.path.isdir(os.path.join(DATA_DIR, d)) and not d.startswith('.')])

# 从bin文件加载量化权重
data = np.fromfile(r'C:\Users\杜龙yue\AppData\Roaming\reasonix\global-workspace\cnn_weights.bin', dtype=np.int16).astype(np.int64)

# 解析 (与train_cnn_v2顺序一致)
ptr = 0
conv1_b = data[ptr:ptr+8]; ptr += 8          # (8,)
conv1_w = data[ptr:ptr+8*1*3*3].reshape(8,1,3,3); ptr += 8*1*3*3  # (8,1,3,3)
conv2_b = data[ptr:ptr+16]; ptr += 16        # (16,)
conv2_w = data[ptr:ptr+16*8*3*3].reshape(16,8,3,3); ptr += 16*8*3*3  # (16,8,3,3)
fc1_b = data[ptr:ptr+64]; ptr += 64          # (64,)
fc1_w = data[ptr:ptr+64*192].reshape(64,192); ptr += 64*192  # (64,192)
fc2_b = data[ptr:ptr+65]; ptr += 65          # (65,)
fc2_w = data[ptr:ptr+65*64].reshape(65,64); ptr += 65*64    # (65,64)
print(f'加载权重: {ptr} int16值')

# 加载部分验证数据
n_test = 500
X_test, y_test = [], []
for idx, cls in enumerate(classes):
    for fname in os.listdir(os.path.join(DATA_DIR, cls)):
        if not fname.lower().endswith(('.jpg','.png','.jpeg')): continue
        img = cv2.imread(os.path.join(DATA_DIR, cls, fname), cv2.IMREAD_GRAYSCALE)
        if img is None: continue
        img = cv2.resize(img, (IMG_W, IMG_H))
        X_test.append(img / 255.0); y_test.append(idx)
        if len(X_test) >= n_test: break
    if len(X_test) >= n_test: break
X_test = np.array(X_test); y_test = np.array(y_test)
print(f'测试样本: {len(X_test)}')

# 测试不同shift值
for shift in [8, 9, 10, 11, 12, 13, 14, 15, 16, 17]:
    correct = 0
    for i in range(len(X_test)):
        img = (X_test[i] * 255).astype(np.int64)

        # Conv1
        h = np.zeros((CONV1, 30, 14), dtype=np.int64)
        for co in range(CONV1):
            for r in range(30):
                for c in range(14):
                    h[co,r,c] = np.sum(img[r:r+3,c:c+3] * conv1_w[co,0]) + conv1_b[co]
        h = np.maximum(h >> shift, 0)

        # Pool1
        hp = np.zeros((CONV1, 15, 7), dtype=np.int64)
        for co in range(CONV1):
            for r in range(15):
                for c in range(7):
                    hp[co,r,c] = np.max(h[co, r*2:r*2+2, c*2:c*2+2])

        # Conv2
        h2 = np.zeros((CONV2, 13, 5), dtype=np.int64)
        for co in range(CONV2):
            for ci in range(CONV1):
                for r in range(13):
                    for c in range(5):
                        h2[co,r,c] += np.sum(hp[ci,r:r+3,c:c+3] * conv2_w[co,ci])
            h2[co] += conv2_b[co]
        h2 = np.maximum(h2 >> shift, 0)

        # Pool2
        h2p = np.zeros((CONV2, 6, 2), dtype=np.int64)
        for co in range(CONV2):
            for r in range(6):
                for c in range(2):
                    h2p[co,r,c] = np.max(h2[co, r*2:r*2+2, c*2:c*2+2])

        flat = h2p.ravel()
        hfc1 = np.maximum((flat.dot(fc1_w.T) + fc1_b) >> shift, 0)
        out = (hfc1.dot(fc2_w.T) + fc2_b) >> shift
        if np.argmax(out) == y_test[i]:
            correct += 1
    print(f'  >> {shift:2d}: {correct}/{len(X_test)} = {correct/len(X_test)*100:.2f}%')
