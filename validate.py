"""
独立验证脚本: 用训练好的int16量化模型识别单个字符图像

用法:
  python validate.py                              # 测试 char_0.bmp (默认)
  python validate.py --image <path_to_image>      # 测试任意图片
  python validate.py --test-all                   # 在验证集上评估

该脚本模拟 Sparrow_soc 上的纯整数推理 (无FPU, 无除法)
"""

import os, sys, argparse
import numpy as np
from PIL import Image

# ======================== 配置 ========================
MODEL_DIR = r"D:\python+pycharm\Project\reset_picture_single_word\model_output"
DEFAULT_TEST_IMAGE = r"D:\MATLAB\PIC\single_word_debug\char_0.bmp"

# ======================== 加载模型 ========================
def load_model(model_dir):
    """加载量化后的 int16 权重和类别"""
    # 类别列表
    classes_path = os.path.join(model_dir, "classes.txt")
    with open(classes_path, "r", encoding="utf-8") as f:
        classes = [line.strip() for line in f if line.strip()]
    NUM_CLASSES = len(classes)

    # 量化参数 (每层的移位值)
    shifts = np.load(os.path.join(model_dir, "shifts.npy")).tolist()

    # 加载每层权重
    layers = []
    layer_names = ["conv1", "conv2", "fc1", "fc2"]
    for name in layer_names:
        w = np.load(os.path.join(model_dir, f"{name}_w.npy")).astype(np.int32)
        b = np.load(os.path.join(model_dir, f"{name}_b.npy")).astype(np.int32)
        layers.append((name, w, b))

    print(f"模型加载完成: {NUM_CLASSES} 类, {len(layers)} 层")
    for (name, w, b), s in zip(layers, shifts):
        print(f"  {name:6s}: weight {str(w.shape):20s} bias {str(b.shape):10s} shift={s}")
    return classes, layers, shifts


# ======================== int16 推理函数 ========================
def conv2d_int16(x, weight, bias, shift):
    """
    纯整数 2D 卷积 (模拟Sparrow_soc C代码)
    x: (1, in_ch, H, W) int32, values 0 or 1
    weight: (out_ch, in_ch, KH, KW) int16
    bias: (out_ch,) int16
    shift: 右移位数
    """
    out_ch, in_ch, kh, kw = weight.shape
    _, _, h, w = x.shape
    # padding=1 → same spatial size
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
        np.clip(acc, 0, 32767, out=acc)  # ReLU
        result[0, oc] = acc
    return result


def maxpool2d_int16(x, pool_size=2):
    """纯整数 MaxPool 2x2"""
    _, ch, h, w = x.shape
    oh, ow = h // pool_size, w // pool_size
    result = np.zeros((1, ch, oh, ow), dtype=np.int32)
    for c in range(ch):
        for i in range(oh):
            for j in range(ow):
                result[0, c, i, j] = np.max(
                    x[0, c, i*pool_size:(i+1)*pool_size, j*pool_size:(j+1)*pool_size]
                )
    return result


def dense_int16(x, weight, bias, shift, use_relu=True):
    """
    纯整数全连接层
    x: (in_dim,) int32
    weight: (out_dim, in_dim) int16
    bias: (out_dim,) int16
    """
    out_dim = weight.shape[0]
    result = np.zeros(out_dim, dtype=np.int32)
    for o in range(out_dim):
        s = int(bias[o])
        # 点积
        s += np.dot(x.astype(np.int32), weight[o].astype(np.int32))
        out_val = s >> shift
        if use_relu and out_val < 0:
            out_val = 0
        if out_val > 32767:
            out_val = 32767
        result[o] = out_val
    return result


def predict_int16(image_bin, layers, shifts):
    """
    完整 int16 推理管线
    image_bin: (32, 16) int32, values 0 or 1
    返回: 类别索引, 类别名, 所有logits
    """
    x = image_bin.reshape(1, 1, 32, 16).astype(np.int32)

    # Conv1
    w, b = layers[0][1], layers[0][2]
    x = conv2d_int16(x, w, b, shifts[0])
    x = maxpool2d_int16(x, 2)

    # Conv2
    w, b = layers[1][1], layers[1][2]
    x = conv2d_int16(x, w, b, shifts[1])
    x = maxpool2d_int16(x, 2)

    # Flatten
    x_flat = x.reshape(-1)

    # FC1
    w, b = layers[2][1], layers[2][2]
    x_flat = dense_int16(x_flat, w, b, shifts[2], use_relu=True)

    # FC2
    w, b = layers[3][1], layers[3][2]
    logits = dense_int16(x_flat, w, b, shifts[3], use_relu=False)

    pred_idx = int(np.argmax(logits))
    return pred_idx, logits


# ======================== 图片预处理 ========================
def preprocess_image(image_path, size=(16, 32), threshold=128):
    """
    预处理图片为 16x32 二值图 (0/1)
    路径支持中文
    """
    if not os.path.exists(image_path):
        raise FileNotFoundError(f"图片不存在: {image_path}")

    img = Image.open(image_path).convert("L")
    if img.size != size:
        img = img.resize(size, Image.NEAREST)
    arr = np.array(img, dtype=np.int32)
    # 二值化: > threshold = 1 (白), <= threshold = 0 (黑)
    binary = (arr > threshold).astype(np.int32)
    return binary, img.size


def print_ascii_preview(binary):
    """打印 ASCII 预览"""
    print("\nASCII 预览 (16x32):")
    for r in range(32):
        line = "".join("#" if binary[r, c] else "." for c in range(16))
        print(f"  {line}")
    print()


# ======================== 主函数 ========================
def predict_single(image_path, classes, layers, shifts):
    """预测单张图片"""
    binary, orig_size = preprocess_image(image_path)
    print(f"原始图片: {orig_size} → 16x32 二值化")
    print_ascii_preview(binary)

    pred_idx, logits = predict_int16(binary, layers, shifts)
    pred_class = classes[pred_idx]

    print(f">>> int16 模型预测: {pred_class} (idx={pred_idx})")
    print(f"    score={logits[pred_idx]}")

    # Top-5
    top5 = np.argsort(logits)[-5:][::-1]
    print("\nTop-5 预测:")
    for i, idx in enumerate(top5):
        print(f"  {i+1}. {classes[idx]:4s}: score={logits[idx]}")

    return pred_class, logits


def test_on_validation_set(classes, layers, shifts):
    """在验证集上评估 int16 模型准确率"""
    dataset_dir = r"D:\python+pycharm\Project\reset_picture_single_word\binary_char_dataset"
    print(f"\n{'='*60}")
    print("int16 模型验证集评估")
    print(f"{'='*60}")

    NUM_CLASSES = len(classes)
    correct = 0
    total = 0
    per_correct = np.zeros(NUM_CLASSES, dtype=int)
    per_total = np.zeros(NUM_CLASSES, dtype=int)

    for cls_idx, cls_name in enumerate(classes):
        cls_dir = os.path.join(dataset_dir, cls_name)
        files = sorted([f for f in os.listdir(cls_dir) if f.lower().endswith(".png")])
        # 取最后5个作为验证集 (与训练时一致)
        val_files = files[-5:]
        for fname in val_files:
            img_path = os.path.join(cls_dir, fname)
            binary, _ = preprocess_image(img_path)
            pred_idx, _ = predict_int16(binary, layers, shifts)
            per_total[cls_idx] += 1
            total += 1
            if pred_idx == cls_idx:
                per_correct[cls_idx] += 1
                correct += 1

    print(f"\n总体准确率: {correct}/{total} = {100.0*correct/total:.1f}%")
    print("\n各类别准确率:")
    for i in range(NUM_CLASSES):
        acc = 100.0 * per_correct[i] / per_total[i] if per_total[i] > 0 else 0
        flag = " ⚠" if acc < 80 else ""
        print(f"  {classes[i]:4s}: {per_correct[i]:d}/{per_total[i]:d} = {acc:5.1f}%{flag}")

    return correct / total


# ======================== CLI ========================
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="CNN字符识别 int16 推理验证")
    parser.add_argument("--image", type=str, default=DEFAULT_TEST_IMAGE,
                        help="要识别的图片路径")
    parser.add_argument("--test-all", action="store_true",
                        help="在验证集上评估准确率")
    parser.add_argument("--model-dir", type=str, default=MODEL_DIR,
                        help="模型目录 (默认: model_output/)")
    args = parser.parse_args()

    print("=" * 60)
    print("CNN 字符识别 - int16 量化推理")
    print("=" * 60)

    classes, layers, shifts = load_model(args.model_dir)

    if args.test_all:
        test_on_validation_set(classes, layers, shifts)
    else:
        predict_single(args.image, classes, layers, shifts)
