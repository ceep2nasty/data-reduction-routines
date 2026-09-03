%{

@author: Benjamin Bemis Ph.D Student, <bbemis@nd.edu> 
Advisor: Dr Juliano

Description:
This script converts Perception files to .mat files and then exports them to a local folder.
This must be run on Windows   


Version: 2.0
Updated: 7/24/2024

%}


%% Preparation of the Workspace

clear all
clc
close all

if(~isdeployed)
  cd(fileparts(matlab.desktop.editor.getActiveFilename));
end

% Make sure to update this for the machine that you are working on.
cd; 

% basepath is the parent directory of data, savepath
basepath = cd; % Windows

% datapath should be the path to raw pnrf files
datapath = 'C:\Users\coled_agkeohi\Notre Dame\PCB_test_workflow_data\raw_pnrf_files';

%savepath is the path you will send exported files to
savepath = 'C:\Users\coled_agkeohi\Notre Dame\PCB_test_workflow_data' ;
addpath(datapath);



%% PNRF Converter Script

% This must be run on windows but can be commented out once the initial conversion is completed for operation on linux

blocks = {'alignment_60psi_feb2026'}; % This is a stand in until you collect the data

exportpath = ([savepath '\matlab_exports\']);

if ~isfolder(exportpath)
    mkdir(exportpath);
end

directory_status = mkdir(exportpath);
cd(datapath)
pnrf_converter(blocks,exportpath);
cd(exportpath);


%% Functions

function [] = pnrf_converter(blocks,savepath)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% PNRF_converter
% Save this code in a folder with pNRF files. 
% Set the 'blocks' cell to the name of the pNRF files you are looking to convert. 
% The code will find the counts of the files in numerical order. 
% It will also determine which cartridges are being used, in the order they are used and turned on
% during the experiment so double check which channels are turned on in Perception. 
% Finally, it will figure out which channels are used. It should sort that by number. 
% A lot of the core code for extracting the data from the pNRF file is
% modified from the following link. 
% You need to download a file from this link:
% https://www.hbm.com/en/7557/hardware-and-software-interfacing-with-genesis-high-speed/
% Somewhere in the middle of the page is the pNRF reader toolkit. 
% Read the manual and example code. 
% Install the toolkit, the last link on the above webpage.
% Then run this code.
% Author: Erik Hoberg <ehoberg@nd.edu>
% Version: 1.11
% Version Date: 06/12/2024
% Updated: Benjamin Bemis <bbemis@nd.edu>
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% INPUTS
%blocks: input the handle of your calibration files and test files here.
%Make sure 'handle001.PNRF' exists! or adjust line 47 to an existant file
%with that handle.
%
%exportpath: input the file location of the folder that you wish to save
%your .mat file exports.
%
%OUTPUTS
% A .mat file saved in a seperate "matlab_exports" folder in the same base directory as the folder that this code exists. Each file contains
% all the files counted for that handle in sequential order from 1--999. 

FromDisk = actxserver('Perception.Loaders.pNRF');
for loopd=1:length(blocks)
    clear Perception_Raw
    name=sprintf(blocks{loopd});
    theFiles = dir([name '*.pNRF']);
    for loopb=1:length(theFiles)
        RecordingName =[theFiles(loopb).name];
        if isfile(RecordingName)==1
            Data = FromDisk.LoadRecording(RecordingName);
            for counta=1:20 %Finding which cartridges to read
                TFa=isempty(Data.Recorders.Item(counta));
                if TFa==0
                    Recorder = Data.Recorders.Item(counta);%
                    Channels = Recorder.Channels;
                    for loopa=1:20 %Finding which channels used on a cartridge and saving them
                        TFbb=isempty(Channels.Item(loopa));
                        if TFbb==0
                            Channel = Channels.Item(loopa);
                            ItfData = Channel.DataSource(3);
                            Sweeps = ItfData.Sweeps;
                            dStartTime = Sweeps.StartTime;
                            dEndTime = Sweeps.EndTime;
                            SegmentsOfData = ItfData.Data(dStartTime, dEndTime);
                            Segment = SegmentsOfData.Item(1);
                            NumberOfSamples = Segment.NumberOfSamples;
                            WaveformData = Segment.Waveform(5, 1, NumberOfSamples, 1)';
                            TFb=any(WaveformData);
                        else
                            TFb=0;
                        end
                        if TFb==1
                            tEnd = Segment.StartTime+(NumberOfSamples - 1)*Segment.SampleInterval;
                            t = Segment.StartTime: Segment.SampleInterval:tEnd;
                            Perception_Raw(loopb,counta).time=t;
                            Perception_Raw(loopb,counta).channel(:,loopa)=WaveformData;
                        end
                    end
                end
            end
        else
            fprintf(['\n' RecordingName ' Not valid!\n'])
        end
    end
    if exist('Perception_Raw','var') == 1
        save([savepath blocks{loopd} '.mat'],'Perception_Raw','-v7.3')
    else
        fprintf(['Variable Perception_Raw not created for ' name '\n'])
    end
end
end
