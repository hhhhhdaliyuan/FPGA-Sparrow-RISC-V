"""
加载已训练的CNN权重, 测试不同shift值 (向量化加速)
"""
import os, numpy as np, cv2, time

DATA_DIR = r'D:\python+pycharm\Project\simple-car-plate-recognition-master\dataset'
IMG_H, IMG_W = 32, 16
CONV1 = 8; CONV2 = 16

classes = sorted([d for d in os.listdir(DATA_DIR)
                  if os.path.isdir(os.path.join(DATA_DIR, d)) and not d.startswith('.')])

data = np.fromfile(r'C:\Users\杜龙yue\AppData\Roaming\reasonix\global-workspace\cnn_weights.bin', dtype=np.int16).astype(np.int32)

ptr = 0
conv1_b = data[ptr:ptr+8]; ptr += 8
conv1_w = data[ptr:ptr+8*1*3*3].reshape(8, 3, 3); ptr += 8*1*3*3  # (8,3,3) for single input channel
conv2_b = data[ptr:ptr+16]; ptr += 16
conv2_w = data[ptr:ptr+16*8*3*3].reshape(16, 8, 3, 3); ptr += 16*8*3*3
fc1_b = data[ptr:ptr+64]; ptr += 64
fc1_w = data[ptr:ptr+64*192].reshape(64, 192); ptr += 64*192
fc2_b = data[ptr:ptr+65]; ptr += 65
fc2_w = data[ptr:ptr+65*64].reshape(65, 64); ptr += 65*64
print(f'Loaded {ptr} int16 values')

# Load a small subset of test data
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
print(f'Test samples: {len(X_test)}')

def conv2d_fast(img, w, b):
    """img: (H,W), w: (oc, kh, kw) for single input channel, b: (oc,)"""
    oc, kh, kw = w.shape
    oh, ow = img.shape[0] - kh + 1, img.shape[1] - kw + 1
    out = np.zeros((oc, oh, ow), dtype=np.int32)
    # Use im2col approach: extract patches and do matrix multiply
    for r in range(oh):
        for c in range(ow):
            patch = img[r:r+kh, c:c+kw].ravel()  # (9,)
            out[:, r, c] = patch.dot(w.reshape(oc, -1).T) + b
    return out

def conv2d_multi_channel(img, w, b):
    """img: (ic, H, W), w: (oc, ic, kh, kw), b: (oc,)"""
    oc, ic, kh, kw = w.shape
    oh, ow = img.shape[1] - kh + 1, img.shape[2] - kw + 1
    out = np.zeros((oc, oh, ow), dtype=np.int32)
    for r in range(oh):
        for c in range(ow):
            patch = img[:, r:r+kh, c:c+kw].ravel()  # (ic*kh*kw,)
            out[:, r, c] = patch.dot(w.reshape(oc, -1).T) + b
    return out

def pool2d(x):
    """x: (c, H, W) -> (c, H//2, W//2)"""
    c, h, w = x.shape
    return x.reshape(c, h//2, 2, w//2, 2).max(axis=(2, 4))

def infer_one(img_255, shift):
    """img_255: (32,16) int32 [0,255]"""
    # Conv1
    h = conv2d_fast(img_255, conv1_w, conv1_b)  # (8,30,14)
    h = np.maximum(h >> shift, 0)
    hp = pool2d(h)  # (8,15,7)

    # Conv2
    h2 = conv2d_multi_channel(hp, conv2_w, conv2_b)  # (16,13,5)
    h2 = np.maximum(h2 >> shift, 0)
    h2p = pool2d(h2)  # (16,6,2)

    flat = h2p.ravel()  # (192,)
    hfc1 = np.maximum((flat.dot(fc1_w.T) + fc1_b) >> shift, 0)
    out = (hfc1.dot(fc2_w.T) + fc2_b) >> shift
    return out

# Test different shift values
print('\nTesting shift values...')
for shift in [8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]:
    t0 = time.time()
    correct = 0
    for i in range(len(X_test)):
        img = (X_test[i] * 255).astype(np.int32)
        out = infer_one(img, shift)
        if np.argmax(out) == y_test[i]:
            correct += 1
    dt = time.time() - t0
    print(f'  >> {shift:2d}: {correct}/{len(X_test)} = {correct/len(X_test)*100:.2f}%  ({dt:.1f}s)')
