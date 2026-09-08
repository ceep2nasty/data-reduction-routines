function reportSecondModeWindows(results)
%REPORTSECONDMODEWINDOWS Print a compact windowed second-mode summary.

fprintf('\nSecond-mode detection summary\n');
fprintf('%s\n', repmat('-', 1, 52));

for channelIndex = 1:numel(results.channels)
    found = results.found(:, channelIndex);
    fprintf('%s\n', results.channels(channelIndex));
    fprintf('  Detected: %d of %d windows\n', nnz(found), numel(found));
    fprintf('  Median frequency: %.2f kHz\n', ...
        median(results.frequency(found, channelIndex), 'omitnan') / 1e3);
    fprintf('  Median prominence: %.2f dB\n', ...
        median(results.prominenceDb(found, channelIndex), 'omitnan'));
    fprintf('  Median width: %.2f kHz\n', ...
        median(results.width(found, channelIndex), 'omitnan') / 1e3);
    fprintf('  Median fit R-squared: %.3f\n', ...
        median(results.fitRSquared(found, channelIndex), 'omitnan'));
end

fprintf('%s\n', repmat('-', 1, 52));
end
