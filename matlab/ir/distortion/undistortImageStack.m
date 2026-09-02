function Data_Distort_Corrected = undistortImageStack(Calibration_Data, cameraParams)
% undistortImageStack - Corrects lens distortion for a stack of calibration images
%
% Inputs:
%   Calibration_Data    - 3D matrix of distorted images (HxWxN)
%   cameraParams        - Camera parameters object from calibration
%
% Output:
%   Data_Distort_Corrected - 3D matrix of undistorted images (same size as input)

    % Initialize output
    [H, W, numFrames] = size(Calibration_Data);
    Data_Distort_Corrected = zeros(H, W, numFrames, 'like', Calibration_Data);

    % Loop over all frames and undistort
    for i = 1:numFrames
        distortedFrame = Calibration_Data(:,:,i);
        Data_Distort_Corrected(:,:,i) = undistortImage(distortedFrame, cameraParams);
        if mod(i, 100) == 0 || i == 1 || i == numFrames
            fprintf('Undistorted frame %d of %d\n', i, numFrames);
        end
    end
end


%Example to run this code
% cd(LoadMain);
% load('CameraParameters_Calibration.mat');
% cd(MainDir);
% Data_Distort_Corrected = undistortImageStack(Calibration_Data, cameraParams);
