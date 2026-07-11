"""
训练小型CNN字符识别模型
数据集: binary_char_dataset/ (65类, 每类50张, 16x32二值图)
目标: Sparrow_soc (无FPU, 无硬件除法, 256KB SRAM, 32位ICB总线)
量化: int16 对称量化, 推理用移位代替除法

架构:
  Input: 1x32x16  (CxHxW, 二值 0/255 → 归一化为 0.0/1.0)
  Conv1: 3x3, 4ch, pad=1 → ReLU → MaxPool 2x2 → 4x16x8
  Conv2: 3x3, 8ch, pad=1 → ReLU → MaxPool 2x2 → 8x8x4
  Flatten: 256
  Dense1: 256→64 → ReLU
  Dense2: 64→65
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
EPOCHS      = 200
LR          = 0.001
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
    """加载 binary_char_dataset/ 下的 16x32 二值PNG"""
    def __init__(self, root_dir, classes):
        self.samples = []
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
        arr = np.array(img, dtype=np.float32)
        # 二值图 0/255 → 归一化到 0.0/1.0
        arr = arr / 255.0
        # shape: (C=1, H=32, W=16)
        tensor = torch.from_numpy(arr).unsqueeze(0)
        return tensor, label


# ======================== 模型定义 ========================
class TinyCharCNN(nn.Module):
    """
    极简CNN, 适合无FPU/无除法的软核, 参数量小.
    Conv1(1→4,3x3) → ReLU → Pool(2x2) → Conv2(4→8,3x3) → ReLU → Pool(2x2) → FC(256→64) → ReLU → FC(64→65)
    """
    def __init__(self, num_classes):
        super().__init__()
        self.conv1 = nn.Conv2d(1, 4, kernel_size=3, padding=1)
        self.bn1   = nn.BatchNorm2d(4)
        self.conv2 = nn.Conv2d(4, 8, kernel_size=3, padding=1)
        self.bn2   = nn.BatchNorm2d(8)
        self.fc1   = nn.Linear(8 * 8 * 4, 64)   # 经过两次Pool: H=32→16→8, W=16→8→4
        self.fc2   = nn.Linear(64, num_classes)
        self._init_weights()

    def _init_weights(self):
        for m in self.modules():
            if isinstance(m, (nn.Conv2d, nn.Linear)):
                nn.init.kaiming_normal_(m.weight, mode='fan_out', nonlinearity='relu')
                if m.bias is not None:
                    nn.init.constant_(m.bias, 0)

    def forward(self, x):
        x = F.relu(self.bn1(self.conv1(x)))          # 1x32x16 → 4x32x16
        x = F.max_pool2d(x, 2)                        # → 4x16x8
        x = F.relu(self.bn2(self.conv2(x)))           # → 8x16x8
        x = F.max_pool2d(x, 2)                        # → 8x8x4
        x = x.view(x.size(0), -1)                     # flatten: 256
        x = F.relu(self.fc1(x))                       # → 64
        x = self.fc2(x)                               # → 65
        return x


# ======================== 训练 ========================
def train():
    full_dataset = CharDataset(DATASET_DIR, CLASSES)
    print(f"\n总样本数: {len(full_dataset)}")

    # 每类50样本, 前45训练, 后5验证
    train_indices, val_indices = [], []
    samples_per_class = len(full_dataset) // NUM_CLASSES
    for cls_idx in range(NUM_CLASSES):
        start = cls_idx * samples_per_class
        train_indices.extend(range(start, start + 45))
        val_indices.extend(range(start + 45, start + samples_per_class))

    train_loader = DataLoader(Subset(full_dataset, train_indices),
                              batch_size=BATCH_SIZE, shuffle=True)
    val_loader   = DataLoader(Subset(full_dataset, val_indices),
                              batch_size=BATCH_SIZE, shuffle=False)

    model = TinyCharCNN(NUM_CLASSES).to(DEVICE)
    criterion = nn.CrossEntropyLoss()
    optimizer = torch.optim.Adam(model.parameters(), lr=LR)
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(
        optimizer, mode='min', factor=0.5, patience=10, )

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
            loss = criterion(model(images), labels)
            loss.backward()
            optimizer.step()
            train_loss += loss.item()
            _, pred = torch.max(model(images).detach(), 1)
            train_total += labels.size(0)
            train_correct += (pred == labels).sum().item()

        # --- 验证 ---
        model.eval()
        val_loss, val_correct, val_total = 0.0, 0, 0
        with torch.no_grad():
            for images, labels in val_loader:
                images, labels = images.to(DEVICE), labels.to(DEVICE)
                outputs = model(images)
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

    # 加载最佳模型
    model.load_state_dict(best_state)
    torch.save(model.state_dict(), os.path.join(OUTPUT_DIR, "model_float.pth"))
    print(f"浮点模型已保存: {OUTPUT_DIR}\\model_float.pth")

    # --- 逐类别评估 ---
    model.eval()
    all_preds, all_labels = [], []
    with torch.no_grad():
        for images, labels in val_loader:
            outputs = model(images.to(DEVICE))
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


# ======================== int16 量化导出 ========================
def quantize_and_export(model):
    """
    将训练好的模型量化为 int16 并导出:
      - model_output/weights.bin     (所有 int16 权重拼接)
      - model_output/cnn_weights.h   (C头文件, 包含权重数组 + 推理宏)
    """
    print("\n========== int16 量化导出 ==========")

    model.eval()
    layers = []

    # ----- conv1 -----
    w1 = model.conv1.weight.detach().numpy()   # (4,1,3,3)
    b1 = model.bn1.bias.detach().numpy()        # (4,) — BN bias
    # 将BN融合到Conv: w_eff = w * gamma / sqrt(var+eps)
    gamma1 = model.bn1.weight.detach().numpy()
    beta1  = model.bn1.bias.detach().numpy()
    mean1  = model.bn1.running_mean.detach().numpy()
    var1   = model.bn1.running_var.detach().numpy()
    eps    = model.bn1.eps
    rstd1  = 1.0 / np.sqrt(var1 + eps)
    w1_eff = w1 * gamma1.reshape(-1,1,1,1) * rstd1.reshape(-1,1,1,1)
    b1_eff = beta1 - mean1 * gamma1 * rstd1
    layers.append(("conv1", w1_eff, b1_eff))

    # ----- conv2 -----
    w2 = model.conv2.weight.detach().numpy()   # (8,4,3,3)
    gamma2 = model.bn2.weight.detach().numpy()
    beta2  = model.bn2.bias.detach().numpy()
    mean2  = model.bn2.running_mean.detach().numpy()
    var2   = model.bn2.running_var.detach().numpy()
    rstd2  = 1.0 / np.sqrt(var2 + eps)
    w2_eff = w2 * gamma2.reshape(-1,1,1,1) * rstd2.reshape(-1,1,1,1)
    b2_eff = beta2 - mean2 * gamma2 * rstd2
    layers.append(("conv2", w2_eff, b2_eff))

    # ----- fc1 -----
    w3 = model.fc1.weight.detach().numpy()     # (64,256)
    b3 = model.fc1.bias.detach().numpy()        # (64,)
    layers.append(("fc1", w3, b3))

    # ----- fc2 -----
    w4 = model.fc2.weight.detach().numpy()     # (65,64)
    b4 = model.fc2.bias.detach().numpy()        # (65,)
    layers.append(("fc2", w4, b4))

    # ----- 量化每层为 int16 -----
    quantized = []
    shift_bits = []  # 每层右移位数, 用 2^shift 代替 scale 乘法除法

    # 统一使用 Q15 格式 (shift=15), 保证每层都用满 int16 精度
    # Q15: 1 bit sign + 15 bits fraction
    # 推理时: result = (sum(input*weight_q) + bias_q) >> 15
    UNIFORM_SHIFT = 15

    for name, w, b in layers:
        s = UNIFORM_SHIFT
        wq = np.clip(np.round(w * (2**s)), -32768, 32767).astype(np.int16)
        bq = np.clip(np.round(b * (2**s)), -32768, 32767).astype(np.int16)

        quantized.append((name, wq, bq))
        shift_bits.append(s)

        w_actual_max = max(np.abs(wq).max(), 1)
        b_actual_max = max(np.abs(bq).max(), 1)
        print(f"  {name:6s}: shape={str(w.shape):20s} shift={s:2d}  "
              f"w∈[{wq.min():5d},{wq.max():5d}]  b∈[{bq.min():5d},{bq.max():5d}]")

    # ----- 保存二进制文件 -----
    # 格式: [shift_bits...][weights+bias拼接]
    meta = np.array(shift_bits, dtype=np.int16)
    all_data = [meta]
    for _, wq, bq in quantized:
        all_data.append(wq.ravel())
        all_data.append(bq)
    all_bin = np.concatenate(all_data).astype(np.int16)
    bin_path = os.path.join(OUTPUT_DIR, "weights.bin")
    all_bin.tofile(bin_path)
    print(f"\n二进制权重: {bin_path}  ({len(all_bin)} int16 = {len(all_bin)*2} bytes)")

    # ----- 生成C头文件 -----
    header = generate_c_header(quantized, shift_bits, CLASSES)
    h_path = os.path.join(OUTPUT_DIR, "cnn_weights.h")
    with open(h_path, "w", encoding="utf-8") as f:
        f.write(header)
    print(f"C头文件: {h_path}")

    # ----- 保存numpy格式 (方便Python验证) -----
    for name, wq, bq in quantized:
        np.save(os.path.join(OUTPUT_DIR, f"{name}_w.npy"), wq)
        np.save(os.path.join(OUTPUT_DIR, f"{name}_b.npy"), bq)
    np.save(os.path.join(OUTPUT_DIR, "shifts.npy"), np.array(shift_bits, dtype=np.int32))

    print("numpy权重已保存 (可用于Python验证)")
    return quantized, shift_bits


def generate_c_header(quantized, shift_bits, classes):
    """生成 int16 权重的 C 头文件 (无浮点, 无除法, 32位ICB总线适用)"""
    lines = []
    lines.append("// ============================================================")
    lines.append("// CNN字符识别 int16 权重头文件")
    lines.append("// 适用于: Sparrow_soc (无FPU, 无硬件除法, 32位ICB总线, 256KB SRAM)")
    lines.append("// 输入: 16x32 二值图像 (0=黑, 255=白) — C代码中先二值化为0/1")
    lines.append("// 输出: 65类 (0-9, A-Z, 省份缩写)")
    lines.append("// 生成方式: Python训练 + int16对称量化 + power-of-2移位")
    lines.append("// ============================================================")
    lines.append("#ifndef __CNN_WEIGHTS_H__")
    lines.append("#define __CNN_WEIGHTS_H__")
    lines.append("#include <stdint.h>")
    lines.append("")

    # 类别列表
    lines.append(f"#define NUM_CLASSES  {len(classes)}")
    lines.append("")
    lines.append("static const char* class_names[NUM_CLASSES] = {")
    for c in classes:
        lines.append(f'    "{c}",')
    lines.append("};")
    lines.append("")

    # 层配置宏
    lines.append("// ==================== 网络结构 ====================")
    lines.append("// Input:  1 x 32 x 16  (C x H x W)")
    lines.append("// Conv1:  1->4,  3x3, pad=1, ReLU,  MaxPool 2x2  ->  4 x 16 x 8")
    lines.append("// Conv2:  4->8,  3x3, pad=1, ReLU,  MaxPool 2x2  ->  8 x  8 x 4")
    lines.append("// FC1:    256 -> 64, ReLU")
    lines.append("// FC2:    64  -> 65")
    lines.append("")

    # Conv1 参数
    lines.append("// ---------- Conv1 ----------")
    lines.append("#define CONV1_IN_CH    1")
    lines.append("#define CONV1_OUT_CH   4")
    lines.append("#define CONV1_KH       3")
    lines.append("#define CONV1_KW       3")
    lines.append(f"#define CONV1_SHIFT    {shift_bits[0]}")
    lines.append("")

    # Conv2 参数
    lines.append("// ---------- Conv2 ----------")
    lines.append("#define CONV2_IN_CH    4")
    lines.append("#define CONV2_OUT_CH   8")
    lines.append("#define CONV2_KH       3")
    lines.append("#define CONV2_KW       3")
    lines.append(f"#define CONV2_SHIFT    {shift_bits[1]}")
    lines.append("")

    # FC1 参数
    lines.append("// ---------- FC1 ----------")
    lines.append("#define FC1_IN         256")
    lines.append("#define FC1_OUT        64")
    lines.append(f"#define FC1_SHIFT      {shift_bits[2]}")
    lines.append("")

    # FC2 参数
    lines.append("// ---------- FC2 ----------")
    lines.append("#define FC2_IN         64")
    lines.append("#define FC2_OUT        65")
    lines.append(f"#define FC2_SHIFT      {shift_bits[3]}")
    lines.append("")

    # 激活映射
    lines.append("// --------------------------------------------------")
    lines.append("// After Conv1 Pool:  H=16, W=8   -> activations = 4*16*8  = 512")
    lines.append("// After Conv2 Pool:  H=8,  W=4   -> activations = 8*8*4   = 256")
    lines.append("// FC1 activations:   64")
    lines.append("// Total activations: 512 + 256 + 64 = 832 int16 = 1664 bytes")
    lines.append("// (远小于 256KB SRAM)")
    lines.append("// --------------------------------------------------")
    lines.append("")

    # 权重数组 (直接嵌入头文件)
    # 对于小型模型, 直接嵌入头文件更简单
    total_int16s = 0
    for name, wq, bq in quantized:
        lines.append(f"// {name}: weights[{wq.shape}] + bias[{bq.shape}]")
        w_flat = wq.ravel()
        b_flat = bq.ravel()

        # 权重数组
        arr_name = f"{name}_weights"
        lines.append(f"static const int16_t {arr_name}[{len(w_flat)}] = {{")
        # 每行16个
        for i in range(0, len(w_flat), 16):
            chunk = w_flat[i:i+16]
            lines.append("    " + ", ".join(f"{v:6d}" for v in chunk) + ",")
        lines.append("};")
        lines.append("")

        # 偏置数组
        arr_name = f"{name}_bias"
        lines.append(f"static const int16_t {arr_name}[{len(b_flat)}] = {{")
        for i in range(0, len(b_flat), 16):
            chunk = b_flat[i:i+16]
            lines.append("    " + ", ".join(f"{v:6d}" for v in chunk) + ",")
        lines.append("};")
        lines.append("")

        total_int16s += len(w_flat) + len(b_flat)

    lines.append(f"// 总权重大小: {total_int16s} int16 = {total_int16s * 2} bytes")
    lines.append(f"// (SRAM 256KB = 262144 bytes, 占用 {(total_int16s*2)/262144*100:.1f}%)")
    lines.append("")

    # 推理函数声明 (C代码需要实现)
    lines.append("// ==================== 推理接口 ====================")
    lines.append("// 输入: 32x16 uint8 图像 (row-major, 0=黑 255=白)")
    lines.append("// 返回: 类别索引 (0~64), 或 -1 表示错误")
    lines.append("//")
    lines.append("// int cnn_predict(const uint8_t image[32][16]);")
    lines.append("")

    # 提供参考C推理代码的宏
    lines.append("// ==================== 参考C代码 (卷积) ====================")
    lines.append("/*")
    lines.append("// Conv2D with int16 weights, int32 accumulator, right-shift output")
    lines.append("static void conv2d_int16(")
    lines.append("    const int16_t input[IN_CH][IN_H][IN_W],")
    lines.append("    const int16_t weights[OUT_CH][IN_CH][KH][KW],")
    lines.append("    const int16_t bias[OUT_CH],")
    lines.append("    int16_t output[OUT_CH][OUT_H][OUT_W],")
    lines.append("    int shift)")
    lines.append("{")
    lines.append("    for (int oc = 0; oc < OUT_CH; oc++) {")
    lines.append("        for (int h = 0; h < OUT_H; h++) {")
    lines.append("            for (int w = 0; w < OUT_W; w++) {")
    lines.append("                int32_t sum = bias[oc];")
    lines.append("                for (int ic = 0; ic < IN_CH; ic++) {")
    lines.append("                    for (int kh = 0; kh < KH; kh++) {")
    lines.append("                        for (int kw = 0; kw < KW; kw++) {")
    lines.append("                            int ih = h + kh - 1;  // padding=1")
    lines.append("                            int iw = w + kw - 1;")
    lines.append("                            if (ih >= 0 && ih < IN_H && iw >= 0 && iw < IN_W)")
    lines.append("                                sum += (int32_t)input[ic][ih][iw] * (int32_t)weights[oc][ic][kh][kw];")
    lines.append("                        }")
    lines.append("                    }")
    lines.append("                }")
    lines.append("                int32_t out = sum >> shift;")
    lines.append("                if (out < 0) out = 0;       // ReLU")
    lines.append("                if (out > 32767) out = 32767;")
    lines.append("                output[oc][h][w] = (int16_t)out;")
    lines.append("            }")
    lines.append("        }")
    lines.append("    }")
    lines.append("}")
    lines.append("")
    lines.append("// MaxPool 2x2")
    lines.append("static void maxpool2d(")
    lines.append("    const int16_t input[IN_CH][IN_H][IN_W],")
    lines.append("    int16_t output[OUT_CH][OUT_H][OUT_W])")
    lines.append("{")
    lines.append("    for (int c = 0; c < IN_CH; c++) {")
    lines.append("        for (int h = 0; h < OUT_H; h++) {")
    lines.append("            for (int w = 0; w < OUT_W; w++) {")
    lines.append("                int16_t maxv = -32768;")
    lines.append("                for (int dh = 0; dh < 2; dh++) {")
    lines.append("                    for (int dw = 0; dw < 2; dw++) {")
    lines.append("                        int ih = h * 2 + dh;")
    lines.append("                        int iw = w * 2 + dw;")
    lines.append("                        if (input[c][ih][iw] > maxv)")
    lines.append("                            maxv = input[c][ih][iw];")
    lines.append("                    }")
    lines.append("                }")
    lines.append("                output[c][h][w] = maxv;")
    lines.append("            }")
    lines.append("        }")
    lines.append("    }")
    lines.append("}")
    lines.append("")
    lines.append("// Dense (fully connected)")
    lines.append("static void dense_int16(")
    lines.append("    const int16_t input[IN_DIM],")
    lines.append("    const int16_t weights[OUT_DIM][IN_DIM],")
    lines.append("    const int16_t bias[OUT_DIM],")
    lines.append("    int16_t output[OUT_DIM],")
    lines.append("    int shift, int use_relu)")
    lines.append("{")
    lines.append("    for (int o = 0; o < OUT_DIM; o++) {")
    lines.append("        int32_t sum = bias[o];")
    lines.append("        for (int i = 0; i < IN_DIM; i++) {")
    lines.append("            sum += (int32_t)input[i] * (int32_t)weights[o][i];")
    lines.append("        }")
    lines.append("        int32_t out = sum >> shift;")
    lines.append("        if (use_relu && out < 0) out = 0;")
    lines.append("        if (out > 32767) out = 32767;")
    lines.append("        output[o] = (int16_t)out;")
    lines.append("    }")
    lines.append("}")
    lines.append("*/")
    lines.append("")

    lines.append("#endif // __CNN_WEIGHTS_H__")
    lines.append("")
    return "\n".join(lines)


# ======================== int16 推理验证 ========================
def verify_int16_inference(model, quantized, shift_bits):
    """在Python中用int16运算模拟C代码推理, 对比全精度结果"""
    print("\n========== int16 推理精度验证 ==========")

    model.eval()

    # 用一个验证集评估 int16 推理准确率
    full_dataset = CharDataset(DATASET_DIR, CLASSES)
    indices = []
    samples_per_class = len(full_dataset) // NUM_CLASSES
    for cls_idx in range(NUM_CLASSES):
        start = cls_idx * samples_per_class
        indices.extend(range(start + 45, start + samples_per_class))

    val_loader = DataLoader(Subset(full_dataset, indices),
                            batch_size=1, shuffle=False)

    correct_int = 0
    correct_float = 0
    total = 0

    for img_t, label in val_loader:
        label = label.item()

        # --- 浮点推理 (参考) ---
        with torch.no_grad():
            out_f = model(img_t.to(DEVICE)).cpu().numpy()[0]
        pred_f = np.argmax(out_f)
        if pred_f == label:
            correct_float += 1

        # --- int16 推理 (模拟C代码) ---
        x = (img_t.numpy()[0, 0] * 255).astype(np.int32)  # 还原到 [0,255]
        # 二值化: >127 = 1, <=127 = 0 (因为C代码读的是原始像素)
        x_bin = (x > 127).astype(np.int32)

        pred_int = int16_infer(x_bin, quantized, shift_bits)
        if pred_int == label:
            correct_int += 1

        total += 1

    print(f"浮点推理:  {correct_float}/{total} = {100.0*correct_float/total:.1f}%")
    print(f"int16推理: {correct_int}/{total} = {100.0*correct_int/total:.1f}%")
    print(f"精度损失:  {100.0*(correct_float-correct_int)/total:.1f}%")
    return correct_int / total


def int16_infer(x_bin, quantized, shift_bits):
    """
    int16 推理 (模拟 Sparrow_soc C代码运算)
    x_bin: (32,16) int32, values 0 or 1
    返回: 类别索引
    """
    # 输入保持 0/1 (C代码读取uint8像素后, 用 >128 二值化, 得到 0 或 1)
    x = x_bin.astype(np.int32)  # 0 或 1, 不用额外缩放

    # ---- Conv1 ----
    name, wq, bq = quantized[0]  # conv1: (4,1,3,3) weight, (4,) bias
    x = int16_conv2d(x.reshape(1, 1, 32, 16), wq, bq, shift_bits[0])
    x = int16_maxpool2d(x, 2)    # → (1,4,16,8)
    # ReLU is inside conv2d

    # ---- Conv2 ----
    name, wq, bq = quantized[1]  # conv2: (8,4,3,3) weight, (8,) bias
    x = int16_conv2d(x, wq, bq, shift_bits[1])
    x = int16_maxpool2d(x, 2)    # → (1,8,8,4)

    # ---- Flatten ----
    x_flat = x.reshape(-1)       # 256

    # ---- FC1 ----
    name, wq, bq = quantized[2]  # fc1: (64,256) weight, (64,) bias
    x_flat = int16_dense(x_flat, wq, bq, shift_bits[2], relu=True)

    # ---- FC2 ----
    name, wq, bq = quantized[3]  # fc2: (65,64) weight, (65,) bias
    x_flat = int16_dense(x_flat, wq, bq, shift_bits[3], relu=False)

    return np.argmax(x_flat)


def int16_conv2d(x, weight, bias, shift):
    """
    x: (1, in_ch, H, W) int32
    weight: (out_ch, in_ch, KH, KW) int16
    bias: (out_ch,) int16
    shift: right-shift amount
    """
    out_ch, in_ch, kh, kw = weight.shape
    _, _, h, w = x.shape
    out_h, out_w = h, w  # padding=1 → same spatial size

    # pad input
    padded = np.pad(x, ((0,0), (0,0), (1,1), (1,1)), mode='constant')

    result = np.zeros((1, out_ch, out_h, out_w), dtype=np.int32)
    # 优化: 用矩阵运算代替逐元素循环
    for oc in range(out_ch):
        acc = np.zeros((out_h, out_w), dtype=np.int32)
        for ic in range(in_ch):
            # 输入通道 ic 与 输出通道 oc 的卷积核做2D相关
            w_slice = weight[oc, ic]  # (kh, kw)
            # 利用 scipy-like 手动滑动窗口
            for kh_ in range(kh):
                for kw_ in range(kw):
                    w_val = int(w_slice[kh_, kw_])
                    if w_val == 0:
                        continue
                    acc += w_val * padded[0, ic, kh_:kh_+out_h, kw_:kw_+out_w]
        # bias
        acc += int(bias[oc])
        # shift + ReLU + clamp
        acc = acc >> shift
        acc = np.clip(acc, 0, 32767)
        result[0, oc] = acc
    return result


def int16_maxpool2d(x, pool_size):
    """x: (1, ch, H, W) int32, pool_size=2"""
    _, ch, h, w = x.shape
    out_h, out_w = h // pool_size, w // pool_size
    result = np.zeros((1, ch, out_h, out_w), dtype=np.int32)
    for c in range(ch):
        for oh in range(out_h):
            for ow in range(out_w):
                block = x[0, c,
                          oh*pool_size:(oh+1)*pool_size,
                          ow*pool_size:(ow+1)*pool_size]
                result[0, c, oh, ow] = block.max()
    return result


def int16_dense(x, weight, bias, shift, relu=False):
    """
    x: (in_dim,) int32
    weight: (out_dim, in_dim) int16
    bias: (out_dim,) int16
    """
    out_dim = weight.shape[0]
    result = np.zeros(out_dim, dtype=np.int32)
    for o in range(out_dim):
        sum_ = int(bias[o])
        for i in range(len(x)):
            sum_ += int(x[i]) * int(weight[o, i])
        out_val = sum_ >> shift
        if relu and out_val < 0:
            out_val = 0
        if out_val > 32767:
            out_val = 32767
        result[o] = out_val
    return result


# ======================== 测试 char_0.bmp ========================
def test_single_image(model, quantized, shift_bits):
    """测试 char_0.bmp (应为 '湘')"""
    print("\n========== 测试 char_0.bmp ==========")

    if not os.path.exists(TEST_IMAGE):
        print(f"⚠ 测试图片不存在: {TEST_IMAGE}")
        return

    img = Image.open(TEST_IMAGE).convert("L")
    print(f"原始图像: {img.size}")

    # 缩放到 16x32
    if img.size != (16, 32):
        img = img.resize((16, 32), Image.NEAREST)
    arr = np.array(img, dtype=np.float32)

    # 二值化: 以128为阈值
    arr_bin = (arr > 127).astype(np.int32)

    # 显示预览
    print("\n(16x32 二值化预览, #=白 .=黑):")
    for r in range(32):
        line = "".join("#" if arr_bin[r, c] else "." for c in range(16))
        print(f"  {line}")

    # --- 浮点推理 ---
    model.eval()
    with torch.no_grad():
        inp = torch.from_numpy(arr / 255.0).unsqueeze(0).unsqueeze(0).float()
        out_f = model(inp).numpy()[0]
    pred_f = np.argmax(out_f)
    top5_f = np.argsort(out_f)[-5:][::-1]
    probs_f = F.softmax(torch.from_numpy(out_f), dim=0).numpy()

    print(f"\n--- 浮点模型预测 ---")
    print(f"  预测: {CLASSES[pred_f]} (idx={pred_f})")
    print(f"  Top-5:")
    for i, idx in enumerate(top5_f):
        print(f"    {i+1}. {CLASSES[idx]:4s}: {probs_f[idx]:.4f}")

    # --- int16 推理 ---
    pred_int = int16_infer(arr_bin, quantized, shift_bits)
    print(f"\n--- int16 模型预测 ---")
    print(f"  预测: {CLASSES[pred_int]} (idx={pred_int})")

    if CLASSES[pred_f] == "湘":
        print("\n✓ 浮点模型正确识别为 '湘'!")
    else:
        print(f"\n⚠ 浮点模型预测为 '{CLASSES[pred_f]}', 非 '湘'!")

    if CLASSES[pred_int] == "湘":
        print("✓ int16模型正确识别为 '湘'!")
    else:
        print(f"⚠ int16模型预测为 '{CLASSES[pred_int]}', 非 '湘'!")


# ======================== Main ========================
if __name__ == "__main__":
    # 1. 训练
    model = train()

    # 2. 量化导出
    quantized, shift_bits = quantize_and_export(model)

    # 3. int16 推理验证
    verify_int16_inference(model, quantized, shift_bits)

    # 4. 测试 char_0.bmp
    test_single_image(model, quantized, shift_bits)

    print("\n========== 完成! ==========")
    print(f"输出目录: {OUTPUT_DIR}")
    print(f"生成的文件:")
    for f in os.listdir(OUTPUT_DIR):
        fpath = os.path.join(OUTPUT_DIR, f)
        size = os.path.getsize(fpath)
        print(f"  {f:30s}  {size:>8d} bytes")
