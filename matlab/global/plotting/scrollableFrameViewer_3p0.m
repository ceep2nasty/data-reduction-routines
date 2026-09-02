function scrollableFrameViewer_3p0(data,startFrame,colorMapUse)
    % Create sample data
    data = data;  % Example: 20 frames
    frameIdx = startFrame;

    % Create figure
    fig = figure('Name', 'Frame Viewer', 'CloseRequestFcn', @onClose);
    ax = axes('Parent', fig);
    hImg = pcolor(ax, data(:,:,frameIdx)); shading interp
    colormap(ax, colorMapUse); colorbar;
    % axis image off;
    title(sprintf('Frame %d / %d', frameIdx, size(data, 3)));

    % Initialize app data
    setappdata(fig, 'data', data);
    setappdata(fig, 'frameIdx', frameIdx);
    setappdata(fig, 'hImg', hImg);
    setappdata(fig, 'shiftDown', false);
    setappdata(fig, 'getptsActive', false);
    setappdata(fig, 'xi_all', []);
    setappdata(fig, 'yi_all', []);
    setappdata(fig, 'cancelGetPts', false);

    % Set callbacks
    fig.WindowScrollWheelFcn = @(src, event) scrollFramesAndCLim(src, event);
    fig.WindowKeyPressFcn = @(src, event) keyPressHandler(src, event);
    fig.WindowKeyReleaseFcn = @(src, event) keyReleaseHandler(src, event);
end

function keyPressHandler(fig, event)
    switch event.Key
        case 'shift'
            setappdata(fig, 'shiftDown', true);

        case 'g'
            setappdata(fig, 'getptsActive', true);
            drawnow;
            collectPoints(fig);

        case 'return'  % plot selected points as thin red circles
            xi = getappdata(fig, 'xi_all');
            yi = getappdata(fig, 'yi_all');
            if ~isempty(xi)
                ax = get(getappdata(fig, 'hImg'), 'Parent');
                hold(ax, 'on');
                plot(ax, xi, yi, 'ro', 'MarkerSize', 6, 'LineWidth', 0.8);
                hold(ax, 'off');
                disp(['Plotted ', num2str(length(xi)), ' selected points.']);
            end
    end
end


function collectPoints(fig)
    % Async getpts: checks for "n" key to stop
    ax = get(getappdata(fig, 'hImg'), 'Parent');

    % Use waitforbuttonpress to manually loop getpts
    while ~getappdata(fig, 'cancelGetPts') && isvalid(fig)
        try
            [xi, yi] = getpts(ax);
            if isempty(xi) || getappdata(fig, 'cancelGetPts')
                break;
            end

            xi_all = getappdata(fig, 'xi_all');
            yi_all = getappdata(fig, 'yi_all');
            setappdata(fig, 'xi_all', [xi_all; xi(:)]);
            setappdata(fig, 'yi_all', [yi_all; yi(:)]);
            disp(['Points added. Total now: ', num2str(length([xi_all; xi]))]);

        catch
            break;
        end
    end

    % setappdata(fig, 'getptsActive', false);
end

function keyReleaseHandler(fig, event)
    if strcmp(event.Key, 'shift')
        setappdata(fig, 'shiftDown', false);
    end
end

function scrollFramesAndCLim(fig, event)
    data = getappdata(fig, 'data');
    hImg = getappdata(fig, 'hImg');
    frameIdx = getappdata(fig, 'frameIdx');
    shiftDown = getappdata(fig, 'shiftDown');
    delta = event.VerticalScrollCount;

    if shiftDown
        % Adjust color limits
        clim = caxis(hImg.Parent);
        range = diff(clim);
        step = 0.05 * range * delta;
        caxis(hImg.Parent, [clim(1) + step  clim(2) - step] );
    else
        % Change frame
        numFrames = size(data, 3);
        newIdx = min(max(1, frameIdx + delta), numFrames);
        if newIdx ~= frameIdx
            set(hImg, 'CData', data(:,:,newIdx));
            title(hImg.Parent, sprintf('Frame %d / %d', newIdx, numFrames));
            setappdata(fig, 'frameIdx', newIdx);
        end
    end
end

function onClose(fig, ~)
    % Display points when figure is closed
    xi = getappdata(fig, 'xi_all');
    yi = getappdata(fig, 'yi_all');
    
    if isempty(xi)
        disp('No points selected.');
    else
        disp('All selected points:');
        disp(table(xi, yi));
    end

    % Save to workspace
    assignin('base', 'xi', xi);
    assignin('base', 'yi', yi);

    delete(fig);
end