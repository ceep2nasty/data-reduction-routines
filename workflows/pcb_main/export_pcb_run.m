%% EXPORT_PCB_RUN Package one complete recording for sharing.
% Edit USER INPUTS below, then run this script. NaN/empty metadata is saved
% as unknown. PCB voltage is saved unchanged; its calibration may remain NaN.
% The driver absolute-pressure offset must be specified before export.
% No cropping, smoothing, resampling, or independent time-zero shifts.

%% USER INPUTS — FILE LOCATIONS
cfg = struct();
cfg.input.file = "C:\Users\coled\Notre Dame\heatedCone_F26\AFOSR_Heated_Cone_Jan2026\PCB_Data\Iso_90psi\Iso_90psi_001.txt";
cfg.output.file = "C:\Users\coled\Notre Dame\heatedCone_F26\pcb_share\Jan2026\Isothermal_90psi";
cfg.input.variable = "Perception_Raw"; % Legacy MAT variable, if needed.

%% USER INPUTS — RUN METADATA (NaN/empty = TO FILL IN)
cfg.metadata.runId = "isothermal_90psi_jan2026";
cfg.metadata.dateConducted = "2026-01-20"; % TO FILL IN: YYYY-MM-DD
cfg.metadata.experimentTitle = "Isothermal 90 psi"; % TO FILL IN: e.g. All Hot
cfg.metadata.driver.nominalT0_K = 438.706;
cfg.metadata.driver.nominalP0_Pa = 620528; % Absolute
cfg.metadata.driver.recordedT0_K = 438.706;
cfg.metadata.driver.recordedP0_Pa = 620528; % Absolute, entered separately
cfg.metadata.driver.recordedValueSource = "Logbook"; % Instrument/logbook
cfg.metadata.vacuumPressure_KPa = 0.6; % Absolute
cfg.metadata.pressureReference = "absolute";
cfg.metadata.notes = "";

%% USER INPUTS — CHANNEL MAPPING / GEOMETRY
cfg.channels.recorderLabels = ["A", "B", "C", "D"];
cfg.channels.maxPerRecorder = 8;
janOrder = ["D01", "D02", "C01", "D05", "D08", "D07", "D06"];
febOrder = ["C01", "C02", "C03", "C04", "D01", "D02", "D03", "D04"];
cfg.channels.pcb = janOrder;
cfg.channels.positionIndex = 1:7;
cfg.channels.sensorNumber = 2:8; % Original sensor numbering
cfg.channels.axialDistance_cm = [31, 41, 52, 63, 75, 86, 97]; % PLACEHOLDERS: replace later
cfg.channels.positionStatus = "placeholder"; % Change to measured when set
cfg.channels.driver = "A01";
cfg.channels.trigger = "B01";

%% USER INPUTS — SAMPLING RATES (Hz)
% NaN = infer from recorded timestamps; enter a value to check against them.
cfg.channels.pcbSamplingRate_Hz = repmat(2e6, 1, 7);
cfg.channels.driverSamplingRate_Hz = 250e3;
cfg.channels.triggerSamplingRate_Hz = 250e3;

%% USER INPUTS — PCB CALIBRATION (OPTIONAL; NaN = UNKNOWN)
% One constant per PCB, in the channel order above. Stored only, NOT applied.
% Convention: pressure change [Pa] = voltage change [V] * constant [Pa/V].
% This constant alone does not establish an absolute-pressure baseline.
cfg.calibration.pcb.constant_Pa_per_V = nan(1, 7);

%% USER INPUTS — DRIVER CALIBRATION (OFFSET REQUIRED BEFORE EXPORT)
% Existing driver calibration from plotPcbTraces / plotQuasiSteadyPcbTraces.
cfg.calibration.driver.voltage_V = [-8.08 -0.73153 -3.3495 4.8098 -7.4776 -0.5246];
cfg.calibration.driver.pressure_Pa = ...
    [51.7 87.8*6.89476 61*6.89476 150*6.89476 14.6*6.89476 93*6.89476] * 1000;
% TO FILL IN: 0 if calibration above is absolute; reference pressure if gauge.
cfg.calibration.driver.offsetToAbsolutePa = 0;

%% EXECUTION — no manual inputs below this line
here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, 'functions'));
runData = exportPcbRun(cfg);
