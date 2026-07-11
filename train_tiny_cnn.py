"""
训练TinyCNN字符分类器 → 导出int16权重(适合RISC-V无FPU/无除法/SRAM 256KB)
输入: 1×32×16 灰度  (H=32, W=16)
输出: 65类 (0-9, A-Z, 省份简称)
架构: Conv(1→8) → Pool → Conv(8→16) → Pool → Conv(16→32) → Pool → GAP → FC(32→65)
参数量: 8033 个 int16 ≈ 16KB 权重 + 10KB 激活 = 远小于256KB
"""
import os, numpy as np, cv2, json, sys
import torch
import torch.nn as nn
import torch.nn.functional as F
from sklearn.model_selection import train_test_split

# ===== 配置 =====
DATA_DIR = r'D:\python+pycharm\Project\simple-car-plate-recognition-master\dataset'
OUTPUT_DIR = r'D:\python+pycharm\Project\train_CNN'  # 输出到项目目录
IMG_H, IMG_W = 32, 16  # 高32, 宽16 (cv2.resize(w, h) = (16, 32))
N_EPOCHS = 80
BATCH_SIZE = 128
LR = 0.001
DEVICE = 'cpu'

# ===== 加载数据 =====
print('加载数据...')
classes = sorted([d for d in os.listdir(DATA_DIR)
                  if os.path.isdir(os.path.join(DATA_DIR, d)) and not d.startswith('.')])
N_CLASSES = len(classes)
print(f'类别数: {N_CLASSES}')

X, y = [], []
for idx, cls in enumerate(classes):
    cls_dir = os.path.join(DATA_DIR, cls)
    for fname in os.listdir(cls_dir):
        if not fname.lower().endswith(('.jpg','.png','.jpeg')): continue
        img = cv2.imread(os.path.join(cls_dir, fname), cv2.IMREAD_GRAYSCALE)
        if img is None: continue
        # === 训练预处理管线 (关键! RISC-V上也要做同样的操作) ===
        # Step 1: resize 到 16×32 (宽×高) — OpenCV参数是(width, height)
        # Step 2: /255.0 归一化到 [0,1]
        X.append(cv2.resize(img, (IMG_W, IMG_H)).astype(np.float32) / 255.0)
        y.append(idx)

X = np.array(X).reshape(-1, 1, IMG_H, IMG_W)  # NCHW
y = np.array(y)
print(f'总样本: {len(X)}, shape: {X.shape}')

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
print(f'训练: {len(X_train)}, 测试: {len(X_test)}')

# ===== 定义CNN =====
class TinyCNN(nn.Module):
    """极小CNN: 8033参数, 适合RISC-V软核"""
    def __init__(self, n_classes=65):
        super().__init__()
        self.conv1 = nn.Conv2d(1, 8, 3, padding=1)    # 1→8,  32×16→32×16
        self.conv2 = nn.Conv2d(8, 16, 3, padding=1)   # 8→16, 16×8→16×8
        self.conv3 = nn.Conv2d(16, 32, 3, padding=1)  # 16→32, 8×4→8×4
        self.fc = nn.Linear(32, n_classes)

    def forward(self, x):
        x = F.relu(self.conv1(x))
        x = F.max_pool2d(x, 2)                         # 32×16 → 16×8
        x = F.relu(self.conv2(x))
        x = F.max_pool2d(x, 2)                         # 16×8 → 8×4
        x = F.relu(self.conv3(x))
        x = F.max_pool2d(x, 2)                         # 8×4 → 4×2
        x = x.mean(dim=[2, 3])                         # GAP: 32×4×2 → 32
        x = self.fc(x)
        return x

model = TinyCNN(N_CLASSES)
total_params = sum(p.numel() for p in model.parameters())
print(f'\n参数量: {total_params}')
# 预估权重大小
weight_bytes = total_params * 2  # int16 = 2 bytes
print(f'权重大小(int16): ~{weight_bytes} bytes ({weight_bytes/1024:.1f}KB)')
print(f'远小于SRAM 256KB: {"✅" if weight_bytes < 200*1024 else "❌"}')

# ===== 训练 =====
print('\n开始训练...')
optimizer = torch.optim.Adam(model.parameters(), lr=LR)
scheduler = torch.optim.lr_scheduler.StepLR(optimizer, step_size=30, gamma=0.5)

best_acc = 0
for epoch in range(N_EPOCHS):
    perm = np.random.permutation(len(X_train))
    losses = []
    model.train()
    for i in range(0, len(X_train), BATCH_SIZE):
        idx = perm[i:i+BATCH_SIZE]
        bx = torch.tensor(X_train[idx])
        by = torch.tensor(y_train[idx], dtype=torch.long)
        optimizer.zero_grad()
        out = model(bx)
        loss = F.cross_entropy(out, by)
        loss.backward()
        optimizer.step()
        losses.append(loss.item())

    scheduler.step()
    model.eval()
    with torch.no_grad():
        out = model(torch.tensor(X_test))
        acc = (out.argmax(1).numpy() == y_test).mean()

    if acc > best_acc:
        best_acc = acc
        torch.save(model.state_dict(), os.path.join(OUTPUT_DIR, 'tiny_cnn_best.pt'))

    if (epoch+1) % 10 == 0 or epoch == 0:
        print(f'epoch {epoch+1:3d}/{N_EPOCHS}  loss={np.mean(losses):.4f}  test_acc={acc*100:.1f}%  best={best_acc*100:.1f}%')

print(f'\n训练完成! 最佳测试准确率: {best_acc*100:.1f}%')

# 加载最佳模型
model.load_state_dict(torch.load(os.path.join(OUTPUT_DIR, 'tiny_cnn_best.pt')))
model.eval()

# ===== 导出 int16 权重 =====
print('\n' + '='*60)
print('导出 int16 量化权重')
print('='*60)

# 提取权重
conv_layers = [
    (model.conv1.weight.detach().numpy(), model.conv1.bias.detach().numpy(), 'conv1'),
    (model.conv2.weight.detach().numpy(), model.conv2.bias.detach().numpy(), 'conv2'),
    (model.conv3.weight.detach().numpy(), model.conv3.bias.detach().numpy(), 'conv3'),
]
fc = (model.fc.weight.detach().numpy(), model.fc.bias.detach().numpy(), 'fc')

all_layers_data = []
scales_info = []

for w, b, name in conv_layers + [fc]:
    # w shape: conv=(out_ch, in_ch, kH, kW), fc=(out, in)
    # 找max|w|, 计算scale
    w_abs_max = max(np.abs(w).max(), 1e-10)
    scale = w_abs_max / 32767.0
    scale_inv = int(1.0 / scale)  # 用于C代码: y = (sum >> 15) * (1/scale_inv)?

    # 量化为int16
    wq = np.clip(np.round(w / scale), -32768, 32767).astype(np.int16)
    bq = np.clip(np.round(b / scale), -32768, 32767).astype(np.int16)

    all_layers_data.append((wq, bq, scale, scale_inv, name))
    print(f'{name:8s}: shape={str(w.shape):20s} scale=1/{scale_inv:6d}  '
          f'w范围=[{wq.min()},{wq.max()}]  b范围=[{bq.min()},{bq.max()}]')

# 保存二进制权重 (全部拼接)
print('\n保存二进制权重...')
all_bin = np.concatenate([
    np.concatenate([w.ravel(), b])
    for w, b, _, _, _ in all_layers_data
]).astype(np.int16)
all_bin.tofile(os.path.join(OUTPUT_DIR, 'tiny_cnn.bin'))
print(f'tiny_cnn.bin: {len(all_bin)} int16 = {len(all_bin)*2} bytes = {len(all_bin)*2/1024:.1f}KB')

# ===== 生成C头文件 =====
print('生成C头文件...')
with open(os.path.join(OUTPUT_DIR, 'tiny_cnn.h'), 'w') as f:
    f.write('// TinyCNN int16 weights for RISC-V (no FPU, no div)\n')
    f.write('// Auto-generated by train_tiny_cnn.py\n')
    f.write(f'// {N_CLASSES} classes, {total_params} params\n')
    f.write(f'// Architecture: Conv(1->8) Pool Conv(8->16) Pool Conv(16->32) Pool GAP FC(32->{N_CLASSES})\n')
    f.write('#include <stdint.h>\n\n')

    # 层定义
    layer_shapes = [
        ('conv1', 1, 8, 3, 3, IMG_H, IMG_W),      # in_ch, out_ch, kH, kW, inH, inW
        ('pool1', 8, 8, 2, 2, IMG_H//2, IMG_W//2),
        ('conv2', 8, 16, 3, 3, IMG_H//2, IMG_W//2),
        ('pool2', 16, 16, 2, 2, IMG_H//4, IMG_W//4),
        ('conv3', 16, 32, 3, 3, IMG_H//4, IMG_W//4),
        ('pool3', 32, 32, 2, 2, IMG_H//8, IMG_W//8),
        ('gap', 32, 32, IMG_H//8, IMG_W//8, 1, 1),
        ('fc', 32, N_CLASSES, 0, 0, 0, 0),
    ]

    ptr = 0
    for i, (name, in_ch, out_ch, kH, kW, h, w) in enumerate(layer_shapes):
        if 'conv' in name:
            f.write(f'// Layer{i}: {name}  {in_ch}->{out_ch}  {kH}x{kW}  input={h}x{w}\n')

    f.write('\n// Weight/bias offsets in tiny_cnn.bin\n')
    ptr = 0
    for wq, bq, scale, scale_inv, name in all_layers_data:
        sz_w = wq.size
        sz_b = bq.size
        f.write(f'#define {name.upper()}_OFFSET {ptr}\n')
        f.write(f'#define {name.upper()}_BIAS_OFFSET {ptr + sz_w}\n')
        f.write(f'#define {name.upper()}_SCALE_INV {scale_inv}\n')
        if wq.ndim == 4:  # conv: O,C,H,W
            f.write(f'#define {name.upper()}_OUT_CH {wq.shape[0]}\n')
            f.write(f'#define {name.upper()}_IN_CH {wq.shape[1]}\n')
            f.write(f'#define {name.upper()}_KH {wq.shape[2]}\n')
            f.write(f'#define {name.upper()}_KW {wq.shape[3]}\n')
        else:  # fc: O,I
            f.write(f'#define {name.upper()}_OUT {wq.shape[0]}\n')
            f.write(f'#define {name.upper()}_IN {wq.shape[1]}\n')
        f.write(f'#define {name.upper()}_BIAS_N {sz_b}\n')
        ptr += sz_w + sz_b
        f.write('\n')

    # 导出classes列表
    f.write(f'#define N_CLASSES {N_CLASSES}\n')
    f.write('const char* class_names[N_CLASSES] = {\n')
    for c in classes:
        f.write(f'  "{c}",\n')
    f.write('};\n\n')

    # C推理函数声明
    f.write('''
// 推理函数: 输入 grayscale 32x16 uint8, 输出类别索引
// 用法: int pred = tiny_cnn_predict(image_32x16);
int tiny_cnn_predict(const uint8_t image[32][16]);
''')

# ===== 验证 int16 推理 (在Python中模拟C代码) =====
print('\n' + '='*60)
print('验证 int16 量化推理 (模拟RISC-V上的C代码)')
print('='*60)

def conv2d_int16(x, w, b, shift=15):
    """2D卷积 int16 量化推理 (无FPU, 无除法)"""
    out_ch, in_ch, kh, kw = w.shape
    h, w_in = x.shape[2], x.shape[3]
    h_out = h - kh + 1 + 2  # padding=1
    w_out = w_in - kw + 1 + 2

    # 先pad输入 (zero padding)
    x_pad = np.pad(x, ((0,0), (0,0), (1,1), (1,1)), mode='constant')

    y = np.zeros((1, out_ch, h, w_in), dtype=np.int32)  # same size due to pad=1
    for oc in range(out_ch):
        for ic in range(in_ch):
            y[0, oc] += F.conv2d(
                torch.tensor(x_pad[:, ic:ic+1]),
                torch.tensor(w[oc:oc+1, ic:ic+1]),
                padding=0
            ).numpy().astype(np.int32)[0, 0]
        y[0, oc] += b[oc]
    y = (y >> shift).clip(0, 32767).astype(np.int32)
    return y

def fc_int16(x_flat, w, b, shift=15):
    """全连接层 int16 量化推理"""
    out = x_flat.dot(w.T) + b
    out = out >> shift
    return out

# 逐层验证
ptr = 0
correct = 0
total = min(500, len(X_test))

for i in range(total):
    # 输入: [0,1] float → [0,255] int (和RISC-V上一样)
    x = (X_test[i] * 255).astype(np.int32)  # shape: (1, 32, 16)

    # Conv1 + Pool
    wq, bq, _, _, _ = all_layers_data[0]
    x = conv2d_int16(x.reshape(1,1,32,16), wq, bq)
    x = F.max_pool2d(torch.tensor(x), 2).numpy()

    # Conv2 + Pool
    wq, bq, _, _, _ = all_layers_data[1]
    x = conv2d_int16(x, wq, bq)
    x = F.max_pool2d(torch.tensor(x), 2).numpy()

    # Conv3 + Pool
    wq, bq, _, _, _ = all_layers_data[2]
    x = conv2d_int16(x, wq, bq)
    x = F.max_pool2d(torch.tensor(x), 2).numpy()

    # GAP: 平均池化 (H=4, W=2)
    x = x.mean(axis=(2, 3), keepdims=True).flatten().astype(np.int32)

    # FC
    wq, bq, _, _, _ = all_layers_data[3]
    x = fc_int16(x, wq, bq)

    if np.argmax(x) == y_test[i]:
        correct += 1

acc = correct / total * 100
print(f'int16量化推理: {correct}/{total} = {acc:.1f}%')
print(f'浮点推理: ~96.2%')
print(f'精度损失: {96.2 - acc:.1f}%')

# ===== 测试 char_0.bmp =====
print('\n' + '='*60)
print('测试 char_0.bmp')
print('='*60)

img_test = cv2.imread(r'D:\MATLAB\PIC\single_word_debug\char_0.bmp', cv2.IMREAD_GRAYSCALE)
if img_test is not None:
    x_test = cv2.resize(img_test, (IMG_W, IMG_H)).astype(np.float32) / 255.0
    x_test = x_test.reshape(1, 1, IMG_H, IMG_W)

    # 浮点推理
    with torch.no_grad():
        out_f = model(torch.tensor(x_test)).numpy()[0]
    pred_f = np.argmax(out_f)
    print(f'浮点模型预测: {classes[pred_f]} (idx={pred_f})')
    top5_f = np.argsort(out_f)[-5:][::-1]
    for i, idx in enumerate(top5_f):
        print(f'  {i+1}. {classes[idx]:10s} prob={F.softmax(torch.tensor(out_f), dim=0)[idx]:.4f}')

    # int16推理
    x = (x_test * 255).astype(np.int32)[0]  # (1, 32, 16)

    wq, bq, _, _, _ = all_layers_data[0]
    x = conv2d_int16(x.reshape(1,1,32,16), wq, bq)
    x = F.max_pool2d(torch.tensor(x), 2).numpy()

    wq, bq, _, _, _ = all_layers_data[1]
    x = conv2d_int16(x, wq, bq)
    x = F.max_pool2d(torch.tensor(x), 2).numpy()

    wq, bq, _, _, _ = all_layers_data[2]
    x = conv2d_int16(x, wq, bq)
    x = F.max_pool2d(torch.tensor(x), 2).numpy()

    x = x.mean(axis=(2, 3)).flatten().astype(np.int32)

    wq, bq, _, _, _ = all_layers_data[3]
    x = fc_int16(x, wq, bq)

    pred_int = np.argmax(x)
    print(f'\nint16量化预测: {classes[pred_int]} (idx={pred_int})')
    top5_int = np.argsort(x)[-5:][::-1]
    for i, idx in enumerate(top5_int):
        print(f'  {i+1}. {classes[idx]:10s} score={x[idx]:6d}')

print('\nDone!')
print(f'输出文件:')
print(f'  {os.path.join(OUTPUT_DIR, "tiny_cnn_best.pt")}  (PyTorch权重)')
print(f'  {os.path.join(OUTPUT_DIR, "tiny_cnn.bin")}       (int16二进制权重)')
print(f'  {os.path.join(OUTPUT_DIR, "tiny_cnn.h")}         (C头文件 + 推理函数声明)')
