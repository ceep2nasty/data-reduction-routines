function makeMP4_letterbox(folderPath, FPS, outputFilename)
% makeMP4_letterbox - Create MP4 video 1920x1080 with aspect ratio preserved and black padding.
%
% Usage:
%   makeMP4_letterbox('folderWithJPEGs', 10, 'outputVideo.mp4')
%
% Output fixed to 1920x1080 (multiples of 8), no distortion.

TARGET_W = 1920*4;
TARGET_H = 1080*4;

if nargin < 3
    error('Usage: makeMP4_letterbox(folderPath, FPS, outputFilename)');
end

if ~endsWith(outputFilename, '.mp4')
    error('Output filename must end with .mp4');
end

imageFiles = dir(fullfile(folderPath, '*.jpeg'));
if isempty(imageFiles)
    error('No JPEG files found in folder: %s', folderPath);
end

% Sort by time saved (modification time)
[~, idx] = sort([imageFiles.datenum]);
imageFiles = imageFiles(idx);

% Create VideoWriter
v = VideoWriter(outputFilename, 'MPEG-4');
v.FrameRate = FPS;
open(v);

for k = 1:length(imageFiles)
    img = imread(fullfile(folderPath, imageFiles(k).name));
    if size(img,3) == 1
        img = repmat(img, [1 1 3]);
    end

    [h, w, ~] = size(img);
    scale = min(TARGET_W / w, TARGET_H / h);
    newW = round(w * scale);
    newH = round(h * scale);

    imgResized = imresize(img, [newH, newW]);

    % Create black background
    frame = zeros(TARGET_H, TARGET_W, 3, 'uint8');

    % Compute top-left corner for centered placement
    x_offset = floor((TARGET_W - newW)/2) + 1;
    y_offset = floor((TARGET_H - newH)/2) + 1;

    % Place resized image into black frame
    frame(y_offset:y_offset+newH-1, x_offset:x_offset+newW-1, :) = imgResized;

    writeVideo(v, frame);
end

close(v);
fprintf('MP4 video created with letterboxing: %s\n', outputFilename);
end
