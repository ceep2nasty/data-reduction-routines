"""Apply shared styling after plotting: format_plot(fig, legend_loc='upper right')."""

from pathlib import Path

from matplotlib import font_manager
from matplotlib.text import Text

# Register user-installed fonts directly, including in sessions with an old cache.
FONT_DIR = Path.home() / ".local/share/fonts/times-new-roman"
for font_path in FONT_DIR.glob("*.ttf"):
    font_manager.fontManager.addfont(str(font_path))

# Edit these defaults once to style every caller. Sizes are in points.
DEFAULTS = {
    "font_family": "Times New Roman",
    "font_size": 12,
    "title_size": 16,
    "label_size": 14,
    "tick_size": 12,
    "legend_size": 11,
    "legend": None,  # None preserves existing legends; True creates; False removes.
    "legend_loc": None,  # None preserves each plot's chosen location.
    "legend_frame": True,
    "legend_columns": 1,
    "grid": None,  # None preserves the plot's grid; True/False overrides it.
    "figure_size": None,  # Optional (width, height) in inches.
}


def format_plot(figure=None, **overrides):
    """Style an existing Figure and return it, ready for show() or savefig().

    Omit figure to use the current figure. Keyword arguments override DEFAULTS.
    Example: format_plot(fig, font_size=20, legend=True, legend_loc='best').
    Specific title/label/tick/legend sizes take precedence over font_size.
    Times New Roman must be installed; Matplotlib otherwise uses a fallback.
    """
    import matplotlib.pyplot as plt

    unknown = overrides.keys() - DEFAULTS.keys()
    if unknown:
        raise TypeError(f"Unknown plot format options: {', '.join(sorted(unknown))}")
    settings = DEFAULTS | overrides
    figure = plt.gcf() if figure is None else figure
    if settings["figure_size"] is not None:
        figure.set_size_inches(*settings["figure_size"])
    for text in figure.findobj(match=Text):
        text.set_fontfamily(settings["font_family"])
        text.set_fontsize(settings["font_size"])
    for ax in figure.axes:
        for title in (ax.title, ax._left_title, ax._right_title):
            title.set_fontsize(settings["title_size"])
        for axis in (ax.xaxis, ax.yaxis):
            axis.label.set_fontsize(settings["label_size"])
            axis.get_offset_text().set_fontsize(settings["tick_size"])
            for tick in axis.get_ticklabels(minor=False) + axis.get_ticklabels(minor=True):
                tick.set_fontsize(settings["tick_size"])
        if settings["grid"] is not None:
            ax.grid(settings["grid"])
        legend = ax.get_legend()
        if settings["legend"] is False:
            if legend is not None:
                legend.remove()
            continue
        if legend is None and settings["legend"] is True:
            handles, labels = ax.get_legend_handles_labels()
            if handles:
                legend = ax.legend(loc=settings["legend_loc"] or "best")
        if legend is not None:
            if settings["legend_loc"] is not None:
                legend.set_loc(settings["legend_loc"])
            legend.set_frame_on(settings["legend_frame"])
            legend.set_ncols(settings["legend_columns"])
            for text in [*legend.get_texts(), legend.get_title()]:
                text.set_fontfamily(settings["font_family"])
                text.set_fontsize(settings["legend_size"])
    figure.canvas.draw_idle()
    return figure
