"""Shared display labels; x in nominal cosine labels is specimen x/L_active."""

import sys
from pathlib import Path

# Shared readers remain in the parent subroutines directory.
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import re
from io import BytesIO
from pathlib import Path


def save_figure(fig, path):
    """Write rendered PNG bytes without opening an existing PNG for reading."""
    buffer = BytesIO()
    fig.savefig(buffer, format="png", dpi=300)
    path = Path(path)
    temporary = path.with_suffix(".tmp.png")
    temporary.write_bytes(buffer.getvalue())
    temporary.replace(path)


def display_label(text):
    replacements = {
        "k1_a2_k2_a1": "2 cos(2πx) + 1 cos(4πx)",
        "k1_a1": "1 cos(2πx)", "k1_a2": "2 cos(2πx)",
        "k2_a1": "1 cos(4πx)",
    }
    for source, target in replacements.items():
        text = text.replace(source, target)
    text = re.sub(r"unconstrained", "Fixed-Free", text, flags=re.I)
    text = re.sub(r"(?<!un)constrained", "Fixed-Fixed", text, flags=re.I)
    text = re.sub(r"pass 1\b", "Top Pass", text, flags=re.I)
    text = re.sub(r"pass 2\b", "Bottom Pass", text, flags=re.I)
    text = re.sub(r"2\s*[×?*]\s*", "2 * ", text)
    # Capitalize prose without altering mathematical x or cosine notation.
    for word in ("raw", "spectra", "amplitude", "linearity", "superposition", "combined",
                 "empirical", "reconstruction", "displacement", "original", "target", "roi",
                 "centered", "known", "imposed", "shape", "fitted", "modal", "contributions",
                 "active", "window", "residual", "membrane", "bending", "optical", "shift",
                 "profiles", "top", "bottom", "pass"):
        text = re.sub(r"\b" + word + r"\b", word.upper() if word == "roi" else word.capitalize(),
                      text, flags=re.I)
    text = re.sub(r"\b(Top|Bottom) Pass\s*[,—:]\s*\1\b", r"\1 Pass", text, flags=re.I)
    return text


def format_figure(fig, raw=False):
    if fig._suptitle:
        fig._suptitle.set_text(display_label(fig._suptitle.get_text()))
    for ax in fig.axes:
        ax.set_title(display_label(ax.get_title()))
        for line in ax.lines:
            line.set_label(display_label(line.get_label()))
        legend = ax.get_legend()
        if legend:
            if raw:
                legend.remove()
            else:
                for text in legend.get_texts():
                    text.set_text(display_label(text.get_text()))
