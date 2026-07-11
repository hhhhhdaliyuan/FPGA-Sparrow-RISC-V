import os, numpy as np, cv2
from sklearn.neural_network import MLPClassifier
from sklearn.model_selection import train_test_split

DATA_DIR = r'D:\python+pycharm\Project\simple-car-plate-recognition-master\dataset'
classes = sorted([d for d in os.listdir(DATA_DIR)
                  if os.path.isdir(os.path.join(DATA_DIR, d)) and not d.startswith('.')])
print(f'类别数: {len(classes)}')

# Quick load with smaller validation set
X_all, y_all = [], []
for idx, cls in enumerate(classes):
    cls_dir = os.path.join(DATA_DIR, cls)
    for fname in os.listdir(cls_dir):
        if not fname.lower().endswith(('.jpg','.png','.jpeg')): continue
        img = cv2.imread(os.path.join(cls_dir, fname), cv2.IMREAD_GRAYSCALE)
        if img is None: continue
        img = cv2.resize(img, (16, 32)).flatten() / 255.0
        X_all.append(img); y_all.append(idx)
X_all, y_all = np.array(X_all), np.array(y_all)
print(f'总样本: {len(X_all)}')

X_train, X_val, y_train, y_val = train_test_split(X_all, y_all, test_size=0.2, random_state=42)

model = MLPClassifier(hidden_layer_sizes=(256,128), max_iter=200, random_state=42, verbose=False)
model.fit(X_train, y_train)
float_acc = model.score(X_val, y_val)
print(f'浮点模型验证准确率: {float_acc*100:.1f}%')

# ===== Test char_0.bmp =====
img_test = cv2.imread(r'D:\MATLAB\PIC\single_word_debug\char_0.bmp', cv2.IMREAD_GRAYSCALE)
x_test = cv2.resize(img_test, (16, 32)).flatten() / 255.0

proba = model.predict_proba([x_test])[0]
pred = np.argmax(proba)
print(f'\n>>> 浮点模型预测: {classes[pred]} (idx={pred}, prob={proba[pred]:.4f})')

print('\nTop-8:')
top8 = np.argsort(proba)[-8:][::-1]
for i, idx in enumerate(top8):
    print(f'  {i+1}. [{idx:2d}] {classes[idx]:10s} prob={proba[idx]:.4f}')

# zh_xiang specific
xiang_idx = classes.index('zh_xiang')
print(f'\nzh_xiang(湘) rank: prob={proba[xiang_idx]:.4f}')

# Save the model for int16 comparison
import joblib
joblib.dump(model, 'float_model.pkl')
print('\n浮点模型已保存到 float_model.pkl')

# Now quantize the same model and run int16 inference on char_0.bmp
print('\n' + '='*60)
print('用本次训练的模型做 int16 量化推理')
print('='*60)

data = []
for i, (w, b) in enumerate(zip(model.coefs_, model.intercepts_)):
    s = max(np.max(np.abs(w)), 1e-10) / 32767.0
    wq = np.clip(np.round(w / s), -32768, 32767).astype(np.int16)
    bq = np.clip(np.round(b / s), -32768, 32767).astype(np.int16)
    data.append((wq, bq, int(1/s)))
    print(f'  Layer{i}: {w.shape} scale={int(1/s)}')

# Int16 inference
x_int = (x_test * 255).astype(np.int32)  # [0, 255]
for i in range(3):
    w = data[i][0].astype(np.int32)
    b = data[i][1].astype(np.int32)
    x_int = (x_int.dot(w) + b) >> 15
    if i < 2:
        x_int = np.maximum(x_int, 0).clip(0, 32767).astype(np.int32)
    else:
        # Output layer: no ReLU
        pass

pred_int = np.argmax(x_int)
print(f'\n>>> int16量化预测: {classes[pred_int]} (idx={pred_int}, score={x_int[pred_int]})')

top8_int = np.argsort(x_int)[-8:][::-1]
print('\nint16 Top-8:')
for i, idx in enumerate(top8_int):
    print(f'  {i+1}. [{idx:2d}] {classes[idx]:10s} score={x_int[idx]:6d}')
print(f'\nzh_xiang(湘) score: {x_int[xiang_idx]}')
