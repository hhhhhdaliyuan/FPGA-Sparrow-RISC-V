import os, cv2, numpy as np

DATA_DIR = r'D:\python+pycharm\Project\simple-car-plate-recognition-master\dataset'
classes = sorted([d for d in os.listdir(DATA_DIR) if os.path.isdir(os.path.join(DATA_DIR, d)) and not d.startswith('.')])

# Load int16 weights
w0 = np.load(r'D:\python+pycharm\Project\train_CNN\layer0_w.npy').astype(np.int32)
b0 = np.load(r'D:\python+pycharm\Project\train_CNN\layer0_b.npy').astype(np.int32)
w1 = np.load(r'D:\python+pycharm\Project\train_CNN\layer1_w.npy').astype(np.int32)
b1 = np.load(r'D:\python+pycharm\Project\train_CNN\layer1_b.npy').astype(np.int32)
w2 = np.load(r'D:\python+pycharm\Project\train_CNN\layer2_w.npy').astype(np.int32)
b2 = np.load(r'D:\python+pycharm\Project\train_CNN\layer2_b.npy').astype(np.int32)

def int16_infer(x_int32):
    h = (x_int32.dot(w0) + b0) >> 15
    h = np.maximum(h, 0).clip(0, 32767)
    h = (h.dot(w1) + b1) >> 15
    h = np.maximum(h, 0).clip(0, 32767)
    h = (h.dot(w2) + b2) >> 15
    return h

# ===== Test with actual training images of zh_xiang =====
print('验证: 用训练集 zh_xiang 的图片测试模型')
print('=' * 60)
xiang_dir = os.path.join(DATA_DIR, 'zh_xiang')
files = sorted([f for f in os.listdir(xiang_dir) if f.lower().endswith(('.jpg','.png','.jpeg'))])

correct = 0
for fname in files:
    img = cv2.imread(os.path.join(xiang_dir, fname), cv2.IMREAD_GRAYSCALE)
    x = cv2.resize(img, (16, 32)).flatten().astype(np.int32)
    out = int16_infer(x)
    p = np.argmax(out)
    if classes[p] == 'zh_xiang':
        correct += 1

print(f'zh_xiang 测试: {correct}/{len(files)} 正确 ({correct/len(files)*100:.1f}%)')
print(f'共 {len(files)} 张测试图片')

# Show incorrect ones
print()
print('预测错误的 zh_xiang 样本:')
for fname in files:
    img = cv2.imread(os.path.join(xiang_dir, fname), cv2.IMREAD_GRAYSCALE)
    x = cv2.resize(img, (16, 32)).flatten().astype(np.int32)
    out = int16_infer(x)
    p = np.argmax(out)
    if classes[p] != 'zh_xiang':
        top3 = np.argsort(out)[-3:][::-1]
        scores = ', '.join([f'{classes[j]}({out[j]})' for j in top3])
        print(f'  {fname}: 预测={classes[p]} | Top3: {scores}')

# Test some other province chars
print()
print('验证: 测试其他省份字符:')
test_classes = ['zh_yue', 'zh_jing', 'zh_su', 'zh_lu', 'zh_min']
for tc in test_classes:
    tc_dir = os.path.join(DATA_DIR, tc)
    tc_files = [f for f in os.listdir(tc_dir) if f.lower().endswith(('.jpg','.png','.jpeg'))]
    correct = 0
    for fname in tc_files[:50]:  # test up to 50
        img = cv2.imread(os.path.join(tc_dir, fname), cv2.IMREAD_GRAYSCALE)
        x = cv2.resize(img, (16, 32)).flatten().astype(np.int32)
        out = int16_infer(x)
        p = np.argmax(out)
        if classes[p] == tc:
            correct += 1
    n = min(50, len(tc_files))
    print(f'  {tc}: {correct}/{n} = {correct/n*100:.1f}%')

# Test digit 8
print()
print('验证: 测试数字 8:')
tc = '8'
tc_dir = os.path.join(DATA_DIR, tc)
tc_files = [f for f in os.listdir(tc_dir) if f.lower().endswith(('.jpg','.png','.jpeg'))]
correct = 0
for fname in tc_files[:100]:
    img = cv2.imread(os.path.join(tc_dir, fname), cv2.IMREAD_GRAYSCALE)
    x = cv2.resize(img, (16, 32)).flatten().astype(np.int32)
    out = int16_infer(x)
    p = np.argmax(out)
    if classes[p] == tc:
        correct += 1
n = min(100, len(tc_files))
print(f'  {tc}: {correct}/{n} = {correct/n*100:.1f}%')
