function ax = insetPlot(pos)
    % pos : [left bottom width height] in normalized figure units (0-1)
    
    ax = axes('Position', pos);   % create inset axes
    grid(ax, 'on');

    % Move tick marks inside
    ax.TickDir = 'in';
    ax.XAxis.TickLength = [0.02 0.02];
    ax.YAxis.TickLength = [0.02 0.02];

    % Turn off y tick labels
    ax.YTickLabel = [];
end