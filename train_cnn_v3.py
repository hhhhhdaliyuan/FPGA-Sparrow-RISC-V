"""
训练小型CNN字符识别模型 v3 — 逐层校准量化
数据集: binary_char_dataset/ (65类, 每类50张, 16x32二值图)
目标: Sparrow_soc (无FPU, 无硬件除法, 256KB SRAM, 32位ICB总线)
量化: 逐层int16校准量化 (每层独立weight_shift + out_shift, 含层间重量化)

v3改进:
  1. 逐层校准量化替代统一Q15 — 修复权重>1.0被裁剪问题
  2. 基于实际激活值范围选择out_shift — 防止int16溢出
  3. 层间重量化 (requantize) — 正确处理不同层间的格式转换
  4. 更激进的数据增强 — 提高泛化能力
  5. 使用LANCZOS缩放测试图像 — 改善大图缩放质量
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

BATCH_SIZE   = 16
EPOCHS       = 500
LR           = 0.001
WEIGHT_DECAY = 5e-5
DEVICE       = torch.device("cpu")

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


# ======================== 数据集 (带增强) ========================
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

        if self.augment:
            arr = self._augment(arr)

        tensor = torch.from_numpy(arr).unsqueeze(0)
        return tensor, label

    def _augment(self, arr):
        """数据增强: 随机平移±1, 随机笔画腐蚀, 随机噪声"""
        h, w = arr.shape
        # 随机平移 (±1 像素)
        dx = np.random.randint(-1, 2)
        dy = np.random.randint(-1, 2)
        if dx != 0 or dy != 0:
            arr_aug = np.zeros_like(arr)
            sy, sx = max(0, dy), max(0, dx)
            ey, ex = min(h, h+dy), min(w, w+dx)
            arr_aug[sy:ey, sx:ex] = arr[max(0,-dy):min(h,h-dy), max(0,-dx):min(w,w-dx)]
            arr = arr_aug

        # 随机笔画腐蚀 (模拟测试图里的笔画断裂)
        if np.random.rand() < 0.3:
            mask = arr > 0.5
            peel = np.random.rand(*arr.shape) < 0.08
            arr[mask & peel] = 0.0

        # 随机椒盐噪声
        if np.random.rand() < 0.3:
            sp = np.random.rand(*arr.shape) < 0.02
            arr[sp] = 1.0 - arr[sp]

        return arr


# ======================== 模型定义 (中等容量) ========================
class CharCNN_V2(nn.Module):
    """
    Conv1(1→8,3x3) → BN → ReLU → Pool(2x2)
    Conv2(8→16,3x3) → BN → ReLU → Pool(2x2)
    Flatten → Dropout → FC(512→64) → ReLU → FC(64→65)
    参数量: ~36K
    """
    def __init__(self, num_classes):
        super().__init__()
        self.conv1 = nn.Conv2d(1, 8, kernel_size=3, padding=1)
        self.bn1   = nn.BatchNorm2d(8)
        self.conv2 = nn.Conv2d(8, 16, kernel_size=3, padding=1)
        self.bn2   = nn.BatchNorm2d(16)
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


# ======================== BN融合 ========================
def fuse_bn(model):
    """BN融合到Conv, 返回浮点权重列表"""
    eps = model.bn1.eps

    # Conv1 + BN1
    w1 = model.conv1.weight.detach().numpy()
    g1 = model.bn1.weight.detach().numpy()
    b1 = model.bn1.bias.detach().numpy()
    m1 = model.bn1.running_mean.detach().numpy()
    v1 = model.bn1.running_var.detach().numpy()
    r1 = 1.0 / np.sqrt(v1 + eps)
    w1_f = w1 * g1.reshape(-1,1,1,1) * r1.reshape(-1,1,1,1)
    b1_f = b1 - m1 * g1 * r1

    # Conv2 + BN2
    w2 = model.conv2.weight.detach().numpy()
    g2 = model.bn2.weight.detach().numpy()
    b2 = model.bn2.bias.detach().numpy()
    m2 = model.bn2.running_mean.detach().numpy()
    v2 = model.bn2.running_var.detach().numpy()
    r2 = 1.0 / np.sqrt(v2 + eps)
    w2_f = w2 * g2.reshape(-1,1,1,1) * r2.reshape(-1,1,1,1)
    b2_f = b2 - m2 * g2 * r2

    # FC layers (no BN)
    w3 = model.fc1.weight.detach().numpy()
    b3 = model.fc1.bias.detach().numpy()
    w4 = model.fc2.weight.detach().numpy()
    b4 = model.fc2.bias.detach().numpy()

    return [
        ("conv1", w1_f, b1_f),
        ("conv2", w2_f, b2_f),
        ("fc1",   w3,   b3),
        ("fc2",   w4,   b4),
    ]


# ======================== 逐层校准量化 ========================
def calibrate_quantization(model, num_calib_samples=200):
    """
    逐层校准量化:
    1. 根据权重范围确定每层的 weight_shift (power-of-2)
    2. 根据激活值范围确定每层的 out_shift
    3. 生成量化权重 + 层间重量化参数
    """
    print("\n========== 逐层校准量化 ==========")

    model.eval()
    fused = fuse_bn(model)

    # --- Step 1: 基于权重范围确定 weight_shift ---
    print("\n[Step 1] 权重量化 (weight_shift):")
    layer_configs = []
    for name, w, b in fused:
        max_w = max(abs(w.min()), abs(w.max())) + 1e-10
        weight_shift = int(np.floor(np.log2(32767.0 / max_w)))
        weight_shift = max(0, min(weight_shift, 30))
        layer_configs.append((name, w, b, weight_shift))

        wq = np.clip(np.round(w * (2**weight_shift)), -32768, 32767).astype(np.int16)
        bq = np.clip(np.round(b * (2**weight_shift)), -32768, 32767).astype(np.int16)
        print(f"  {name:6s}: max|w|={max_w:.4f}  weight_shift={weight_shift:2d}  "
              f"wq[{wq.min():6d},{wq.max():6d}]  bq[{bq.min():6d},{bq.max():6d}]")

    # --- Step 2: 基于激活统计确定 out_shift ---
    print("\n[Step 2] 激活量化校准 (out_shift):")
    dataset = CharDataset(DATASET_DIR, CLASSES, augment=False)
    calib_indices = np.random.choice(len(dataset),
                                      min(num_calib_samples, len(dataset)),
                                      replace=False)
    calib_loader = DataLoader(Subset(dataset, calib_indices),
                              batch_size=1, shuffle=False)

    all_act_max = {"conv1": [], "conv2": [], "fc1": [], "fc2_out": []}

    with torch.no_grad():
        for img_t, _ in calib_loader:
            x = F.relu(model.bn1(model.conv1(img_t)))
            all_act_max["conv1"].append(x.max().item())

            x = F.max_pool2d(x, 2)
            x = F.relu(model.bn2(model.conv2(x)))
            all_act_max["conv2"].append(x.max().item())

            x = F.max_pool2d(x, 2)
            x = x.view(x.size(0), -1)
            x = F.relu(model.fc1(x))
            all_act_max["fc1"].append(x.max().item())

            x = model.fc2(x)
            all_act_max["fc2_out"].extend(x[0].numpy().tolist())

    OUT_SHIFT = {}
    for name in ["conv1", "conv2", "fc1"]:
        max_val = max(all_act_max[name])
        if max_val < 1e-10:
            max_val = 1.0
        shift = int(np.floor(np.log2(32767.0 / max_val)))
        shift = max(0, min(shift, 30))
        OUT_SHIFT[name] = shift
        print(f"  {name:6s}: max_act={max_val:.3f}  out_shift={shift:2d}  "
              f"max_int16={int(max_val*2**shift)}")

    # fc2 (输出层)
    fc2_max_abs = max(abs(min(all_act_max["fc2_out"])),
                       abs(max(all_act_max["fc2_out"])), 1.0)
    shift = int(np.floor(np.log2(32767.0 / fc2_max_abs)))
    shift = max(0, min(shift, 30))
    OUT_SHIFT["fc2"] = shift
    print(f"  {'fc2':6s}: max|act|={fc2_max_abs:.3f}  out_shift={shift:2d}  "
          f"max_int16={int(fc2_max_abs*2**shift)}")

    # --- Step 3: 生成量化权重 + 层间重量化参数 ---
    print("\n[Step 3] 量化参数:")
    quantized = []
    shift_info = {}

    for name, w, b, w_shift in layer_configs:
        out_shift = OUT_SHIFT.get(name, 15)
        wq = np.clip(np.round(w * (2**w_shift)), -32768, 32767).astype(np.int16)
        bq = np.clip(np.round(b * (2**w_shift)), -32768, 32767).astype(np.int16)
        quantized.append((name, wq, bq))

        # 前一层输出格式 (输入层为0)
        prev_shifts = {
            "conv1": 0,
            "conv2": OUT_SHIFT["conv1"],
            "fc1": OUT_SHIFT["conv2"],
            "fc2": OUT_SHIFT["fc1"],
        }
        prev_out_shift = prev_shifts.get(name, 0)
        shift_amount = prev_out_shift + w_shift - out_shift

        if shift_amount < 0:
            print(f"  ⚠ {name}: shift_amount={shift_amount} < 0! 使用0")
            shift_amount = 0

        shift_info[name] = {
            "w_shift": w_shift,
            "out_shift": out_shift,
            "prev_out_shift": prev_out_shift,
            "shift_amount": shift_amount,
        }

        print(f"  {name:6s}: prev={prev_out_shift:2d}+w={w_shift:2d}-out={out_shift:2d}"
              f" = >>{shift_amount:2d}  | wq[{wq.min():6d},{wq.max():6d}]")

    # --- Step 4: 验证不溢出 ---
    print("\n[Step 4] 溢出检查:")
    for name, wq, bq in quantized:
        info = shift_info[name]
        n_mac = len(wq.ravel())
        max_wq = int(np.abs(wq).max()) or 1

        if name == "conv1":
            max_input = 1
        else:
            prev_name = {"conv2": "conv1", "fc1": "conv2", "fc2": "fc1"}[name]
            max_act = max(all_act_max[prev_name])
            max_input = int(max_act * (2 ** shift_info[prev_name]["out_shift"]))
            max_input = max(1, max_input)

        est_acc = n_mac * max_input * max_wq + int(np.abs(bq).max())
        safe = est_acc < 2**31
        print(f"  {name}: ~{n_mac} MACs * in={max_input} * wq={max_wq} "
              f"+ bias={int(np.abs(bq).max())} = {est_acc}  "
              f"{'OK' if safe else 'OVERFLOW!'}")

    return quantized, shift_info


# ======================== 训练 ========================
def train():
    dataset = CharDataset(DATASET_DIR, CLASSES, augment=True)
    print(f"\n总样本数: {len(dataset)}")

    samples_per_class = len(dataset) // NUM_CLASSES
    train_indices, val_indices = [], []
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
        optimizer, mode='min', factor=0.5, patience=20)

    best_acc = 0.0
    best_state = None

    print(f"\n开始训练 {EPOCHS} epoch...")
    for epoch in range(1, EPOCHS + 1):
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
            lr_now = optimizer.param_groups[0]['lr']
            print(f"Epoch {epoch:4d}/{EPOCHS}  "
                  f"Train={train_acc:.1f}%  Val={val_acc:.1f}%  Best={best_acc:.1f}%  "
                  f"LR={lr_now:.6f}")

    print(f"\n完成! 最佳验证准确率: {best_acc:.2f}%")

    model.load_state_dict(best_state)
    torch.save(model.state_dict(), os.path.join(OUTPUT_DIR, "model_float.pth"))
    print(f"浮点模型已保存")

    # 逐类别评估
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
        flag = " W" if acc < 80 else ""
        if acc < 80:
            weak_classes.append(CLASSES[i])
        print(f"  {CLASSES[i]:4s}: {per_correct[i]:2d}/{per_total[i]:2d} = {acc:5.1f}%{flag}")

    if weak_classes:
        print(f"\nW 低准确率类别: {weak_classes}")
    else:
        print("\n所有类别准确率 >= 80%")

    return model


# ======================== int16 推理 (逐层重量化) ========================
def int16_infer(x_bin, quantized, shift_info):
    x = x_bin.reshape(1, 1, 32, 16).astype(np.int32)

    # Conv1
    name = "conv1"
    w, b = quantized[0][1], quantized[0][2]
    x = int16_conv2d(x, w, b, shift_info[name]["shift_amount"])
    x = int16_maxpool2d(x, 2)

    # Conv2
    name = "conv2"
    w, b = quantized[1][1], quantized[1][2]
    x = int16_conv2d(x, w, b, shift_info[name]["shift_amount"])
    x = int16_maxpool2d(x, 2)

    # Flatten + FC1
    x_flat = x.reshape(-1)
    name = "fc1"
    w, b = quantized[2][1], quantized[2][2]
    x_flat = int16_dense(x_flat, w, b, shift_info[name]["shift_amount"], relu=True)

    # FC2
    name = "fc2"
    w, b = quantized[3][1], quantized[3][2]
    logits = int16_dense(x_flat, w, b, shift_info[name]["shift_amount"], relu=False)

    return int(np.argmax(logits)), logits


def int16_conv2d(x, weight, bias, shift_amount):
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
        if shift_amount > 0:
            acc = acc >> shift_amount
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


def int16_dense(x, weight, bias, shift_amount, relu=False):
    out_dim = weight.shape[0]
    result = np.zeros(out_dim, dtype=np.int32)
    for o in range(out_dim):
        s = int(bias[o]) + int(np.dot(x.astype(np.int32), weight[o].astype(np.int32)))
        if shift_amount > 0:
            s = s >> shift_amount
        if relu and s < 0:
            s = 0
        if s > 32767:
            s = 32767
        result[o] = s
    return result


# ======================== 验证 ========================
def verify_int16(model, quantized, shift_info):
    print("\n========== int16 推理精度验证 ==========")

    dataset = CharDataset(DATASET_DIR, CLASSES, augment=False)
    val_indices = []
    samples_per_class = len(dataset) // NUM_CLASSES
    for cls_idx in range(NUM_CLASSES):
        start = cls_idx * samples_per_class
        val_indices.extend(range(start + 45, start + samples_per_class))

    val_loader = DataLoader(Subset(dataset, val_indices), batch_size=1, shuffle=False)

    correct_int = 0
    correct_float = 0
    total = 0
    model.eval()

    for img_t, label in val_loader:
        label = label.item()

        with torch.no_grad():
            out_f = model(img_t.to(DEVICE), use_dropout=False).cpu().numpy()[0]
        if np.argmax(out_f) == label:
            correct_float += 1

        x = (img_t.numpy()[0, 0] * 255).astype(np.int32)
        x_bin = (x > 127).astype(np.int32)
        pred_int, _ = int16_infer(x_bin, quantized, shift_info)
        if pred_int == label:
            correct_int += 1
        total += 1

    print(f"浮点推理:  {correct_float}/{total} = {100.0*correct_float/total:.1f}%")
    print(f"int16推理: {correct_int}/{total} = {100.0*correct_int/total:.1f}%")
    print(f"精度损失:  {100.0*(correct_float-correct_int)/total:.1f}%")
    return correct_int / total


# ======================== 测试 char_0.bmp ========================
def test_single_image(model, quantized, shift_info):
    print("\n========== 测试 char_0.bmp (期望: 湘) ==========")

    if not os.path.exists(TEST_IMAGE):
        print(f"W 测试图片不存在: {TEST_IMAGE}")
        return

    img = Image.open(TEST_IMAGE).convert("L")
    print(f"原始图像: {img.size}")

    if img.size != (16, 32):
        img = img.resize((16, 32), Image.LANCZOS)
    arr = np.array(img, dtype=np.float32)
    arr_bin = (arr > 127).astype(np.int32)

    print("\nASCII 预览 (16x32):")
    for r in range(32):
        line = "".join("#" if arr_bin[r, c] else "." for c in range(16))
        print(f"  {line}")

    # Float
    model.eval()
    with torch.no_grad():
        inp = torch.from_numpy(arr / 255.0).unsqueeze(0).unsqueeze(0).float()
        out_f = model(inp.to(DEVICE), use_dropout=False).cpu().numpy()[0]
        probs_f = F.softmax(torch.from_numpy(out_f), dim=0).numpy()
    pred_f = np.argmax(out_f)
    top5_f = np.argsort(out_f)[-5:][::-1]

    print(f"\n--- 浮点模型预测 ---")
    print(f"  预测: {CLASSES[pred_f]} (idx={pred_f})  "
          f"{'OK' if CLASSES[pred_f]=='湘' else 'WRONG'}")
    for i, idx in enumerate(top5_f):
        print(f"    {i+1}. {CLASSES[idx]:4s}: {probs_f[idx]:.4f}")

    # Int16
    pred_int, logits_int = int16_infer(arr_bin, quantized, shift_info)
    top5_int = np.argsort(logits_int)[-5:][::-1]

    print(f"\n--- int16 模型预测 ---")
    print(f"  预测: {CLASSES[pred_int]} (idx={pred_int})  "
          f"{'OK' if CLASSES[pred_int]=='湘' else 'WRONG'}")
    for i, idx in enumerate(top5_int):
        print(f"    {i+1}. {CLASSES[idx]:4s}: score={logits_int[idx]}")


# ======================== 导出头文件 ========================
def export_header(quantized, shift_info, classes):
    print("\n========== 导出 C 头文件 ==========")

    lines = []
    lines.append("// ============================================================")
    lines.append("// CNN字符识别 int16 权重头文件 (v3 — per-layer quant)")
    lines.append("// Target: Sparrow_soc (no FPU, no HW divide, 32-bit ICB, 256KB SRAM)")
    lines.append("// Input: 16x32 binary image (0/1)")
    lines.append("// Arch: Conv(1->8) Pool Conv(8->16) Pool FC(512->64) ReLU FC(64->65)")
    lines.append("// Quant: per-layer int16 with inter-layer requantization")
    lines.append("// ============================================================")
    lines.append("#ifndef __CNN_WEIGHTS_H__")
    lines.append("#define __CNN_WEIGHTS_H__")
    lines.append("#include <stdint.h>")
    lines.append("")

    lines.append(f"#define NUM_CLASSES  {len(classes)}")
    lines.append("")
    lines.append("static const char* class_names[NUM_CLASSES] = {")
    for c in classes:
        lines.append(f'    "{c}",')
    lines.append("};")
    lines.append("")

    lines.append("// Layer config: shift_amount = prev_out_shift + w_shift - out_shift")
    lines.append("// Conv1 (input is 0/1, prev_out_shift=0)")
    s = shift_info["conv1"]
    lines.append("#define CONV1_IN_CH     1")
    lines.append("#define CONV1_OUT_CH    8")
    lines.append("#define CONV1_KH        3")
    lines.append("#define CONV1_KW        3")
    lines.append(f"#define CONV1_W_SHIFT   {s['w_shift']}")
    lines.append(f"#define CONV1_OUT_SHIFT {s['out_shift']}")
    lines.append(f"#define CONV1_SHIFT_AMT {s['shift_amount']}")
    lines.append("")

    s = shift_info["conv2"]
    lines.append("// Conv2")
    lines.append("#define CONV2_IN_CH     8")
    lines.append("#define CONV2_OUT_CH    16")
    lines.append("#define CONV2_KH        3")
    lines.append("#define CONV2_KW        3")
    lines.append(f"#define CONV2_W_SHIFT   {s['w_shift']}")
    lines.append(f"#define CONV2_OUT_SHIFT {s['out_shift']}")
    lines.append(f"#define CONV2_SHIFT_AMT {s['shift_amount']}")
    lines.append("")

    s = shift_info["fc1"]
    lines.append("// FC1 (512 -> 64)")
    lines.append("#define FC1_IN          512")
    lines.append("#define FC1_OUT         64")
    lines.append(f"#define FC1_W_SHIFT     {s['w_shift']}")
    lines.append(f"#define FC1_OUT_SHIFT   {s['out_shift']}")
    lines.append(f"#define FC1_SHIFT_AMT   {s['shift_amount']}")
    lines.append("")

    s = shift_info["fc2"]
    lines.append("// FC2 (64 -> 65, output layer)")
    lines.append("#define FC2_IN          64")
    lines.append("#define FC2_OUT         65")
    lines.append(f"#define FC2_W_SHIFT     {s['w_shift']}")
    lines.append(f"#define FC2_OUT_SHIFT   {s['out_shift']}")
    lines.append(f"#define FC2_SHIFT_AMT   {s['shift_amount']}")
    lines.append("")

    # 权重数组
    total_sz = 0
    for name, wq, bq in quantized:
        w_flat = wq.ravel()
        b_flat = bq.ravel()
        total_sz += len(w_flat) + len(b_flat)

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

    lines.append(f"// Total weights: {total_sz} int16 = {total_sz*2} bytes")
    lines.append("")
    lines.append("#endif // __CNN_WEIGHTS_H__")

    h_path = os.path.join(OUTPUT_DIR, "cnn_weights.h")
    with open(h_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"  C头文件: {h_path} ({os.path.getsize(h_path)} bytes)")

    # 保存二进制
    meta = np.array([shift_info[n]["shift_amount"] for n in ["conv1","conv2","fc1","fc2"]],
                    dtype=np.int16)
    all_data = [meta]
    for _, wq, bq in quantized:
        all_data.append(wq.ravel())
        all_data.append(bq)
    all_bin = np.concatenate(all_data).astype(np.int16)
    bin_path = os.path.join(OUTPUT_DIR, "weights.bin")
    all_bin.tofile(bin_path)
    print(f"  二进制权重: {bin_path} ({len(all_bin)} int16 = {len(all_bin)*2} bytes)")

    for name, wq, bq in quantized:
        np.save(os.path.join(OUTPUT_DIR, f"{name}_w.npy"), wq)
        np.save(os.path.join(OUTPUT_DIR, f"{name}_b.npy"), bq)
    shift_arr = np.array([shift_info[n]["shift_amount"] for n in ["conv1","conv2","fc1","fc2"]],
                         dtype=np.int32)
    np.save(os.path.join(OUTPUT_DIR, "shifts.npy"), shift_arr)
    print("  numpy权重已保存")


# ======================== Main ========================
if __name__ == "__main__":
    print("=" * 60)
    print("CNN Char Recognition - Train + Per-layer Quant (v3)")
    print("=" * 60)

    model = train()
    quantized, shift_info = calibrate_quantization(model)
    verify_int16(model, quantized, shift_info)
    test_single_image(model, quantized, shift_info)
    export_header(quantized, shift_info, CLASSES)

    print(f"\n{'='*60}")
    print(f"完成! 输出目录: {OUTPUT_DIR}")
    for f in sorted(os.listdir(OUTPUT_DIR)):
        fpath = os.path.join(OUTPUT_DIR, f)
        print(f"  {f:30s}  {os.path.getsize(fpath):>8d} bytes")
