#!/usr/bin/env python3
"""RC low-pass filter calculator GUI."""

from __future__ import annotations

import math
import tkinter as tk
from tkinter import messagebox, ttk

from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg
from matplotlib.figure import Figure

from lp_filter_tool import (
    ValueErrorWithHint,
    analyze_filter,
    parse_value,
    pretty_si,
    transfer_function,
)


def _logspace(start: float, stop: float, points: int) -> list[float]:
    """Return a log-spaced list without numpy."""
    if points < 2:
        raise ValueErrorWithHint("Point count must be >= 2")
    if start <= 0 or stop <= start:
        raise ValueErrorWithHint("Frequency range is invalid")
    log_start = math.log10(start)
    log_stop = math.log10(stop)
    step = (log_stop - log_start) / (points - 1)
    return [10 ** (log_start + step * i) for i in range(points)]


class RCFilterApp:
    def __init__(self) -> None:
        self.root = tk.Tk()
        self.root.title("RC Low-pass Filter Tool")
        self._build_widgets()

    def _build_widgets(self) -> None:
        main = ttk.Frame(self.root, padding=12)
        main.grid(row=0, column=0, sticky="nsew")
        self.root.columnconfigure(0, weight=1)
        self.root.rowconfigure(0, weight=1)

        # parameter inputs
        form = ttk.LabelFrame(main, text="Parameters")
        form.grid(row=0, column=0, sticky="nsew")

        labels = [
            ("R1 [ohm]", "10k"),
            ("R2 [ohm] (optional)", "100k"),
            ("C [F]", "100n"),
            ("f min [Hz]", "10"),
            ("f max [Hz]", "100000"),
            ("Points", "300"),
        ]
        self.entry_vars: list[tk.StringVar] = []
        for idx, (label, default) in enumerate(labels):
            ttk.Label(form, text=label).grid(row=idx, column=0, sticky="w", pady=2)
            var = tk.StringVar(value=default)
            entry = ttk.Entry(form, textvariable=var, width=20)
            entry.grid(row=idx, column=1, sticky="ew", pady=2)
            self.entry_vars.append(var)

        calc_btn = ttk.Button(form, text="Calculate", command=self._on_calculate)
        calc_btn.grid(row=len(labels), column=0, columnspan=2, sticky="ew", pady=(6, 0))

        # results
        result_frame = ttk.LabelFrame(main, text="Results")
        result_frame.grid(row=1, column=0, sticky="nsew", pady=(12, 0))
        self.result_label = ttk.Label(
            result_frame,
            text="Enter parameters and press Calculate.",
            justify="left",
        )
        self.result_label.grid(row=0, column=0, sticky="w")

        # graph
        graph_frame = ttk.LabelFrame(main, text="Frequency vs Gain")
        graph_frame.grid(row=0, column=1, rowspan=2, sticky="nsew", padx=(12, 0))
        main.columnconfigure(1, weight=1)
        main.rowconfigure(1, weight=1)

        self.figure = Figure(figsize=(6, 4), dpi=100)
        self.ax = self.figure.add_subplot(111)
        self.ax.set_xscale("log")
        self.ax.set_xlabel("Frequency [Hz]")
        self.ax.set_ylabel("|H| [V/V]")
        self.ax.grid(True, which="both", linestyle="--", alpha=0.4)
        self.canvas = FigureCanvasTkAgg(self.figure, master=graph_frame)
        self.canvas.get_tk_widget().grid(row=0, column=0, sticky="nsew")
        graph_frame.rowconfigure(0, weight=1)
        graph_frame.columnconfigure(0, weight=1)

    def _on_calculate(self) -> None:
        r1_str, r2_str, c_str, fmin_str, fmax_str, points_str = [
            var.get().strip() for var in self.entry_vars
        ]
        try:
            r1 = parse_value(r1_str)
            c = parse_value(c_str)
            r2 = parse_value(r2_str) if r2_str else None
            freq_min = parse_value(fmin_str)
            freq_max = parse_value(fmax_str)
            points = int(points_str)

            result = analyze_filter(r1, c, r2)
            freqs = _logspace(freq_min, freq_max, points)
            gains = [abs(transfer_function(r1, c, r2, f)) for f in freqs]
        except (ValueErrorWithHint, ValueError) as exc:
            messagebox.showerror("Error", str(exc))
            return

        summary = [
            f"R1 : {pretty_si(result.r1, 'ohm')}",
            f"R2 : {pretty_si(result.r2, 'ohm')}" if result.r2 else "R2 : open",
            f"C  : {pretty_si(result.c, 'F')}",
            f"R_th : {pretty_si(result.r_th, 'ohm')}",
            f"tau : {pretty_si(result.tau, 's')}",
            f"f_c : {pretty_si(result.fc, 'Hz')}",
            f"DC gain : {result.dc_gain:.4f} V/V",
        ]
        self.result_label.config(text="\n".join(summary))
        self._update_plot(freqs, gains)

    def _update_plot(self, freqs: list[float], gains: list[float]) -> None:
        self.ax.clear()
        self.ax.set_xscale("log")
        self.ax.plot(freqs, gains, color="#1f77b4")
        self.ax.set_xlabel("Frequency [Hz]")
        self.ax.set_ylabel("|H| [V/V]")
        self.ax.grid(True, which="both", linestyle="--", alpha=0.4)
        self.canvas.draw_idle()

    def run(self) -> None:
        self.root.mainloop()


if __name__ == "__main__":
    RCFilterApp().run()
