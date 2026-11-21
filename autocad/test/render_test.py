#!/usr/bin/env python3
"""Прогоняет vorota.lsp во всех 9 узорах через mini_autolisp и рисует:
 - развёртку первого листа (что режет лазер),
 - 3D-вид ворот (лист + отогнутые лепестки) — по реальным вызовам Rotate3D."""
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

NAMES = ["Ромб", "Треугольник", "Квадрат", "Соты", "Восьмигранник", "Ёлочка", "Кирпич", "Алмаз", "Кристалл"]


def rotate(pts, p1, p2, ang):
    p1, p2 = np.array(p1, float), np.array(p2, float)
    k = (p2 - p1) / np.linalg.norm(p2 - p1)
    out = []
    for p in pts:
        v = np.array(p, float) - p1
        v = v * math.cos(ang) + np.cross(k, v) * math.sin(ang) + k * (k @ v) * (1 - math.cos(ang))
        out.append(v + p1)
    return np.array(out)


def run_pattern(pat, gw=4000, gh=2000):
    it = ml.Interp([str(gw), str(gh), "2", str(pat), "", "", ""])
    flaps, holes = [], []
    orig_ex, orig_rot, orig_bool = it._extrude, it._rot, it._boolean

    def ex(ms, reg, h, taper):
        it._last = reg[1]
        return orig_ex(ms, reg, h, taper)

    def rot(obj, p1, p2, ang):
        pts3 = [(p[0], p[1], 0.0) for p in obj[1][1]]
        flaps.append(rotate(pts3, p1, p2, ang))
        return orig_rot(obj, p1, p2, ang)

    def boolean(a, op, b):
        holes.append(b[1])
        return orig_bool(a, op, b)
    it._extrude, it._rot, it._boolean = ex, rot, boolean
    it.b["VLA-ADDEXTRUDEDSOLID"] = ex
    it.b["VLA-ROTATE3D"] = rot
    it.b["VLA-BOOLEAN"] = boolean
    src = open(os.path.join(os.path.dirname(__file__), "..", "vorota.lsp"), encoding="utf-8").read()
    for f in ml.parse(ml.tokenize(src)):
        it.ev(f)
    it.ev([ml.Sym("C:VOROTA")])
    return it, flaps, holes


def draw_3d(ax, gw, gh, flaps, holes):
    light = np.array([-0.5, 0.45, 0.75])
    light /= np.linalg.norm(light)
    ax.add_patch(plt.Rectangle((0, 0), gw, gh, color="#a7b0b4"))
    for h in holes:
        ax.add_patch(Polygon(h, closed=True, color="#25292b"))
    for f in sorted(flaps, key=lambda f: f[:, 2].mean()):
        n = np.cross(f[1] - f[0], f[2] - f[0])
        n /= np.linalg.norm(n)
        if n[2] < 0:
            n = -n
        s = 0.3 + 0.7 * max(0.0, n @ light)
        ax.add_patch(Polygon(f[:, :2], closed=True, fc=(s, s, s * 1.02 if s < 0.97 else s), ec="#56606a", lw=0.15))
    ax.set_xlim(-30, gw + 30)
    ax.set_ylim(-30, gh + 30)
    ax.set_aspect("equal")
    ax.axis("off")


def main(out):
    os.makedirs(out, exist_ok=True)
    gw, gh = 4000, 2000
    fig3, axs3 = plt.subplots(3, 3, figsize=(18, 10))
    for pat in range(1, 10):
        it, flaps, holes = run_pattern(pat, gw, gh)
        ax = axs3.ravel()[pat - 1]
        draw_3d(ax, gw, gh, flaps, holes)
        ax.set_title(f"{pat} — {NAMES[pat - 1]}", fontsize=12)
        if pat == 1:
            # развёртка + 3D крупно для варианта «ромб»
            lines = [e for e in it.ents if e and e.get(0) == "LINE"]
            circles = [e for e in it.ents if e and e.get(0) == "CIRCLE"]
            polys = [e for e in it.ents if e and e.get(0) == "LWPOLYLINE" and e.get(8) == "LIST"]
            fig, ax2 = plt.subplots(figsize=(16, 11))
            for e in polys:
                p = np.array(e["PTS"] + e["PTS"][:1])
                ax2.plot(p[:, 0], p[:, 1], color="0.6", lw=0.8)
            for e in lines:
                a, b = e[10], e[11]
                ax2.plot([a[0], b[0]], [a[1], b[1]], color="#c62828", lw=0.3)
            for e in circles:
                ax2.add_patch(plt.Circle(e[10][:2], e[40], fill=False, ec="#c62828", lw=0.5))
            ax2.set_aspect("equal")
            ax2.axis("off")
            ax2.set_title("Развёртки из плагина (узор «Ромб»): 3 листа 1500x3000, всё красное — рез", fontsize=11)
            fig.tight_layout()
            fig.savefig(os.path.join(out, "razvertka_romb.png"), dpi=140)
            plt.close(fig)
            # крупный фрагмент стыка двух листов
            x0 = [e for e in polys][0]["PTS"][0][0]
            fig, ax2 = plt.subplots(figsize=(10, 10))
            for e in lines:
                a, b = e[10], e[11]
                ax2.plot([a[0], b[0]], [a[1], b[1]], color="#c62828", lw=1.0)
            for e in circles:
                ax2.add_patch(plt.Circle(e[10][:2], e[40], fill=False, ec="#c62828", lw=1.0))
            ax2.set_xlim(1130, 1430)
            ax2.set_ylim(-3845, -3545)
            ax2.set_aspect("equal")
            ax2.axis("off")
            ax2.set_title("Крупно: край листа — отбортовка 30 мм (пунктир = гиб 90°), отверстия М8 для соединения листов;\n"
                          "у края ячейки обрезаны — узор доходит почти до края", fontsize=10)
            fig.tight_layout()
            fig.savefig(os.path.join(out, "krupno_kray.png"), dpi=130)
            plt.close(fig)
            fig, ax2 = plt.subplots(figsize=(16, 8.6))
            draw_3d(ax2, gw, gh, flaps, holes)
            ax2.set_title("3D из плагина: ворота 4000x2000, узор «Ромб», лепестки 35°. Стыки листов — x=1333 и 2667", fontsize=11)
            fig.tight_layout()
            fig.savefig(os.path.join(out, "vorota_3d_romb.png"), dpi=130)
            plt.close(fig)
        print(pat, NAMES[pat - 1], "линий", sum(1 for e in it.ents if e and e.get(0) == "LINE"),
              "лепестков", len(flaps), "вырезов", len(holes), "|", it.out[-5].strip()[:90])
    fig3.suptitle("Все 9 узоров плагина ВОРОТА — 3D-вид спереди (4000x2000)", fontsize=14)
    fig3.tight_layout()
    fig3.savefig(os.path.join(out, "vse_uzory.png"), dpi=110)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "out")
