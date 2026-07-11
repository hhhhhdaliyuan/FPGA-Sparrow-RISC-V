"""
快速验证: 用已训练好的float权重测试不同量化策略
策略: bias用weight的scale (不是bias自己的scale)
"""
import os, numpy as np, cv2, torch, time, torch.nn as nn, torch.nn.functional as F

DATA_DIR = r'D:\python+pycharm\Project\simple-car-plate-recognition-master\dataset'
IMG_H, IMG_W = 32, 16

classes = sorted([d for d in os.listdir(DATA_DIR)
                  if os.path.isdir(os.path.join(DATA_DIR, d)) and not d.startswith('.')])

# Load just enough data for testing
print('Loading data...')
X_small, y_small = [], []
for idx, cls in enumerate(classes):
    for fname in os.listdir(os.path.join(DATA_DIR, cls)):
        if not fname.lower().endswith(('.jpg','.png','.jpeg')): continue
        img = cv2.imread(os.path.join(DATA_DIR, cls, fname), cv2.IMREAD_GRAYSCALE)
        if img is None: continue
        X_small.append(cv2.resize(img, (IMG_W, IMG_H)).astype(np.float32) / 255.0)
        y_small.append(idx)
        if len(X_small) >= 200: break
    if len(X_small) >= 200: break
X_small = np.array(X_small); y_small = np.array(y_small)
print(f'Loaded {len(X_small)} samples')

class TinyCNN(nn.Module):
    def __init__(self, n_classes):
        super().__init__()
        self.conv1 = nn.Conv2d(1, 8, 3, bias=True)
        self.conv2 = nn.Conv2d(8, 16, 3, bias=True)
        self.fc1 = nn.Linear(16*6*2, 64, bias=True)
        self.fc2 = nn.Linear(64, n_classes, bias=True)
    def forward(self, x):
        x = F.relu(self.conv1(x)); x = F.max_pool2d(x, 2)
        x = F.relu(self.conv2(x)); x = F.max_pool2d(x, 2)
        x = x.view(x.size(0), -1)
        x = F.relu(self.fc1(x)); x = self.fc2(x)
        return x

# Train tiny model on small data
print('Training...')
model = TinyCNN(len(classes))
loader = torch.utils.data.DataLoader(
    torch.utils.data.TensorDataset(
        torch.tensor(X_small[:, None, :, :]), torch.tensor(y_small)),
    batch_size=32, shuffle=True)
opt = torch.optim.Adam(model.parameters(), lr=0.01)
for epoch in range(30):
    model.train()
    for bx, by in loader:
        opt.zero_grad(); nn.CrossEntropyLoss()(model(bx), by).backward(); opt.step()
model.eval()
with torch.no_grad():
    acc = (model(torch.tensor(X_small[:, None, :, :])).argmax(1) == torch.tensor(y_small)).float().mean().item()
print(f'Accuracy: {acc*100:.2f}%')

float_w = {k: v.numpy() for k, v in model.state_dict().items()}

# ==== 量化策略对比 ====
MAX_VAL = 32767
n = len(X_small)

def quantize(w, s_factor=None):
    """如果s_factor=None, 用w自己的max; 否则用指定的s_factor"""
    if s_factor is None:
        s = max(np.max(np.abs(w)), 1e-10) / MAX_VAL
    else:
        s = s_factor
    return np.clip(np.round(w / s), -(MAX_VAL+1), MAX_VAL).astype(np.int64), s

def test_quantization(strategy_name, use_bias_weight_scale, shifts):
    """测试量化策略
    use_bias_weight_scale: True=bias用同层weight的scale, False=bias用自己的scale
    shifts: (sh_conv1, sh_conv2, sh_fc1, sh_fc2)
    """
    # Quantize weights
    qw1, s_w1 = quantize(float_w['conv1.weight'])
    qw2, s_w2 = quantize(float_w['conv2.weight'])
    qf1, s_f1 = quantize(float_w['fc1.weight'])
    qf2, s_f2 = quantize(float_w['fc2.weight'])
    
    if use_bias_weight_scale:
        qb1, _ = quantize(float_w['conv1.bias'], s_w1)
        qb2, _ = quantize(float_w['conv2.bias'], s_w2)
        qfb1, _ = quantize(float_w['fc1.bias'], s_f1)
        qfb2, _ = quantize(float_w['fc2.bias'], s_f2)
    else:
        qb1, _ = quantize(float_w['conv1.bias'])
        qb2, _ = quantize(float_w['conv2.bias'])
        qfb1, _ = quantize(float_w['fc1.bias'])
        qfb2, _ = quantize(float_w['fc2.bias'])
    
    sh_c1, sh_c2, sh_f1, sh_f2 = shifts
    
    correct = 0
    for i in range(n):
        img = (X_small[i] * 255).astype(np.int64)
        
        # Conv1 vectorized
        patches = np.lib.stride_tricks.sliding_window_view(img, (3, 3)).reshape(-1, 9)
        w1_flat = qw1[:, 0, :, :].reshape(8, 9)
        h1 = np.maximum((patches @ w1_flat.T + qb1).T.reshape(8, 30, 14) >> sh_c1, 0)
        hp1 = h1.reshape(8, 15, 2, 7, 2).max(axis=(2, 4))
        
        # Conv2
        patches2 = np.lib.stride_tricks.sliding_window_view(
            hp1.transpose(1,2,0), (3,3,8)).reshape(13*5, -1)
        w2_flat = qw2.reshape(16, -1)
        h2 = np.maximum((patches2 @ w2_flat.T + qb2).T.reshape(16, 13, 5) >> sh_c2, 0)
        hp2 = h2.reshape(16, 6, 2, 2, 2).max(axis=(2, 4))
        
        flat = hp2.ravel()
        hfc1 = np.maximum((flat @ qf1.T + qfb1) >> sh_f1, 0)
        out = (hfc1 @ qf2.T + qfb2) >> sh_f2
        
        if np.argmax(out) == y_small[i]:
            correct += 1
    
    return correct / n

print(f'\n{"Strategy":40s} {"Acc":>8s}')
print('-' * 50)

# Strategy 1: 原始方式 (bias用自己的scale, >>15)
acc = test_quantization('bias=self, >>15 all', False, (15,15,15,15))
print(f'{"bias=self, >>15 all":40s} {acc*100:7.2f}%')

# Strategy 2: bias用weight的scale, >>15
acc = test_quantization('bias=weight_scale, >>15 all', True, (15,15,15,15))
print(f'{"bias=weight_scale, >>15 all":40s} {acc*100:7.2f}%')

# Strategy 3: bias用weight的scale, 不同shift
for sh in [12, 13, 14]:
    acc = test_quantization(f'bias=weight_scale, >>{sh} all', True, (sh,sh,sh,sh))
    print(f'{"bias=weight_scale, >>%d all"%sh:40s} {acc*100:7.2f}%')

# Strategy 4: Per-layer shift (conv lower, fc higher)
for csh in [11, 12, 13, 14]:
    for fsh in [13, 14, 15]:
        acc = test_quantization(f'bias=weight_scale, conv>>{csh} fc>>{fsh}', True, (csh,csh,fsh,fsh))
        print(f'{"bias=weight_scale, conv>>%d fc>>%d"%(csh,fsh):40s} {acc*100:7.2f}%')

print(f'\nFloat ref: {acc*100:.2f}% (on test set)')
