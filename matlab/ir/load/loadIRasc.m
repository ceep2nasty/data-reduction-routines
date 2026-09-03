function Frames = loadIRasc(LoadDataDir,IR_Folder,NumFrames)
cd(LoadDataDir)
list = dir(fullfile(IR_Folder,'*.asc'));
Frames = zeros(640,512,NumFrames,'single');

for k = 1:NumFrames
    d = importdata(fullfile(IR_Folder,list(k).name));
    x = d.data(:,1) + d.data(:,2)/100;
    Frames(:,:,k) = fliplr(reshape(x,[640,512]));
    if mod(k,20)==0
        disp(['Loaded ',num2str(k),' of ',num2str(NumFrames)]);
    end
end