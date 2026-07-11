%% 串口数据全帧恢复 v2 — 逐字节扫描，验证头部尾部
clear; close all;

filename = 'D:\MATLAB\盘古200Pro+开发板（MES2L676-200HP）配套资料\5_Software\串口调试助手\ReceivedTofile-COM9-2026_7_11_0-29-03.DAT';

fid = fopen(filename, 'rb');
raw = fread(fid, inf, '*uint8');
fclose(fid);
fprintf('文件: %d 字节\n', length(raw));

% 已知参数
CROP_W = 651; CROP_H = 251;
BIN_BPR = ceil(CROP_W/8);  % 82
BIN_LEN = BIN_BPR * CROP_H; % 20582
RAW_LEN = CROP_W * CROP_H * 2; % 326802

frames = {};
i = 1;
n = length(raw);

while i <= n - 12
    % 搜索 AA 55
    if raw(i) ~= 170 || raw(i+1) ~= 85
        i = i + 1;
        continue;
    end
    
    typ = raw(i+2);
    w = raw(i+3)*256 + raw(i+4);
    h = raw(i+5)*256 + raw(i+6);
    
    % 匹配已知尺寸
    if w ~= CROP_W || h ~= CROP_H
        i = i + 1;
        continue;
    end
    
    % 确定数据长度
    if typ == 7
        dlen = BIN_LEN;
    elseif typ == 8
        dlen = RAW_LEN;
    else
        i = i + 1;
        continue;
    end
    
    ds = i + 7;          % 数据起始 (1-indexed)
    de = ds + dlen - 1;  % 数据末尾
    
    if de + 2 > n
        i = i + 1;
        continue;
    end
    
    % 验证尾部 55 AA
    if raw(de+1) == 85 && raw(de+2) == 170
        frames{end+1} = struct('typ', typ, 'w', w, 'h', h, ...
                               'data', raw(ds:de), 'offset', i);
        fprintf('  [%d] type=%d offset=%d\n', length(frames), typ, i);
        i = de + 3;
    else
        i = i + 1;
    end
end

fprintf('\n共 %d 帧\n', length(frames));

% ===== 配对 =====
if isempty(frames)
    error('未找到任何帧！');
end

pairs = [];
k = 1;
while k < length(frames)
    if frames{k}.typ == 7 && frames{k+1}.typ == 8
        pairs(end+1, :) = [k, k+1];
        k = k + 2;
    else
        k = k + 1;
    end
end

fprintf('完整 BIN+RAW 对: %d 对\n', size(pairs,1));

% 丢弃最后一对
if size(pairs,1) > 1
    pairs = pairs(1:end-1, :);
    fprintf('保留 %d 对 (丢弃最后1对)\n', size(pairs,1));
end

% ===== 恢复图像 =====
outdir = fileparts(filename);

for p = 1:size(pairs,1)
    fb = frames{pairs(p,1)};
    fr = frames{pairs(p,2)};
    
    % --- BIN ---
    bin_img = zeros(fb.h, fb.w, 'uint8');
    for row = 1:fb.h
        for col = 1:8:fb.w
            bi = (row-1)*BIN_BPR + ceil(col/8);
            if bi > length(fb.data), break; end
            byte = fb.data(bi);
            for k = 0:7
                c = col + k;
                if c > fb.w, break; end
                bin_img(row, c) = 255 * bitget(byte, 8-k);
            end
        end
    end
    
    % --- RAW ---
    raw_rgb = zeros(fr.h, fr.w, 3, 'uint8');
    for row = 1:fr.h
        for col = 1:fr.w
            pi = (row-1)*fr.w*2 + (col-1)*2 + 1;
            if pi+1 > length(fr.data), break; end
            px = fr.data(pi)*256 + fr.data(pi+1);
            raw_rgb(row,col,1) = uint8(bitshift(bitand(px, 0xF800), -8));
            raw_rgb(row,col,2) = uint8(bitshift(bitand(px, 0x07E0), -3));
            raw_rgb(row,col,3) = uint8(bitshift(bitand(px, 0x001F), 3));
        end
    end
    
    % --- 显示 ---
    figure(1); clf;
    subplot(2,2,1); imshow(bin_img);  title(sprintf('BIN #%d', p));
    subplot(2,2,2); imshow(raw_rgb);  title(sprintf('RAW #%d', p));
    subplot(2,2,3); imhist(bin_img);  title('BIN直方图');
    
    white_pct = sum(bin_img(:) > 128) / numel(bin_img) * 100;
    fprintf('  第%d对: BIN白=%.1f%%\n', p, white_pct);
    
    imwrite(bin_img, fullfile(outdir, sprintf('pair%02d_bin.png', p)));
    imwrite(raw_rgb, fullfile(outdir, sprintf('pair%02d_raw.png', p)));
    
    if p < size(pairs,1), pause(0.3); end
end

fprintf('\n完成。%d 对已保存到 %s\n', size(pairs,1), outdir);
