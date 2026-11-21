#!/usr/bin/env python3
"""Прогон fasad.lsp и картинки: 3D-вид фасада (по 3DFACE из плагина) + раскрой + деталь крупно."""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import mini_autolisp as ml  # noqa: E402
import matplotlib  # noqa: E402
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import Polygon  # noqa: E402

LSP = os.path.join(os.path.dirname(__file__), "..", "fasad.lsp")


def run(answers):
    it = ml.Interp(answers)
    for f in ml.parse(ml.tokenize(open(LSP, encoding="utf-8").read())):
        it.ev(f)
    it.ev([ml.Sym("C:FASAD")])
    return it


def faces(it):
    out = []
    for e in it.ents:
        if e and e.get(0) == "3DFACE":
            p = [e[10]] + [e[k] for k in (11, 12, 13)]
            out.append(np.array(p, float))
    return out


def view3d(ax, fcs, yaw=-35, pitch=12, color=(0.80, 0.82, 0.85)):
    """Ортогональная проекция с поворотом (как фото сбоку), заливка по освещению."""
    ya, pa = math.radians(yaw), math.radians(pitch)
    Ry = np.array([[math.cos(ya), 0, math.sin(ya)], [0, 1, 0], [-math.sin(ya), 0, math.cos(ya)]])
    Rx = np.array([[1, 0, 0], [0, math.cos(pa), -math.sin(pa)], [0, math.sin(pa), math.cos(pa)]])
    R = Rx @ Ry
    light = np.array([-0.4, 0.6, 0.7])
    light /= np.linalg.norm(light)
    polys = []
    for f in fcs:
        n = np.cross(f[1] - f[0], f[2] - f[0])
        if np.linalg.norm(n) < 1e-9:
            continue
        n /= np.linalg.norm(n)
        if n[2] < 0 and abs(n[2]) > 1e-6:
            n = -n
        q = f @ R.T
        polys.append((q[:, 2].mean(), q[:, :2], n))
    polys.sort(key=lambda t: t[0])
    for _, q, n in polys:
        s = 0.35 + 0.65 * max(0.0, float(n @ light))
        ax.add_patch(Polygon(q, closed=True, fc=tuple(min(1, c * s * 1.1) for c in color), ec="#4a5258", lw=0.3))
    allp = np.vstack([p for _, p, _ in polys])
    ax.set_xlim(allp[:, 0].min() - 50, allp[:, 0].max() + 50)
    ax.set_ylim(allp[:, 1].min() - 50, allp[:, 1].max() + 50)
    ax.set_aspect("equal")
    ax.axis("off")


def layout(ax, it, sheets=3, part_zoom=False):
    lines = [e for e in it.ents if e and e.get(0) == "LINE"]
    circ = [e for e in it.ents if e and e.get(0) == "CIRCLE"]
    txt = [e for e in it.ents if e and e.get(0) == "TEXT" and e.get(8) == "NOMER"]
    lst = [e for e in lines if e.get(8) == "LIST"]
    xmax = 0 + sheets * 1800 - 300
    for e in lines:
        a, b = e[10], e[11]
        if a[1] > -100 or a[0] > xmax:
            continue
        col = {"REZ": "#c62828", "GIB": "#2e7d32", "LIST": "0.6"}.get(e.get(8), "k")
        ax.plot([a[0], b[0]], [a[1], b[1]], color=col, lw=0.35 if not part_zoom else 0.9)
    for e in circ:
        c = e[10]
        if c[1] > -100 or c[0] > xmax:
            continue
        ax.add_patch(plt.Circle(c[:2], e[40], fill=False, ec="#c62828", lw=0.25 if not part_zoom else 0.7))
    for e in txt:
        p = e[10]
        if p[1] < -100 and p[0] < xmax:
            ax.text(p[0], p[1], e[1], fontsize=7 if not part_zoom else 12, color="#1565c0")
    ax.set_aspect("equal")
    ax.axis("off")


CASES = [
    ("1_kvadrat_volna", "Как фото 1: квадрат 600, глубина 150, вершина — волна, перфорация через грань",
     ["6000", "3000", "1.5", "1", "", "", "2", "1", "2", "", "", "", "", ""], (0.82, 0.84, 0.87)),
    ("2_pryamougolnik", "Как фото 2: прямоугольник 500x1000, вершина смещена, перфорация на всех гранях",
     ["4000", "2000", "2", "5", "", "120", "1", "1", "1", "8", "20", "", "", "", ""], (0.42, 0.44, 0.47)),
    ("3_treugolnik", "Как фото 3: треугольник 700, глубина 150, вершина по центру, без перфорации",
     ["6000", "3000", "1.5", "2", "", "", "1", "1", "0", "", "", "", ""], (0.86, 0.74, 0.45)),
]


def main(out):
    os.makedirs(out, exist_ok=True)
    for name, title, ans, col in CASES:
        it = run(ans)
        print(name, [x for x in it.out if "Готово" in x])
        fcs = faces(it)
        fig, axs = plt.subplots(1, 2, figsize=(20, 7.5), gridspec_kw={"width_ratios": [1.25, 1]})
        view3d(axs[0], fcs, yaw=-38, pitch=10, color=col)
        axs[0].set_title(title + "\nвид сбоку (3D из плагина)", fontsize=11)
        view3d(axs[1], fcs, yaw=0, pitch=0, color=col)
        axs[1].set_title("вид спереди", fontsize=11)
        fig.tight_layout()
        fig.savefig(os.path.join(out, f"fasad_{name}.png"), dpi=110)
        plt.close(fig)
        fig, ax = plt.subplots(figsize=(16, 10))
        layout(ax, it, sheets=3)
        ax.set_title("Раскрой (первые 3 листа 1500x3000): красное — рез, пунктир — гиб с петельками, синее — номер детали",
                     fontsize=11)
        fig.tight_layout()
        fig.savefig(os.path.join(out, f"raskroy_{name}.png"), dpi=110)
        plt.close(fig)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "out")
