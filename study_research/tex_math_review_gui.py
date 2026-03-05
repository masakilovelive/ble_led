import os
import queue
import shutil
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

import tkinter as tk
from tkinter import filedialog, messagebox, ttk

SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))

from tex_math_compile import (  # noqa: E402
    build_output_path,
    convert_docx,
    iter_docx_files,
    resolve_tex_bin,
)


DEFAULT_DPI_INLINE = 200
DEFAULT_DPI_DISPLAY = 250
DEFAULT_INLINE_SCALE = 1.0
DEFAULT_DISPLAY_SCALE = 1.0


def export_pdf(docx_path, pdf_path):
    ps = shutil.which("powershell") or shutil.which("pwsh")
    if not ps:
        raise RuntimeError("PowerShell not found.")
    script = (
        "param([string]$InputDocx,[string]$OutputPdf)\n"
        "$ErrorActionPreference = 'Stop'\n"
        "$word = New-Object -ComObject Word.Application\n"
        "$word.Visible = $false\n"
        "$word.DisplayAlerts = 0\n"
        "try {\n"
        "  $doc = $word.Documents.Open($InputDocx)\n"
        "  $doc.ExportAsFixedFormat($OutputPdf, 17)\n"
        "  $doc.Close()\n"
        "} finally {\n"
        "  $word.Quit()\n"
        "}\n"
    )
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".ps1", mode="w", encoding="utf-8")
    try:
        tmp.write(script)
        tmp.close()
        subprocess.run(
            [
                ps,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                tmp.name,
                "-InputDocx",
                str(docx_path),
                "-OutputPdf",
                str(pdf_path),
            ],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
    finally:
        try:
            os.unlink(tmp.name)
        except OSError:
            pass


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("TeX Math Compile")
        self.geometry("900x600")

        self.input_var = tk.StringVar(value=str(Path.cwd()))
        self.output_var = tk.StringVar(value="")
        self.suffix_var = tk.StringVar(value="_compiled")
        self.recursive_var = tk.BooleanVar(value=False)
        self.skip_var = tk.BooleanVar(value=True)
        self.status_var = tk.StringVar(value="Idle")
        self.inline_scale_var = tk.StringVar(value=str(DEFAULT_INLINE_SCALE))
        self.display_scale_var = tk.StringVar(value=str(DEFAULT_DISPLAY_SCALE))

        self.queue = queue.Queue()
        self.worker = None
        self.outputs = []

        self._build_ui()

    def _build_ui(self):
        pad = {"padx": 8, "pady": 6}

        frame = ttk.Frame(self)
        frame.pack(fill="x", **pad)

        ttk.Label(frame, text="Input folder").grid(row=0, column=0, sticky="w")
        ttk.Entry(frame, textvariable=self.input_var, width=70).grid(
            row=0, column=1, sticky="we"
        )
        ttk.Button(frame, text="Browse", command=self._browse_input).grid(
            row=0, column=2, sticky="e"
        )

        ttk.Label(frame, text="Output folder (optional)").grid(row=1, column=0, sticky="w")
        ttk.Entry(frame, textvariable=self.output_var, width=70).grid(
            row=1, column=1, sticky="we"
        )
        ttk.Button(frame, text="Browse", command=self._browse_output).grid(
            row=1, column=2, sticky="e"
        )

        options = ttk.Frame(self)
        options.pack(fill="x", **pad)
        ttk.Checkbutton(options, text="Recursive", variable=self.recursive_var).pack(
            side="left"
        )
        ttk.Checkbutton(options, text="Skip existing", variable=self.skip_var).pack(
            side="left", padx=10
        )
        ttk.Label(options, text="Suffix").pack(side="left")
        ttk.Entry(options, textvariable=self.suffix_var, width=15).pack(
            side="left", padx=6
        )
        ttk.Label(options, text="Inline scale").pack(side="left", padx=(10, 0))
        ttk.Entry(options, textvariable=self.inline_scale_var, width=6).pack(
            side="left", padx=6
        )
        ttk.Label(options, text="Display scale").pack(side="left")
        ttk.Entry(options, textvariable=self.display_scale_var, width=6).pack(
            side="left", padx=6
        )

        actions = ttk.Frame(self)
        actions.pack(fill="x", **pad)
        ttk.Button(actions, text="Convert Folder", command=self._start_convert).pack(
            side="left"
        )
        ttk.Button(actions, text="Open Selected", command=self._open_selected).pack(
            side="left", padx=10
        )
        ttk.Button(actions, text="Export PDF", command=self._export_selected).pack(
            side="left"
        )
        ttk.Label(actions, textvariable=self.status_var).pack(side="right")

        list_frame = ttk.Frame(self)
        list_frame.pack(fill="both", expand=True, **pad)
        self.listbox = tk.Listbox(list_frame)
        self.listbox.pack(side="left", fill="both", expand=True)
        scrollbar = ttk.Scrollbar(list_frame, orient="vertical", command=self.listbox.yview)
        scrollbar.pack(side="right", fill="y")
        self.listbox.config(yscrollcommand=scrollbar.set)

    def _browse_input(self):
        path = filedialog.askdirectory()
        if path:
            self.input_var.set(path)

    def _browse_output(self):
        path = filedialog.askdirectory()
        if path:
            self.output_var.set(path)

    def _start_convert(self):
        if self.worker and self.worker.is_alive():
            messagebox.showinfo("Working", "Conversion already running.")
            return

        input_dir = Path(self.input_var.get().strip())
        if not input_dir.exists() or not input_dir.is_dir():
            messagebox.showerror("Error", "Input folder not found.")
            return

        output_dir = self.output_var.get().strip()
        output_dir = Path(output_dir) if output_dir else None
        if output_dir is not None:
            output_dir.mkdir(parents=True, exist_ok=True)

        self.listbox.delete(0, tk.END)
        self.outputs = []
        self.status_var.set("Converting...")

        args = {
            "input_dir": input_dir,
            "output_dir": output_dir,
            "recursive": self.recursive_var.get(),
            "suffix": self.suffix_var.get(),
            "skip_existing": self.skip_var.get(),
            "inline_scale": self._parse_scale(self.inline_scale_var.get(), DEFAULT_INLINE_SCALE),
            "display_scale": self._parse_scale(self.display_scale_var.get(), DEFAULT_DISPLAY_SCALE),
        }

        self.worker = threading.Thread(target=self._convert_worker, args=(args,), daemon=True)
        self.worker.start()
        self.after(100, self._process_queue)

    def _convert_worker(self, args):
        tex_bin = resolve_tex_bin(None)
        cache_dir = args["input_dir"] / ".math_cache"
        for docx_path in iter_docx_files(
            args["input_dir"], args["recursive"], args["suffix"]
        ):
            out_path = build_output_path(
                docx_path,
                args["input_dir"],
                args["output_dir"],
                args["suffix"],
            )
            out_path.parent.mkdir(parents=True, exist_ok=True)
            if args["skip_existing"] and out_path.exists():
                self.queue.put(("log", "skipped: {}".format(out_path)))
                continue
            try:
                convert_docx(
                    docx_path,
                    out_path,
                    tex_bin,
                    DEFAULT_DPI_INLINE,
                    DEFAULT_DPI_DISPLAY,
                    args["inline_scale"],
                    args["display_scale"],
                    cache_dir,
                )
                self.queue.put(("output", out_path))
                self.queue.put(("log", "ok: {} -> {}".format(docx_path, out_path)))
            except Exception as exc:
                self.queue.put(("log", "error: {} ({})".format(docx_path, exc)))
        self.queue.put(("done", None))

    def _process_queue(self):
        try:
            while True:
                kind, payload = self.queue.get_nowait()
                if kind == "output":
                    self.outputs.append(payload)
                    self.listbox.insert(tk.END, str(payload))
                elif kind == "log":
                    self.status_var.set(payload)
                elif kind == "done":
                    self.status_var.set("Done")
        except queue.Empty:
            pass
        if self.worker and self.worker.is_alive():
            self.after(100, self._process_queue)

    def _selected_output(self):
        if not self.listbox.curselection():
            return None
        idx = self.listbox.curselection()[0]
        return Path(self.listbox.get(idx))

    def _open_selected(self):
        path = self._selected_output()
        if not path:
            messagebox.showinfo("Select", "Select a compiled DOCX first.")
            return
        os.startfile(str(path))

    def _export_selected(self):
        path = self._selected_output()
        if not path:
            messagebox.showinfo("Select", "Select a compiled DOCX first.")
            return
        pdf_path = path.with_suffix(".pdf")
        if pdf_path.exists():
            if not messagebox.askyesno(
                "Overwrite?", "PDF exists. Overwrite?"
            ):
                return
        try:
            export_pdf(path, pdf_path)
            messagebox.showinfo("Done", "Saved: {}".format(pdf_path))
        except subprocess.CalledProcessError as exc:
            messagebox.showerror("Error", exc.stdout or str(exc))
        except Exception as exc:
            messagebox.showerror("Error", str(exc))

    @staticmethod
    def _parse_scale(value, fallback):
        try:
            return float(value)
        except ValueError:
            return fallback


if __name__ == "__main__":
    app = App()
    app.mainloop()
