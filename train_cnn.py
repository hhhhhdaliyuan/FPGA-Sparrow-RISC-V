"""
训练CNN字符分类器 → 导出int8/int16权重 (适配RISC-V无FPU)
输入: 16x32灰度图  输出: 65类(0-9,A-Z,省份缩写)
约束: 无FPU, 无硬件除法, 32位总线, 256KB SRAM

训练流程:
  1. 读取所有图像, resize到16x32, 归一化到[0,1]
  2. 保持2D空间结构 (不flatten)
  3. 训练CNN: Conv → Pool → Conv → Pool → FC
  4. 导出int8/int16权重 + C头文件
  5. 用整数推理验证精度

RISC-V推理流程(需在C代码中实现):
  输入: 16x32 uint8像素 [0,255]
  → Conv (int8权重, int32累加, scale移位)
  → ReLU (max(0, x))
  → MaxPool (取最大值)
  → Conv → ReLU → MaxPool
  → Flatten → FC → ReLU → FC
  → argmax → 类别索引
"""

import os, numpy as np, cv2, time
import torch
import torch.nn as nn
import torch.nn.functional as F

# ========== 1. 配置 ==========
DATA_DIR = r'D:\python+pycharm\Project\simple-car-plate-recognition-master\dataset'
IMG_H, IMG_W = 32, 16   # 注意: torch Conv2d用 (N, C, H, W)

# CNN超参数
CONV1_FILTERS = 8        # 第一层卷积核数
CONV2_FILTERS = 16       # 第二层卷积核数
FC1_NEURONS = 64         # 全连接层神经元数
KERNEL_SIZE = 3          # 卷积核大小
POOL_SIZE = 2            # 池化大小

# 导出配置
USE_INT16 = True         # True=int16, False=int8
OUTPUT_H = 'cnn_weights.h'
OUTPUT_BIN = 'cnn_weights.bin'

device = torch.device('cpu')
print(f'设备: {device}')
print(f'输入: {IMG_H}x{IMG_W}')
print(f'架构: Conv({CONV1_FILTERS})→Pool→Conv({CONV2_FILTERS})→Pool→FC({FC1_NEURONS})→FC(65)')

# ========== 2. 加载数据 ==========
print('\n加载数据...')
classes = sorted([d for d in os.listdir(DATA_DIR)
                  if os.path.isdir(os.path.join(DATA_DIR, d)) and not d.startswith('.')])
print(f'类别数: {len(classes)}')

X, y = [], []
for idx, cls in enumerate(classes):
    cls_dir = os.path.join(DATA_DIR, cls)
    for fname in os.listdir(cls_dir):
        if not fname.lower().endswith(('.jpg','.png','.jpeg')): continue
        img = cv2.imread(os.path.join(cls_dir, fname), cv2.IMREAD_GRAYSCALE)
        if img is None: continue
        img = cv2.resize(img, (IMG_W, IMG_H))  # (H, W)
        X.append(img.astype(np.float32) / 255.0)
        y.append(idx)

X = np.array(X)  # (N, 32, 16)
y = np.array(y)
print(f'总样本: {len(X)}, 形状: {X.shape}')

# 划分训练/验证集
from sklearn.model_selection import train_test_split
X_train, X_val, y_train, y_val = train_test_split(X, y, test_size=0.2, random_state=42)
print(f'训练: {len(X_train)}, 验证: {len(X_val)}')

# 转换为torch tensor: (N, C, H, W)
X_train_t = torch.tensor(X_train[:, None, :, :], dtype=torch.float32)  # (N,1,32,16)
y_train_t = torch.tensor(y_train, dtype=torch.long)
X_val_t = torch.tensor(X_val[:, None, :, :], dtype=torch.float32)
y_val_t = torch.tensor(y_val, dtype=torch.long)

# ========== 3. 定义CNN模型 ==========
class TinyCharCNN(nn.Module):
    """超轻量CNN: 适合RISC-V软核"""
    def __init__(self, num_classes=65):
        super().__init__()
        # Conv1: 1→8, 3x3 → (H-2, W-2) = (30, 14)
        self.conv1 = nn.Conv2d(1, CONV1_FILTERS, KERNEL_SIZE, padding=0, bias=True)
        # After Pool2: (15, 7) → Conv2: 8→16, 3x3 → (13, 5)
        self.conv2 = nn.Conv2d(CONV1_FILTERS, CONV2_FILTERS, KERNEL_SIZE, padding=0, bias=True)
        # After Pool2: (6, 2) → flatten: 16*6*2 = 192
        self._flatten_features = CONV2_FILTERS * 6 * 2
        self.fc1 = nn.Linear(self._flatten_features, FC1_NEURONS, bias=True)
        self.fc2 = nn.Linear(FC1_NEURONS, num_classes, bias=True)

    def forward(self, x):
        # x: (N, 1, 32, 16)
        x = self.conv1(x)          # (N, 8, 30, 14)
        x = F.relu(x)
        x = F.max_pool2d(x, 2)     # (N, 8, 15, 7)

        x = self.conv2(x)          # (N, 16, 13, 5)
        x = F.relu(x)
        x = F.max_pool2d(x, 2)     # (N, 16, 6, 2)

        x = x.view(x.size(0), -1)  # (N, 192)
        x = self.fc1(x)            # (N, 64)
        x = F.relu(x)
        x = self.fc2(x)            # (N, 65)
        return x

model = TinyCharCNN(num_classes=len(classes))
total_params = sum(p.numel() for p in model.parameters())
print(f'\n模型参数量: {total_params:,}')
print(f'int8大小: {total_params:,} bytes = {total_params/1024:.1f}KB')
print(f'int16大小: {total_params*2:,} bytes = {total_params*2/1024:.1f}KB')

# ========== 4. 训练 ==========
print('\n开始训练...')
batch_size = 64
epochs = 30
lr = 0.01

train_dataset = torch.utils.data.TensorDataset(X_train_t, y_train_t)
train_loader = torch.utils.data.DataLoader(train_dataset, batch_size=batch_size, shuffle=True)

criterion = nn.CrossEntropyLoss()
optimizer = torch.optim.Adam(model.parameters(), lr=lr)
scheduler = torch.optim.lr_scheduler.StepLR(optimizer, step_size=10, gamma=0.5)

best_acc = 0
for epoch in range(epochs):
    model.train()
    running_loss = 0.0
    for bx, by in train_loader:
        optimizer.zero_grad()
        outputs = model(bx)
        loss = criterion(outputs, by)
        loss.backward()
        optimizer.step()
        running_loss += loss.item()

    # 验证
    model.eval()
    with torch.no_grad():
        val_out = model(X_val_t)
        val_pred = val_out.argmax(dim=1)
        val_acc = (val_pred == y_val_t).float().mean().item()

    scheduler.step()
    if val_acc > best_acc:
        best_acc = val_acc

    if (epoch+1) % 5 == 0 or epoch == 0:
        print(f'  Epoch {epoch+1:2d}/{epochs} | loss={running_loss/len(train_loader):.4f} | val_acc={val_acc*100:.2f}%')

print(f'\n最佳验证准确率: {best_acc*100:.2f}%')

# 在训练集上也评估一下
model.eval()
with torch.no_grad():
    train_out = model(X_train_t)
    train_pred = train_out.argmax(dim=1)
    train_acc = (train_pred == y_train_t).float().mean().item()
    print(f'训练集准确率: {train_acc*100:.2f}%')

# ========== 5. 提取权重 ==========
print('\n导出权重...')
state = model.state_dict()
weights = {}

for name, param in model.named_parameters():
    w = param.detach().cpu().numpy()
    weights[name] = w
    print(f'  {name}: {w.shape}  min={w.min():.4f}  max={w.max():.4f}')

# ========== 6. 量化导出 ==========
DTYPE = np.int16 if USE_INT16 else np.int8
MAX_VAL = 32767 if USE_INT16 else 127

print(f'\n量化格式: {DTYPE.__name__} (范围[-{MAX_VAL+1}, {MAX_VAL}])')

all_data = []         # 二进制数据
layer_info = []       # 层信息 (name, shape, offset, scale)

offset = 0
for name, w in weights.items():
    # 计算scale: max|w| / MAX_VAL
    scale = max(np.max(np.abs(w)), 1e-10) / MAX_VAL
    wq = np.clip(np.round(w / scale), -(MAX_VAL+1), MAX_VAL).astype(DTYPE)
    scale_inv = int(1.0 / scale)  # 用于C代码: req = (sum >> shift) * scale_inv 或 sum >> shift

    nbytes = w.size * (2 if USE_INT16 else 1)
    layer_info.append((name, w.shape, offset, scale_inv))
    all_data.append(wq.ravel())

    print(f'  {name:20s}: shape={str(w.shape):15s} scale=1/{scale_inv}  offset={offset} ({nbytes}B)')
    offset += w.size

# 合并所有数据
all_flat = np.concatenate([d.astype(np.int64) for d in all_data]).astype(DTYPE)
total_bytes = all_flat.nbytes

# 保存二进制
all_flat.tofile(OUTPUT_BIN)
print(f'\n二进制已保存: {OUTPUT_BIN} ({total_bytes} bytes = {total_bytes/1024:.1f}KB)')

# 生成C头文件
print(f'生成头文件: {OUTPUT_H}')

with open(OUTPUT_H, 'w') as f:
    f.write('// CNN权重 (int16/int8量化)  — 适配RISC-V无FPU\n')
    f.write(f'// 输入: {IMG_H}x{IMG_W}灰度  输出: {len(classes)}类\n')
    f.write(f'// 总参数量: {total_params}  {DTYPE.__name__}值 = {total_bytes} bytes = {total_bytes/1024:.1f}KB\n')
    f.write(f'// 量化格式: {DTYPE.__name__}  scale=1/N (推理时右移后乘回)\n')
    f.write('#include <stdint.h>\n\n')

    # 宏定义: 层尺寸
    f.write(f'// ===== 网络结构 =====\n')
    f.write(f'#define IMG_H {IMG_H}\n')
    f.write(f'#define IMG_W {IMG_W}\n')
    f.write(f'#define NUM_CLASSES {len(classes)}\n\n')

    # 为每一层生成尺寸宏 + 偏移宏
    for name, shape, off, scale_inv in layer_info:
        if name.startswith('conv') and name.endswith('.weight'):
            layer_id = name.split('.')[0]  # conv1, conv2
            f.write(f'// {name}: {shape}\n')
            out_ch, in_ch, kh, kw = shape
            f.write(f'#define {layer_id.upper()}_OUT_CH {out_ch}\n')
            f.write(f'#define {layer_id.upper()}_IN_CH {in_ch}\n')
            f.write(f'#define {layer_id.upper()}_KH {kh}\n')
            f.write(f'#define {layer_id.upper()}_KW {kw}\n')
            f.write(f'#define {layer_id.upper()}_W_OFFSET {off}\n')
            f.write(f'#define {layer_id.upper()}_SCALE {scale_inv}\n\n')
        elif name.startswith('conv') and name.endswith('.bias'):
            layer_id = name.split('.')[0]
            f.write(f'#define {layer_id.upper()}_B_OFFSET {off}\n\n')
        elif name.startswith('fc') and name.endswith('.weight'):
            layer_id = name.split('.')[0]
            out_f, in_f = shape
            f.write(f'// {name}: {shape}\n')
            f.write(f'#define {layer_id.upper()}_OUT {out_f}\n')
            f.write(f'#define {layer_id.upper()}_IN {in_f}\n')
            f.write(f'#define {layer_id.upper()}_W_OFFSET {off}\n')
            f.write(f'#define {layer_id.upper()}_SCALE {scale_inv}\n\n')
        elif name.startswith('fc') and name.endswith('.bias'):
            layer_id = name.split('.')[0]
            f.write(f'#define {layer_id.upper()}_B_OFFSET {off}\n\n')

    f.write(f'#define TOTAL_WEIGHTS {offset}\n')
    f.write(f'#define WEIGHTS_BYTES {total_bytes}\n\n')

    # extern声明
    f.write(f'// 权重数组 (存DDR, 按偏移加载)\n')
    f.write(f'extern const {DTYPE.__name__}_t cnn_weights[TOTAL_WEIGHTS];\n\n')

    # 类别名
    f.write(f'// 类别名 (用于调试输出)\n')
    f.write(f'extern const char* class_names[NUM_CLASSES];\n\n')

    # 推理函数声明
    f.write(f'// 推理函数 (纯整数运算, 无FPU)\n')
    f.write(f'int cnn_predict(const uint8_t* img_hw, int* scores_out);\n')
    f.write(f'// img_hw: {IMG_H}x{IMG_W} 灰度像素 [0,255]\n')
    f.write(f'// scores_out: NUM_CLASSES 个输出分数\n')
    f.write(f'// return: 预测类别索引\n')

print(f'\n✅ 导出完成!')

# ========== 7. 整数推理验证 ==========
print(f'\n{"="*60}')
print(f'整数推理验证 (模拟RISC-V无浮点)')
print(f'{"="*60}')

# 加载量化权重
qdata = np.frombuffer(all_flat.tobytes(), dtype=DTYPE).astype(np.int32)

def conv2d_int(input_2d, weight_4d, bias_1d, scale_inv):
    """纯整数Conv2D: input (H,W), weight (oc,ic,kh,kw), bias (oc,)"""
    oc, ic, kh, kw = weight_4d.shape
    ih, iw = input_2d.shape
    oh, ow = ih - kh + 1, iw - kw + 1  # valid padding
    output = np.zeros((oh, ow), dtype=np.int32)
    for co in range(oc):
        for ci in range(ic):
            for r in range(oh):
                for c in range(ow):
                    patch = input_2d[r:r+kh, c:c+kw].astype(np.int32)
                    w_patch = weight_4d[co, ci, :, :].astype(np.int32)
                    output[r, c] += np.sum(patch * w_patch)
        # 加bias
        output += bias_1d[co]
        # 量化还原: >> 15 (对于int16权重, 输入是[0,255])
        # 因为权重 scale = max|w|/32767, 输入是[0,255]
        # x * wq ≈ x * w/scale, 然后>>15 -> x*w/(scale*32768)
        # 但更方便: 直接scale_inv乘
    return output

def fc_int(input_1d, weight_2d, bias_1d, scale_inv):
    """纯整数FC: input (N,), weight (out, in), bias (out,)"""
    w = weight_2d.astype(np.int32)
    b = bias_1d.astype(np.int32)
    out = input_1d.dot(w.T) + b
    # 量化还原: >> 15
    # 但需要看实际数值范围决定
    return out

# 用更高效的向量化方法验证
def conv_int_vectorized(img, w, b, do_relu=True, do_pool=True):
    """
    img: (H, W) int32 [0,255]
    w: (oc, ic, kh, kw) int32 (量化权重)
    b: (oc,) int32 (量化bias)
    """
    oc, ic, kh, kw = w.shape
    ih, iw = img.shape
    oh, ow = ih - kh + 1, iw - kw + 1

    # im2col + 矩阵乘: 对所有输出通道
    out = np.zeros((oc, oh, ow), dtype=np.int32)
    for co in range(oc):
        for r in range(oh):
            for c in range(ow):
                patch = img[r:r+kh, c:c+kw].ravel().astype(np.int32)
                w_row = w[co].ravel().astype(np.int32)
                out[co, r, c] = np.dot(patch, w_row) + b[co]

    # 量化还原: 每个卷积层有自己的scale
    # 这里需要恢复正确的数值范围
    # 使用移位 (因为RISC-V无除法)
    out = out >> 15

    if do_relu:
        out = np.maximum(out, 0).clip(0, 32767)

    if do_pool:
        # 2x2 max pool
        pool_h, pool_w = oh // 2, ow // 2
        pooled = np.zeros((oc, pool_h, pool_w), dtype=np.int32)
        for co in range(oc):
            for r in range(pool_h):
                for c in range(pool_w):
                    pooled[co, r, c] = np.max(out[co, r*2:r*2+2, c*2:c*2+2])
        return pooled
    return out

def fc_int_vectorized(x, w, b, do_relu=True):
    """x: (N,) int32, w: (out, in) int32, b: (out,) int32"""
    out = x.dot(w.T) + b
    out = out >> 15
    if do_relu:
        out = np.maximum(out, 0).clip(0, 32767)
    return out

# 从测试集选样本验证
np.random.seed(42)
val_indices = np.random.choice(len(X_val), min(500, len(X_val)), replace=False)
correct_int = 0

# 解析量化权重
ptr = 0
# conv1.weight (8,1,3,3)
conv1_w = qdata[ptr:ptr+8*1*3*3].reshape(8, 1, 3, 3); ptr += 8*1*3*3
conv1_b = qdata[ptr:ptr+8]; ptr += 8
# conv2.weight (16,8,3,3)
conv2_w = qdata[ptr:ptr+16*8*3*3].reshape(16, 8, 3, 3); ptr += 16*8*3*3
conv2_b = qdata[ptr:ptr+16]; ptr += 16
# fc1.weight (64,192)
fc1_w = qdata[ptr:ptr+64*192].reshape(64, 192); ptr += 64*192
fc1_b = qdata[ptr:ptr+64]; ptr += 64
# fc2.weight (65,64)
fc2_w = qdata[ptr:ptr+65*64].reshape(65, 64); ptr += 65*64
fc2_b = qdata[ptr:ptr+65]; ptr += 65

print(f'解析权重: ptr={ptr}, 总={offset}')
assert ptr == offset, f'指针不匹配: {ptr} vs {offset}'

for i, idx in enumerate(val_indices):
    # 输入: [0,255] 整数
    img_uint8 = (X_val[idx] * 255).astype(np.int32)  # (32, 16)

    # Conv1 (8,1,3,3) + ReLU + Pool2
    h = conv_int_vectorized(img_uint8, conv1_w, conv1_b, do_relu=True, do_pool=True)
    # h: (8, 15, 7)

    # Conv2 (16,8,3,3) + ReLU + Pool2
    # conv_int_vectorized expects 2D input, so process each input channel
    h_combined = np.zeros((16, h.shape[1]-2, h.shape[2]-2), dtype=np.int32)
    for co in range(16):
        acc = np.zeros((h.shape[1]-2, h.shape[2]-2), dtype=np.int32)
        for ci in range(8):
            patch = h[ci]  # (15, 7)
            w_slice = conv2_w[co, ci]  # (3, 3)
            for r in range(h.shape[1]-2):
                for c in range(h.shape[2]-2):
                    acc[r, c] += np.sum(patch[r:r+3, c:c+3] * w_slice)
        h_combined[co] = acc + conv2_b[co]
    h_combined = h_combined >> 15
    h_combined = np.maximum(h_combined, 0).clip(0, 32767)
    # Pool2
    h_pool = np.zeros((16, 6, 2), dtype=np.int32)
    for co in range(16):
        for r in range(6):
            for c in range(2):
                h_pool[co, r, c] = np.max(h_combined[co, r*2:r*2+2, c*2:c*2+2])

    # Flatten (192,)
    h_flat = h_pool.ravel()

    # FC1 + ReLU
    h_fc1 = fc_int_vectorized(h_flat, fc1_w, fc1_b, do_relu=True)

    # FC2 (输出)
    h_fc2 = fc_int_vectorized(h_fc1, fc2_w, fc2_b, do_relu=False)

    pred = np.argmax(h_fc2)
    if pred == y_val[idx]:
        correct_int += 1

    if (i+1) % 100 == 0:
        print(f'  验证中: {i+1}/{len(val_indices)} 当前正确率={correct_int/(i+1)*100:.1f}%')

int_acc = correct_int / len(val_indices)

# 浮点推理对比
print(f'\n浮点推理评估...')
model.eval()
with torch.no_grad():
    val_out = model(X_val_t)
    val_pred = val_out.argmax(dim=1)
    float_acc = (val_pred == y_val_t).float().mean().item()

print(f'\n{"="*60}')
print(f'结果对比')
print(f'{"="*60}')
print(f'  浮点模型验证准确率: {float_acc*100:.2f}%')
print(f'  整数推理验证准确率: {int_acc*100:.2f}%')
print(f'  精度差距: {(float_acc-int_acc)*100:.2f}%')

# ========== 8. 测试char_0.bmp ==========
print(f'\n{"="*60}')
print(f'测试 char_0.bmp (湘)')
print(f'{"="*60}')

xiang_idx = classes.index('zh_xiang')
img_test = cv2.imread(r'D:\MATLAB\PIC\single_word_debug\char_0.bmp', cv2.IMREAD_GRAYSCALE)
print(f'原始图像: {img_test.shape}')

# 测试不同预处理方式
for label, img_proc in [
    ('直接缩放[0,255]', img_test),
    ('反转后缩放[0,255]', 255 - img_test),
]:
    img_small = cv2.resize(img_proc, (IMG_W, IMG_H)).astype(np.int32)  # (32, 16)

    # 整数推理
    h = conv_int_vectorized(img_small, conv1_w, conv1_b, True, True)
    h_combined = np.zeros((16, h.shape[1]-2, h.shape[2]-2), dtype=np.int32)
    for co in range(16):
        acc = np.zeros((h.shape[1]-2, h.shape[2]-2), dtype=np.int32)
        for ci in range(8):
            for r in range(h.shape[1]-2):
                for c in range(h.shape[2]-2):
                    acc[r, c] += np.sum(h[ci][r:r+3, c:c+3] * conv2_w[co, ci])
        h_combined[co] = acc + conv2_b[co]
    h_combined = h_combined >> 15
    h_combined = np.maximum(h_combined, 0).clip(0, 32767)
    h_pool = np.zeros((16, 6, 2), dtype=np.int32)
    for co in range(16):
        for r in range(6):
            for c in range(2):
                h_pool[co, r, c] = np.max(h_combined[co, r*2:r*2+2, c*2:c*2+2])

    h_flat = h_pool.ravel()
    h_fc1 = fc_int_vectorized(h_flat, fc1_w, fc1_b, True)
    h_fc2 = fc_int_vectorized(h_fc1, fc2_w, fc2_b, False)

    pred = np.argmax(h_fc2)
    top5 = np.argsort(h_fc2)[-5:][::-1]

    print(f'\n预处理: {label}')
    print(f'  预测: {classes[pred]} (idx={pred})')
    for rank, idx in enumerate(top5):
        print(f'    {rank+1}. {classes[idx]:10s} score={h_fc2[idx]:6d}')
    print(f'  zh_xiang(湘) score={h_fc2[xiang_idx]:6d}')

print(f'\n✅ 完成! 模型和权重已导出到 {OUTPUT_H} 和 {OUTPUT_BIN}')
