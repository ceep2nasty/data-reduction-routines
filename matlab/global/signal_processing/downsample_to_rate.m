function [time_down, Property_down] = downsample_to_rate(time_vector, Property_Vector, Target_frequency_rate)
% DOWNSAMPLE_TO_RATE Downsamples time and signal arrays to a target sampling rate.
%   Inputs:
%       time_array - original time vector
%       T_infty    - original signal vector (same length as time_array)
%       target_rate - desired sampling rate in Hz
%   Outputs:
%       t_down - downsampled time vector
%       T_down - downsampled signal vector

% Define new time vector based on target rate
t_start = time_vector(1);
t_end   = time_vector(end);
dt_target = 1/Target_frequency_rate;
time_down = t_start:dt_target:t_end;

% Interpolate T_infty onto new time vector
Property_down = interp1(time_vector, Property_Vector, time_down, 'linear');

end