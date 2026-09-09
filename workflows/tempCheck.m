%% Compare the revised timing detector with the saved result
[newSteadyWindow, newTimingDiagnostics] = ...
    determineQuasiSteadyWindow( ...
        results.cfg, ...
        results.driverData, ...
        results.triggerData, ...
        results.dataData);

oldStart = results.steadyWindow.startTime;
newStart = newSteadyWindow.startTime;

fprintf('Previous start: %.6f s\n', oldStart);
fprintf('Revised start:  %.6f s\n', newStart);
fprintf('Start shift:    %+.3f ms\n', 1e3*(newStart - oldStart));

fprintf('Previous end:   %.6f s\n', results.steadyWindow.endTime);
fprintf('Revised end:    %.6f s\n', newSteadyWindow.endTime);
