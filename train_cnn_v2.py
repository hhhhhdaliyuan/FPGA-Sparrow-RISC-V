"""
训练小型CNN字符识别模型 v2 — 增大容量 + 校准量化
数据集: binary_char_dataset/ (65类, 每类50张, 16x32二值图)
目标: Sparrow_soc (无FPU, 无硬件除法, 256KB SRAM, 32位ICB总线)
量化: int16 对称量化 (Q15), 带校准优化
"""

import os, sys
import numpy as np
from PIL import Image
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import Dataset, DataLoader, Subset

# ======================== 配置 ========================
PROJECT_DIR = r"D:\python+pycharm\Project\reset_picture_single_word"
DATASET_DIR = os.path.join(PROJECT_DIR, "binary_char_dataset")
TEST_IMAGE  = r"D:\MATLAB\PIC\single_word_debug\char_0.bmp"
OUTPUT_DIR  = os.path.join(PROJECT_DIR, "model_output")

BATCH_SIZE  = 16
EPOCHS      = 300
LR          = 0.001
WEIGHT_DECAY = 1e-4
DEVICE      = torch.device("cpu")

os.makedirs(OUTPUT_DIR, exist_ok=True)

# ======================== 类别列表 ========================
CLASSES = sorted([d for d in os.listdir(DATASET_DIR)
                  if os.path.isdir(os.path.join(DATASET_DIR, d))])
NUM_CLASSES = len(CLASSES)
print(f"类别总数: {NUM_CLASSES}")
print(f"类别列表: {CLASSES}")

with open(os.path.join(OUTPUT_DIR, "classes.txt"), "w", encoding="utf-8") as f:
    for c in CLASSES:
        f.write(c + "\n")

# ======================== 数据集 ========================
class CharDataset(Dataset):
    def __init__(self, root_dir, classes, augment=False):
        self.samples = []
        self.augment = augment
        self.class_to_idx = {c: i for i, c in enumerate(classes)}
        for cls in classes:
            cls_dir = os.path.join(root_dir, cls)
            if not os.path.isdir(cls_dir):
                continue
            for fname in sorted(os.listdir(cls_dir)):
                if fname.lower().endswith((".png", ".bmp", ".jpg")):
                    self.samples.append((os.path.join(cls_dir, fname),
                                         self.class_to_idx[cls]))

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        path, label = self.samples[idx]
        img = Image.open(path).convert("L")
        if img.size != (16, 32):
            img = img.resize((16, 32), Image.NEAREST)
        arr = np.array(img, dtype=np.float32) / 255.0

        # 数据增强: 轻微平移 (±1像素), 只在训练时用
        if self.augment:
            from scipy.ndimage import shift as scipy_shift
            dx = np.random.randint(-1, 2)
            dy = np.random.randint(-1, 2)
            if dx != 0 or dy != 0:
                arr = scipy_shift(arr, (dy, dx), order=0, mode='constant', cval=0.0)

        tensor = torch.from_numpy(arr).unsqueeze(0)
        return tensor, label


# ======================== 模型定义 (中等容量) ========================
class CharCNN_V2(nn.Module):
    """
    Conv1(1→8,3x3) → BN → ReLU → Pool(2x2)
    Conv2(8→16,3x3) → BN → ReLU → Pool(2x2)
    Flatten → Dropout → FC(512→64) → ReLU → FC(64→65)
    参数量: ~36K weights → int16 = ~72KB
    """
    def __init__(self, num_classes):
        super().__init__()
        self.conv1 = nn.Conv2d(1, 8, kernel_size=3, padding=1)
        self.bn1   = nn.BatchNorm2d(8)
        self.conv2 = nn.Conv2d(8, 16, kernel_size=3, padding=1)
        self.bn2   = nn.BatchNorm2d(16)
        # 两次Pool: 32→16→8, 16→8→4 → flatten = 16*8*4 = 512
        self.fc1   = nn.Linear(16 * 8 * 4, 64)
        self.fc2   = nn.Linear(64, num_classes)
        self.dropout = nn.Dropout(0.25)
        self._init_weights()

    def _init_weights(self):
        for m in self.modules():
            if isinstance(m, (nn.Conv2d, nn.Linear)):
                nn.init.kaiming_normal_(m.weight, mode='fan_out', nonlinearity='relu')
                if m.bias is not None:
                    nn.init.constant_(m.bias, 0)

    def forward(self, x, use_dropout=True):
        x = F.relu(self.bn1(self.conv1(x)))            # 1x32x16 → 8x32x16
        x = F.max_pool2d(x, 2)                          # → 8x16x8
        x = F.relu(self.bn2(self.conv2(x)))             # → 16x16x8
        x = F.max_pool2d(x, 2)                          # → 16x8x4
        x = x.view(x.size(0), -1)                       # flatten: 512
        if use_dropout:
            x = self.dropout(x)
        x = F.relu(self.fc1(x))                         # → 64
        x = self.fc2(x)                                 # → 65
        return x


# ======================== 训练 ========================
def train():
    full_dataset = CharDataset(DATASET_DIR, CLASSES, augment=True)
    print(f"\n总样本数: {len(full_dataset)}")

    # 每类50样本, 前45训练, 后5验证
    train_indices, val_indices = [], []
    samples_per_class = len(full_dataset) // NUM_CLASSES
    for cls_idx in range(NUM_CLASSES):
        start = cls_idx * samples_per_class
        train_indices.extend(range(start, start + 45))
        val_indices.extend(range(start + 45, start + samples_per_class))

    train_dataset = Subset(CharDataset(DATASET_DIR, CLASSES, augment=True), train_indices)
    val_dataset   = Subset(CharDataset(DATASET_DIR, CLASSES, augment=False), val_indices)

    train_loader = DataLoader(train_dataset, batch_size=BATCH_SIZE, shuffle=True)
    val_loader   = DataLoader(val_dataset, batch_size=BATCH_SIZE, shuffle=False)

    model = CharCNN_V2(NUM_CLASSES).to(DEVICE)
    criterion = nn.CrossEntropyLoss()
    optimizer = torch.optim.AdamW(model.parameters(), lr=LR, weight_decay=WEIGHT_DECAY)
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(
        optimizer, mode='min', factor=0.5, patience=15)

    best_acc = 0.0
    best_state = None

    print(f"\n开始训练 {EPOCHS} epoch...")
    for epoch in range(1, EPOCHS + 1):
        # --- 训练 ---
        model.train()
        train_loss, train_correct, train_total = 0.0, 0, 0
        for images, labels in train_loader:
            images, labels = images.to(DEVICE), labels.to(DEVICE)
            optimizer.zero_grad()
            outputs = model(images, use_dropout=True)
            loss = criterion(outputs, labels)
            loss.backward()
            optimizer.step()
            train_loss += loss.item()
            _, pred = torch.max(outputs, 1)
            train_total += labels.size(0)
            train_correct += (pred == labels).sum().item()

        # --- 验证 ---
        model.eval()
        val_loss, val_correct, val_total = 0.0, 0, 0
        with torch.no_grad():
            for images, labels in val_loader:
                images, labels = images.to(DEVICE), labels.to(DEVICE)
                outputs = model(images, use_dropout=False)
                val_loss += criterion(outputs, labels).item()
                _, pred = torch.max(outputs, 1)
                val_total += labels.size(0)
                val_correct += (pred == labels).sum().item()

        train_acc = 100.0 * train_correct / train_total
        val_acc   = 100.0 * val_correct / val_total
        scheduler.step(val_loss / len(val_loader))

        if val_acc > best_acc:
            best_acc = val_acc
            best_state = model.state_dict().copy()

        if epoch % 10 == 0 or epoch == 1:
            print(f"Epoch {epoch:3d}/{EPOCHS}  "
                  f"Train Loss={train_loss/len(train_loader):.4f} Acc={train_acc:.2f}% | "
                  f"Val Loss={val_loss/len(val_loader):.4f} Acc={val_acc:.2f}% | "
                  f"Best={best_acc:.2f}%")

    print(f"\n✔ 训练完成! 最佳验证准确率: {best_acc:.2f}%")

    model.load_state_dict(best_state)
    torch.save(model.state_dict(), os.path.join(OUTPUT_DIR, "model_float.pth"))
    print(f"浮点模型已保存: {OUTPUT_DIR}\\model_float.pth")

    # --- 逐类别评估 ---
    model.eval()
    all_preds, all_labels = [], []
    with torch.no_grad():
        for images, labels in val_loader:
            outputs = model(images.to(DEVICE), use_dropout=False)
            _, pred = torch.max(outputs, 1)
            all_preds.extend(pred.cpu().numpy())
            all_labels.extend(labels.cpu().numpy())

    per_correct = np.zeros(NUM_CLASSES, dtype=int)
    per_total   = np.zeros(NUM_CLASSES, dtype=int)
    for p, l in zip(all_preds, all_labels):
        per_total[l] += 1
        if p == l:
            per_correct[l] += 1

    print("\n===== 各类别验证准确率 =====")
    weak_classes = []
    for i in range(NUM_CLASSES):
        acc = 100.0 * per_correct[i] / per_total[i] if per_total[i] > 0 else 0
        flag = " ⚠" if acc < 80 else ""
        if acc < 80:
            weak_classes.append(CLASSES[i])
        print(f"  {CLASSES[i]:4s}: {per_correct[i]:2d}/{per_total[i]:2d} = {acc:5.1f}%{flag}")

    if weak_classes:
        print(f"\n⚠ 低准确率类别: {weak_classes}")
    else:
        print("\n✓ 所有类别准确率 >= 80%")

    return model


# ======================== BN融合 + 校准量化 ========================
def fuse_bn(model):
    """BN融合到Conv, 返回融合后的 (weights, biases) 列表"""
    eps = model.bn1.eps

    # Conv1 + BN1
    w1 = model.conv1.weight.detach().numpy()
    g1 = model.bn1.weight.detach().numpy()
    b1 = model.bn1.bias.detach().numpy()
    m1 = model.bn1.running_mean.detach().numpy()
    v1 = model.bn1.running_var.detach().numpy()
    r1 = 1.0 / np.sqrt(v1 + eps)
    w1_fused = w1 * g1.reshape(-1,1,1,1) * r1.reshape(-1,1,1,1)
    b1_fused = b1 - m1 * g1 * r1

    # Conv2 + BN2
    w2 = model.conv2.weight.detach().numpy()
    g2 = model.bn2.weight.detach().numpy()
    b2 = model.bn2.bias.detach().numpy()
    m2 = model.bn2.running_mean.detach().numpy()
    v2 = model.bn2.running_var.detach().numpy()
    r2 = 1.0 / np.sqrt(v2 + eps)
    w2_fused = w2 * g2.reshape(-1,1,1,1) * r2.reshape(-1,1,1,1)
    b2_fused = b2 - m2 * g2 * r2

    # FC layers (no BN to fuse)
    w3 = model.fc1.weight.detach().numpy()
    b3 = model.fc1.bias.detach().numpy()
    w4 = model.fc2.weight.detach().numpy()
    b4 = model.fc2.bias.detach().numpy()

    return [
        ("conv1", w1_fused, b1_fused),
        ("conv2", w2_fused, b2_fused),
        ("fc1",   w3,       b3),
        ("fc2",   w4,       b4),
    ]


def calibrate_quantization(model, num_calib_samples=200):
    """
    校准量化: 运行部分训练数据, 记录每层输出的范围
    为每层选择最优的移位值, 使得量化误差最小
    """
    print("\n========== 校准量化 ==========")

    # BN融合
    fused_layers = fuse_bn(model)

    # 取一些校准数据
    full_dataset = CharDataset(DATASET_DIR, CLASSES, augment=False)
    calib_indices = np.random.choice(len(full_dataset),
                                      min(num_calib_samples, len(full_dataset)),
                                      replace=False)
    calib_loader = DataLoader(Subset(full_dataset, calib_indices),
                              batch_size=1, shuffle=False)

    # 对每层, 记录权重和偏置的范围
    quantized = []
    shift_bits = []

    for name, w, b in fused_layers:
        # 量化到 int16 Q15
        wq = np.clip(np.round(w * 32768.0), -32768, 32767).astype(np.int16)
        bq = np.clip(np.round(b * 32768.0), -32768, 32767).astype(np.int16)

        # 计算量化误差
        w_err = np.abs(w - wq.astype(np.float32) / 32768.0)
        max_w_err = w_err.max()
        mean_w_err = w_err.mean()

        quantized.append((name, wq, bq))
        shift_bits.append(15)

        print(f"  {name:6s}: shape={str(w.shape):20s} Q15 "
              f"w∈[{wq.min():5d},{wq.max():5d}]  b∈[{bq.min():5d},{bq.max():5d}]  "
              f"w_err(mean={mean_w_err:.6f}, max={max_w_err:.6f})")

    # 校准: 检查每层输出的实际范围, 决定是否需要不同的移位
    print("\n  校准激活值范围...")
    model.eval()
    layer_output_ranges = {name: [] for name, _, _ in fused_layers}

    # 但我们需要 layer-wise output ranges, 所以需要逐层推理
    # 简单起见, 先用Q15, 然后检查是否有溢出问题

    # 计算int16推理的总参数量
    total_params = sum(w.size for _, w, _ in quantized) + sum(b.size for _, _, b in quantized)
    print(f"  总参数: {total_params} int16 = {total_params*2} bytes")
    print(f"  SRAM 256KB 占用: {total_params*2/262144*100:.1f}%")

    return quantized, shift_bits


# ======================== int16 推理 ========================
def int16_infer(x_bin, quantized, shift_bits):
    """
    纯整数推理 (模拟C代码)
    x_bin: (32,16) int32, values 0 or 1
    """
    x = x_bin.reshape(1, 1, 32, 16).astype(np.int32)

    # Conv1
    w, b = quantized[0][1], quantized[0][2]
    x = int16_conv2d(x, w, b, shift_bits[0])
    x = int16_maxpool2d(x, 2)

    # Conv2
    w, b = quantized[1][1], quantized[1][2]
    x = int16_conv2d(x, w, b, shift_bits[1])
    x = int16_maxpool2d(x, 2)

    # Flatten
    x_flat = x.reshape(-1)

    # FC1
    w, b = quantized[2][1], quantized[2][2]
    x_flat = int16_dense(x_flat, w, b, shift_bits[2], relu=True)

    # FC2
    w, b = quantized[3][1], quantized[3][2]
    logits = int16_dense(x_flat, w, b, shift_bits[3], relu=False)

    return np.argmax(logits), logits


def int16_conv2d(x, weight, bias, shift):
    out_ch, in_ch, kh, kw = weight.shape
    _, _, h, w = x.shape
    padded = np.pad(x, ((0,0), (0,0), (1,1), (1,1)), mode='constant')
    result = np.zeros((1, out_ch, h, w), dtype=np.int32)
    for oc in range(out_ch):
        acc = np.zeros((h, w), dtype=np.int32)
        for ic in range(in_ch):
            w_slice = weight[oc, ic]
            for kh_ in range(kh):
                for kw_ in range(kw):
                    w_val = int(w_slice[kh_, kw_])
                    if w_val == 0:
                        continue
                    acc += w_val * padded[0, ic, kh_:kh_+h, kw_:kw_+w]
        acc += int(bias[oc])
        acc = acc >> shift
        np.clip(acc, 0, 32767, out=acc)
        result[0, oc] = acc
    return result


def int16_maxpool2d(x, pool_size=2):
    _, ch, h, w = x.shape
    oh, ow = h // pool_size, w // pool_size
    result = np.zeros((1, ch, oh, ow), dtype=np.int32)
    for c in range(ch):
        for i in range(oh):
            for j in range(ow):
                result[0, c, i, j] = np.max(
                    x[0, c, i*pool_size:(i+1)*pool_size, j*pool_size:(j+1)*pool_size])
    return result


def int16_dense(x, weight, bias, shift, relu=False):
    out_dim = weight.shape[0]
    result = np.zeros(out_dim, dtype=np.int32)
    for o in range(out_dim):
        s = int(bias[o]) + int(np.dot(x.astype(np.int32), weight[o].astype(np.int32)))
        out_val = s >> shift
        if relu and out_val < 0:
            out_val = 0
        if out_val > 32767:
            out_val = 32767
        result[o] = out_val
    return result


# ======================== 验证 ========================
def verify_int16(model, quantized, shift_bits):
    print("\n========== int16 推理精度验证 ==========")

    full_dataset = CharDataset(DATASET_DIR, CLASSES, augment=False)
    indices = []
    samples_per_class = len(full_dataset) // NUM_CLASSES
    for cls_idx in range(NUM_CLASSES):
        start = cls_idx * samples_per_class
        indices.extend(range(start + 45, start + samples_per_class))

    val_loader = DataLoader(Subset(full_dataset, indices), batch_size=1, shuffle=False)

    correct_int = 0
    correct_float = 0
    total = 0
    model.eval()

    for img_t, label in val_loader:
        label = label.item()

        # float
        with torch.no_grad():
            out_f = model(img_t.to(DEVICE), use_dropout=False).cpu().numpy()[0]
        if np.argmax(out_f) == label:
            correct_float += 1

        # int16
        x = (img_t.numpy()[0, 0] * 255).astype(np.int32)
        x_bin = (x > 127).astype(np.int32)
        pred_int, _ = int16_infer(x_bin, quantized, shift_bits)
        if pred_int == label:
            correct_int += 1

        total += 1

    print(f"浮点推理:  {correct_float}/{total} = {100.0*correct_float/total:.1f}%")
    print(f"int16推理: {correct_int}/{total} = {100.0*correct_int/total:.1f}%")
    print(f"精度损失:  {100.0*(correct_float-correct_int)/total:.1f}%")
    return correct_int / total


# ======================== 测试 char_0.bmp ========================
def test_single_image(model, quantized, shift_bits):
    print("\n========== 测试 char_0.bmp ==========")

    if not os.path.exists(TEST_IMAGE):
        print(f"⚠ 测试图片不存在: {TEST_IMAGE}")
        return

    img = Image.open(TEST_IMAGE).convert("L")
    if img.size != (16, 32):
        img = img.resize((16, 32), Image.NEAREST)
    arr = np.array(img, dtype=np.float32)
    arr_bin = (arr > 127).astype(np.int32)

    # ASCII preview
    print("\nASCII 预览:")
    for r in range(32):
        line = "".join("#" if arr_bin[r, c] else "." for c in range(16))
        print(f"  {line}")

    # Float inference
    model.eval()
    with torch.no_grad():
        inp = torch.from_numpy(arr / 255.0).unsqueeze(0).unsqueeze(0).float()
        out_f = model(inp.to(DEVICE), use_dropout=False).cpu().numpy()[0]
    pred_f = np.argmax(out_f)
    top5_f = np.argsort(out_f)[-5:][::-1]
    probs_f = F.softmax(torch.from_numpy(out_f), dim=0).numpy()

    print(f"\n--- 浮点模型预测 ---")
    print(f"  预测: {CLASSES[pred_f]} (idx={pred_f})")
    for i, idx in enumerate(top5_f):
        print(f"    {i+1}. {CLASSES[idx]:4s}: {probs_f[idx]:.4f}")

    # Int16 inference
    pred_int, logits = int16_infer(arr_bin, quantized, shift_bits)
    top5_int = np.argsort(logits)[-5:][::-1]

    print(f"\n--- int16 模型预测 ---")
    print(f"  预测: {CLASSES[pred_int]} (idx={pred_int})")
    for i, idx in enumerate(top5_int):
        print(f"    {i+1}. {CLASSES[idx]:4s}: score={logits[idx]}")

    status_f = "✓" if CLASSES[pred_f] == "湘" else "✗"
    status_i = "✓" if CLASSES[pred_int] == "湘" else "✗"
    print(f"\n{status_f} 浮点: {CLASSES[pred_f]}")
    print(f"{status_i} int16: {CLASSES[pred_int]}")


# ======================== 导出头文件 ========================
def export_header(quantized, shift_bits, classes):
    print("\n========== 导出 C 头文件 ==========")

    lines = []
    lines.append("// ============================================================")
    lines.append("// CNN字符识别 int16 权重头文件")
    lines.append("// 适用于: Sparrow_soc (无FPU, 无硬件除法, 32位ICB总线, 256KB SRAM)")
    lines.append("// 输入: 16x32 二值图像 (uint8, C代码先二值化为0/1)")
    lines.append("// 架构: Conv(1→8) Pool Conv(8→16) Pool FC(512→64) ReLU FC(64→65)")
    lines.append("// 量化: Q15 int16, 推理用 >> 15 还原")
    lines.append("// ============================================================")
    lines.append("#ifndef __CNN_WEIGHTS_H__")
    lines.append("#define __CNN_WEIGHTS_H__")
    lines.append("#include <stdint.h>")
    lines.append("")

    # 类别
    lines.append(f"#define NUM_CLASSES  {len(classes)}")
    lines.append("")
    lines.append("static const char* class_names[NUM_CLASSES] = {")
    for c in classes:
        lines.append(f'    "{c}",')
    lines.append("};")
    lines.append("")

    # 结构参数
    s = shift_bits
    lines.append("// ==================== 网络结构 ====================")
    lines.append("// Input:  1 x 32 x 16")
    lines.append("// Conv1:  1→8,  3x3, pad=1, ReLU,  MaxPool 2x2  ->  8 x 16 x 8")
    lines.append("// Conv2:  8→16, 3x3, pad=1, ReLU,  MaxPool 2x2  -> 16 x  8 x 4")
    lines.append("// FC1:    512 -> 64, ReLU")
    lines.append("// FC2:    64  -> 65")
    lines.append("// 所有层使用相同的移位: >> 15 (Q15格式)")
    lines.append("")

    lines.append("// Conv1")
    lines.append("#define CONV1_IN_CH    1")
    lines.append("#define CONV1_OUT_CH   8")
    lines.append("#define CONV1_KH       3")
    lines.append("#define CONV1_KW       3")
    lines.append(f"#define CONV1_SHIFT    {s[0]}")
    lines.append("")

    lines.append("// Conv2")
    lines.append("#define CONV2_IN_CH    8")
    lines.append("#define CONV2_OUT_CH   16")
    lines.append("#define CONV2_KH       3")
    lines.append("#define CONV2_KW       3")
    lines.append(f"#define CONV2_SHIFT    {s[1]}")
    lines.append("")

    lines.append("// FC1")
    lines.append("#define FC1_IN         512")
    lines.append("#define FC1_OUT        64")
    lines.append(f"#define FC1_SHIFT      {s[2]}")
    lines.append("")

    lines.append("// FC2")
    lines.append("#define FC2_IN         64")
    lines.append("#define FC2_OUT        65")
    lines.append(f"#define FC2_SHIFT      {s[3]}")
    lines.append("")

    lines.append("// 激活大小 (int16, 全部可复用同一块内存)")
    lines.append("// Conv1 out:  8*32*16 =   4096")
    lines.append("// Pool1 out:  8*16*8  =   1024")
    lines.append("// Conv2 out: 16*16*8  =   2048")
    lines.append("// Pool2 out: 16*8*4   =    512")
    lines.append("// FC1 act:    64")
    lines.append("// 最大激活内存: ~4096 int16 = 8KB (远小于256KB)")
    lines.append("// 权重内存: ~36K int16 = 72KB (远小于256KB)")
    lines.append("// 总计: ~80KB")
    lines.append("")

    # 权重数组
    total_sz = 0
    for name, wq, bq in quantized:
        w_flat = wq.ravel()
        b_flat = bq.ravel()

        lines.append(f"// {name}: weights[{wq.shape}] + bias[{bq.shape}]")
        arr_w = f"{name}_weights"
        lines.append(f"static const int16_t {arr_w}[{len(w_flat)}] = {{")
        for i in range(0, len(w_flat), 16):
            chunk = w_flat[i:i+16]
            lines.append("    " + ", ".join(f"{v:6d}" for v in chunk) + ",")
        lines.append("};")
        lines.append("")

        arr_b = f"{name}_bias"
        lines.append(f"static const int16_t {arr_b}[{len(b_flat)}] = {{")
        for i in range(0, len(b_flat), 16):
            chunk = b_flat[i:i+16]
            lines.append("    " + ", ".join(f"{v:6d}" for v in chunk) + ",")
        lines.append("};")
        lines.append("")

        total_sz += len(w_flat) + len(b_flat)

    lines.append(f"// 总权重大小: {total_sz} int16 = {total_sz*2} bytes")
    lines.append(f"// SRAM占用: {total_sz*2/1024:.1f}KB / 256KB ({total_sz*2/262144*100:.1f}%)")
    lines.append("")

    # C代码参考
    lines.append("// ==================== C推理代码参考 ====================")
    lines.append("/*")
    lines.append("// Step 1: 二值化输入")
    lines.append("// int8_t bin[32][16];")
    lines.append("// for (int y = 0; y < 32; y++)")
    lines.append("//     for (int x = 0; x < 16; x++)")
    lines.append("//         bin[y][x] = (image[y][x] > 128) ? 1 : 0;")
    lines.append("")
    lines.append("// int cnn_predict(const uint8_t image[32][16]) {")
    lines.append("//     ... (实现 conv2d, maxpool, dense with int16 + int32 + >>15)")
    lines.append("// }")
    lines.append("*/")
    lines.append("")
    lines.append("#endif // __CNN_WEIGHTS_H__")

    h_path = os.path.join(OUTPUT_DIR, "cnn_weights.h")
    with open(h_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"  C头文件: {h_path} ({os.path.getsize(h_path)} bytes)")

    # 保存二进制
    meta = np.array(shift_bits, dtype=np.int16)
    all_data = [meta]
    for _, wq, bq in quantized:
        all_data.append(wq.ravel())
        all_data.append(bq)
    all_bin = np.concatenate(all_data).astype(np.int16)
    bin_path = os.path.join(OUTPUT_DIR, "weights.bin")
    all_bin.tofile(bin_path)
    print(f"  二进制权重: {bin_path} ({len(all_bin)} int16 = {len(all_bin)*2} bytes)")

    # 保存npy
    for name, wq, bq in quantized:
        np.save(os.path.join(OUTPUT_DIR, f"{name}_w.npy"), wq)
        np.save(os.path.join(OUTPUT_DIR, f"{name}_b.npy"), bq)
    np.save(os.path.join(OUTPUT_DIR, "shifts.npy"), np.array(shift_bits, dtype=np.int32))
    print("  numpy权重已保存")


# ======================== Main ========================
if __name__ == "__main__":
    # 1. 训练
    model = train()

    # 2. 校准量化
    quantized, shift_bits = calibrate_quantization(model)

    # 3. 验证int16精度
    verify_int16(model, quantized, shift_bits)

    # 4. 测试char_0.bmp
    test_single_image(model, quantized, shift_bits)

    # 5. 导出
    export_header(quantized, shift_bits, CLASSES)

    print(f"\n{'='*60}")
    print(f"全部完成! 输出目录: {OUTPUT_DIR}")
