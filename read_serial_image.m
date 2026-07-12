%% 串口恢复 (修复uint8饱和问题)

filename = 'D:\MATLAB\盘古200Pro+开发板（MES2L676-200HP）配套资料\5_Software\串口调试助手\ReceivedTofile-COM9-2026_7_10_23-36-09.DAT';

fid = fopen(filename, 'rb');
raw = fread(fid, inf, 'uint8=>uint8');
fclose(fid);
fprintf('文件: %d 字节\n', length(raw));

cnt = 0;
i = 1;
while i < length(raw) - 12
    if raw(i)~=0xAA || raw(i+1)~=0x55, i=i+1; continue; end
    t = raw(i+2); if t~=7 && t~=8, i=i+1; continue; end
    
    % !! 关键修复: 转double防止uint8饱和 !!
    w = double(raw(i+3)) * 256 + double(raw(i+4));
    h = double(raw(i+5)) * 256 + double(raw(i+6));
    
    if w<10 || w>2000 || h<10 || h>2000, i=i+1; continue; end
    
    if t==7, dlen = ceil(w/8) * h; else dlen = w * h * 2; end
    
    ok = false;
    for hh = [7 9 11]
        ds = i + hh; de = ds + dlen - 1;
        if de+2 <= length(raw) && raw(de+1)==0x55 && raw(de+2)==0xAA
            cnt = cnt + 1;
            fprintf('\n=== 图#%d: type=%d %dx%d hh=%d ===\n', cnt, t, w, h, hh);
            
            pck = raw(ds:de);
            if t==7
                img = zeros(h,w,'uint8');
                bpr = ceil(w/8);
                for r = 1:h
                    for c = 1:8:w
                        b = pck((r-1)*bpr + ceil(c/8));
                        for k = 0:7
                            if c+k <= w, img(r,c+k) = bitget(b,8-k)*255; end
                        end
                    end
                end
                figure('Name',sprintf('二值图 %dx%d',w,h),'Position',[100 100 800 400]);
                imshow(img); title(sprintf('二值图 %dx%d',w,h));
                fprintf('白色占比: %.1f%%\n', sum(img(:)==255)/(w*h)*100);
            else
                img = zeros(h,w,3,'uint8');
                p = 1;
                for r = 1:h
                    for c = 1:w
                        px = double(pck(p))*256 + double(pck(p+1)); p = p+2;
                        img(r,c,1) = bitshift(bitand(px,63488),-8);
                        img(r,c,2) = bitshift(bitand(px,2016),-3);
                        img(r,c,3) = bitshift(bitand(px,31),3);
                    end
                end
                figure('Name',sprintf('原图 %dx%d',w,h),'Position',[700 100 800 400]);
                imshow(img); title(sprintf('原图 %dx%d',w,h));
            end
            drawnow;
            i = de + 3; ok = true; break;
        end
    end
    if ~ok, i=i+1; end
end

if cnt==0, error('未找到有效数据!'); end
fprintf('\n共 %d 张图\n', cnt);
