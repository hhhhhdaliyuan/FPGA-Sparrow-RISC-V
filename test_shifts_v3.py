"""
快速测试不同shift值 (用PyTorch做前向, 只验证量化部分)
"""
import os, numpy as np, cv2, torch, time

DATA_DIR = r'D:\python+pycharm\Project\simple-car-plate-recognition-master\dataset'
IMG_H, IMG_W = 32, 16
device = torch.device('cpu')

classes = sorted([d for d in os.listdir(DATA_DIR)
                  if os.path.isdir(os.path.join(DATA_DIR, d)) and not d.startswith('.')])
print(f'Classes: {len(classes)}')

# Load float model (re-train tiny version)
# Actually, just load a pre-trained state dict
# Re-train a minimal model quickly
import torch.nn as nn
import torch.nn.functional as F

class TinyCNN(nn.Module):
    def __init__(self):
        super().__init__()
        self.conv1 = nn.Conv2d(1, 8, 3, bias=True)
        self.conv2 = nn.Conv2d(8, 16, 3, bias=True)
        self.fc1 = nn.Linear(16*6*2, 64, bias=True)
        self.fc2 = nn.Linear(64, len(classes), bias=True)
    def forward(self, x):
        x = F.relu(self.conv1(x)); x = F.max_pool2d(x, 2)
        x = F.relu(self.conv2(x)); x = F.max_pool2d(x, 2)
        x = x.view(x.size(0), -1)
        x = F.relu(self.fc1(x)); x = self.fc2(x)
        return x

# Load saved weights from cnn_weights.bin
model = TinyCNN()
state = model.state_dict()
data = np.fromfile(r'C:\Users\杜龙yue\AppData\Roaming\reasonix\global-workspace\cnn_weights.bin', dtype=np.int16).astype(np.float32)
ptr = 0
for name in sorted(state.keys()):
    shape = state[name].shape
    sz = int(np.prod(shape))
    # The weights in bin are int16 quantized, but we need the dequantized float for comparison
    # For speed, just retrain from scratch
    ptr += sz

# JUST RETRAIN FROM SCRATCH (smaller, faster)
X, y = [], []
for idx, cls in enumerate(classes):
    for fname in os.listdir(os.path.join(DATA_DIR, cls)):
        if not fname.lower().endswith(('.jpg','.png','.jpeg')): continue
        img = cv2.imread(os.path.join(DATA_DIR, cls, fname), cv2.IMREAD_GRAYSCALE)
        if img is None: continue
        X.append(cv2.resize(img, (IMG_W, IMG_H)).astype(np.float32) / 255.0)
        y.append(idx)
X = np.array(X); y = np.array(y)
from sklearn.model_selection import train_test_split
X_train, X_val, y_train, y_val = train_test_split(X, y, test_size=0.2, random_state=42)
print(f'Train: {len(X_train)}, Val: {len(X_val)}')

X_val_t = torch.tensor(X_val[:, None, :, :], dtype=torch.float32)
y_val_t = torch.tensor(y_val, dtype=torch.long)

print('Training float model...')
model = TinyCNN()
train_loader = torch.utils.data.DataLoader(
    torch.utils.data.TensorDataset(
        torch.tensor(X_train[:, None, :, :], dtype=torch.float32),
        torch.tensor(y_train, dtype=torch.long)),
    batch_size=64, shuffle=True)
opt = torch.optim.Adam(model.parameters(), lr=0.01)

for epoch in range(20):
    model.train()
    for bx, by in train_loader:
        opt.zero_grad(); nn.CrossEntropyLoss()(model(bx), by).backward(); opt.step()
    model.eval()
    with torch.no_grad():
        acc = (model(X_val_t).argmax(1) == y_val_t).float().mean().item()
    if (epoch+1) % 5 == 0:
        print(f'  epoch {epoch+1:2d} acc={acc*100:.2f}%')

# Float accuracy
model.eval()
with torch.no_grad():
    float_logits = model(X_val_t)
    float_acc = (float_logits.argmax(1) == y_val_t).float().mean().item()
print(f'Float val acc: {float_acc*100:.2f}%')

# Get float weights
float_w = {k: v.numpy() for k, v in model.state_dict().items()}

# Now quantize and test different shifts
MAX_VAL = 32767
print('\nQuantizing and testing shifts...')

# Extract and quantize
q = {}
for name in sorted(float_w.keys()):
    w = float_w[name]
    s = max(np.max(np.abs(w)), 1e-10) / MAX_VAL
    wq = np.clip(np.round(w / s), -(MAX_VAL+1), MAX_VAL).astype(np.int16)
    q[name] = wq

# Test with 100 validation samples
n = min(200, len(X_val))
print(f'Testing {n} samples...')

# Pre-compute all quantized weight arrays as int64 for fast inference
qw1 = q['conv1.weight'].astype(np.int64)  # (8,1,3,3)
qb1 = q['conv1.bias'].astype(np.int64)    # (8,)
qw2 = q['conv2.weight'].astype(np.int64)  # (16,8,3,3)
qb2 = q['conv2.bias'].astype(np.int64)    # (16,)
qf1 = q['fc1.weight'].astype(np.int64)    # (64,192)
qfb1 = q['fc1.bias'].astype(np.int64)     # (64,)
qf2 = q['fc2.weight'].astype(np.int64)    # (65,64)
qfb2 = q['fc2.bias'].astype(np.int64)     # (65,)

# Vectorized im2col for speed: process one image at a time but vectorize inner loops
def infer_int(img_u8, sh_conv1, sh_conv2, sh_fc1, sh_fc2):
    """img_u8: (32,16) int32 [0,255]"""
    # Conv1: use vectorized approach
    # img: (32,16), w: (8,3,3)
    h, w_in = img_u8.shape
    # im2col: extract all 3x3 patches -> (30*14, 9)
    patches = np.lib.stride_tricks.sliding_window_view(img_u8, (3, 3)).reshape(-1, 9)  # (420, 9)
    w1_flat = qw1[:, 0, :, :].reshape(8, 9)  # (8, 9)
    h1 = (patches @ w1_flat.T + qb1).T.reshape(8, 30, 14)  # (8, 30, 14)
    h1 = np.maximum(h1 >> sh_conv1, 0)
    # Pool: (8,15,7)
    hp1 = h1.reshape(8, 15, 2, 7, 2).max(axis=(2, 4))

    # Conv2: multi-channel im2col
    # hp1: (8, 15, 7)
    ic = 8
    patches2 = np.lib.stride_tricks.sliding_window_view(
        hp1.transpose(1, 2, 0), (3, 3, ic)).reshape(13*5, -1)  # (65, 8*3*3=72)
    w2_flat = qw2.reshape(16, -1)  # (16, 72)
    h2 = (patches2 @ w2_flat.T + qb2).T.reshape(16, 13, 5)
    h2 = np.maximum(h2 >> sh_conv2, 0)
    # Pool: (16, 6, 2)
    hp2 = h2.reshape(16, 6, 2, 2, 2).max(axis=(2, 4))

    flat = hp2.ravel()  # (192,)
    hfc1 = np.maximum((flat @ qf1.T + qfb1) >> sh_fc1, 0)
    out = (hfc1 @ qf2.T + qfb2) >> sh_fc2
    return out

# Try different shift combinations
print('\n=== Fixed shift for all layers ===')
for shift in [10, 11, 12, 13, 14, 15, 16, 17]:
    t0 = time.time()
    correct = 0
    for i in range(n):
        img = (X_val[i] * 255).astype(np.int64)
        out = infer_int(img, shift, shift, shift, shift)
        if np.argmax(out) == y_val[i]:
            correct += 1
    dt = time.time() - t0
    print(f'  >> {shift:2d}: {correct}/{n} = {correct/n*100:.2f}% ({dt:.1f}s)')

print('\n=== Per-layer shifts (conv=13, fc=14) ===')
t0 = time.time()
correct = 0
for i in range(n):
    img = (X_val[i] * 255).astype(np.int64)
    out = infer_int(img, 13, 13, 14, 14)
    if np.argmax(out) == y_val[i]:
        correct += 1
print(f'  conv=13,fc=14: {correct}/{n} = {correct/n*100:.2f}%')

print('\n=== Per-layer shifts (conv=12, fc=13) ===')
t0 = time.time()
correct = 0
for i in range(n):
    img = (X_val[i] * 255).astype(np.int64)
    out = infer_int(img, 12, 12, 13, 13)
    if np.argmax(out) == y_val[i]:
        correct += 1
print(f'  conv=12,fc=13: {correct}/{n} = {correct/n*100:.2f}%')

print('\n=== Per-layer shifts (conv=11, fc=12) ===')
correct = 0
for i in range(n):
    img = (X_val[i] * 255).astype(np.int64)
    out = infer_int(img, 11, 11, 12, 12)
    if np.argmax(out) == y_val[i]:
        correct += 1
print(f'  conv=11,fc=12: {correct}/{n} = {correct/n*100:.2f}%')

print(f'\nFloat ref: {float_acc*100:.2f}%')
