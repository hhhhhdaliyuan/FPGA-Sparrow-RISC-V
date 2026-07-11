%% DEBUG: check first bytes
filename = 'D:\MATLAB\盘古200Pro+开发板（MES2L676-200HP）配套资料\5_Software\串口调试助手\ReceivedTofile-COM9-2026_7_11_0-29-03.DAT';
fid = fopen(filename, 'rb');
raw = fread(fid, inf, '*uint8');
fclose(fid);

fprintf('raw(90:96) = ');
for k = 90:96
    fprintf('%d ', raw(k));
end
fprintf('\n');

fprintf('class(raw) = %s\n', class(raw));
fprintf('raw(90)==170: %d\n', raw(90)==170);
fprintf('raw(91)==85: %d\n', raw(91)==85);
fprintf('raw(90)==0xAA: %d\n', raw(90)==0xAA);

% Direct extraction using known offsets
BIN_BPR = 82; BIN_LEN = 82*251; RAW_LEN = 651*251*2;
offsets = [89, 20726, 347601, 368238, 695113, 715750];
for idx = 1:length(offsets)
    o = offsets(idx) + 1;  % 1-indexed
    t = raw(o+2);
    w = raw(o+3)*256 + raw(o+4);
    h = raw(o+5)*256 + raw(o+6);
    fprintf('offset %d: type=%d w=%d h=%d\n', offsets(idx), t, w, h);
end
