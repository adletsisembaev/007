#!/usr/bin/env python3
"""Прогон vorota.lsp (версия со скрытыми стыками) и картинки:
 vid_speredi_<n>.png — вид спереди по 3D-данным плагина (стык — тонкая линия по полосе),
 raskroy_<n>.png      — все листы раскроя (что режет лазер),
 styk_krupno.png      — крупно стык двух листов: зигзаг по полосе + лапки."""
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
LSP = os.path.join(os.path.dirname(__file__), "..", "vorota.lsp")


def rotate(pts, p1, p2, ang):
    p1, p2 = np.array(p1, float), np.array(p2, float)
    k = (p2 - p1) / np.linalg.norm(p2 - p1)
    out = []
    for p in pts:
        v = np.array(p, float) - p1
        v = v * math.cos(ang) + np.cross(k, v) * math.sin(ang) + k * (k @ v) * (1 - math.cos(ang))
        out.append(v + p1)
    return np.array(out)


def run(pat, answers):
    it = ml.Interp(answers)
    rec = {"flaps": [], "tabs": [], "holes": [], "tiles": [], "plates": []}
    cur_plate = []

    def region(ms, arr):
        r = ml.Interp._addregion(it, ms, arr)
        return r

    def boolean(a, op, b):
        (rec["holes"] if op == 2 else rec["tiles"]).append(b[1])
        return None

    def rot(obj, p1, p2, ang):
        pts3 = [(p[0], p[1], 0.0) for p in obj[1][1]]
        r = rotate(pts3, p1, p2, ang)
        (rec["tabs"] if abs(abs(ang) - math.pi / 2) < 1e-6 else rec["flaps"]).append(r)

    def extrude(ms, reg, h, taper):
        it.solids += 1
        return ("SOLID", reg)
    it.b["VLA-BOOLEAN"] = boolean
    it.b["VLA-ROTATE3D"] = rot
    it.b["VLA-ADDEXTRUDEDSOLID"] = extrude
    src = open(LSP, encoding="utf-8").read()
    for f in ml.parse(ml.tokenize(src)):
        it.ev(f)
    it.ev([ml.Sym("C:VOROTA")])
    return it, rec


def front(ax, gw, gh, rec, show_joints):
    light = np.array([-0.5, 0.45, 0.75])
    light /= np.linalg.norm(light)
    ax.add_patch(plt.Rectangle((0, 0), gw, gh, color="#a7b0b4"))
    for h in rec["holes"]:
        ax.add_patch(Polygon(h, closed=True, color="#25292b"))
    for f in rec["flaps"]:
        n = np.cross(f[1] - f[0], f[2] - f[0])
        n /= np.linalg.norm(n)
        if n[2] < 0:
            n = -n
        s = 0.3 + 0.7 * max(0.0, n @ light)
        ax.add_patch(Polygon(f[:, :2], closed=True, fc=(s, s, s), ec="#56606a", lw=0.12))
    if show_joints:
        for t in rec["tabs"]:
            ax.plot([t[0][0], t[3][0]], [t[0][1], t[3][1]], color="#e65100", lw=1.2)
    ax.set_xlim(-30, gw + 30)
    ax.set_ylim(-30, gh + 30)
    ax.set_aspect("equal")
    ax.axis("off")


def sheets(it):
    lines = [e for e in it.ents if e and e.get(0) == "LINE"]
    circ = [e for e in it.ents if e and e.get(0) == "CIRCLE"]
    rects = [e for e in it.ents if e and e.get(0) == "LWPOLYLINE" and e.get(8) == "LIST"]
    return lines, circ, rects


def main(out):
    os.makedirs(out, exist_ok=True)
    gw, gh = 4000, 2000
    for pat in (1, 4, 7):
        it, rec = run(pat, [str(gw), str(gh), "2", str(pat), "", "", "", "", "1", ""])
        print(pat, NAMES[pat - 1], it.out[-7].strip()[:150])
        fig, axs = plt.subplots(1, 2, figsize=(20, 5.6))
        front(axs[0], gw, gh, rec, False)
        axs[0].set_title(f"{NAMES[pat-1]}: вид спереди — стыков листов не видно", fontsize=11)
        front(axs[1], gw, gh, rec, True)
        axs[1].set_title("то же, оранжевым показаны линии стыков (идут по полосам узора)", fontsize=11)
        fig.tight_layout()
        fig.savefig(os.path.join(out, f"vid_speredi_{pat}.png"), dpi=120)
        plt.close(fig)
        lines, circ, rects = sheets(it)
        fig, ax = plt.subplots(figsize=(18, 11))
        for e in rects:
            p = np.array(e["PTS"] + e["PTS"][:1])
            ax.plot(p[:, 0], p[:, 1], color="0.55", lw=0.8)
        for e in lines:
            a, b = e[10], e[11]
            ax.plot([a[0], b[0]], [a[1], b[1]], color="#c62828", lw=0.25)
        for e in circ:
            ax.add_patch(plt.Circle(e[10][:2], e[40], fill=False, ec="#c62828", lw=0.4))
        ax.set_aspect("equal")
        ax.axis("off")
        ax.set_title(f"{NAMES[pat-1]}: раскрой листов 1500x3000 (серое — рамка листа, красное — всё режется)", fontsize=11)
        fig.tight_layout()
        fig.savefig(os.path.join(out, f"raskroy_{pat}.png"), dpi=120)
        plt.close(fig)
        if pat == 1:
            # крупно стык: правый край листа 1 и левый край листа 2
            fig, axs = plt.subplots(1, 2, figsize=(14, 8))
            xs = [e for e in rects]
            for ax, r in zip(axs, xs[:2]):
                x0 = min(p[0] for p in r["PTS"])
                y0 = min(p[1] for p in r["PTS"])
                for e in lines:
                    a, b = e[10], e[11]
                    ax.plot([a[0], b[0]], [a[1], b[1]], color="#c62828", lw=1.0)
                for e in circ:
                    ax.add_patch(plt.Circle(e[10][:2], e[40], fill=False, ec="#c62828", lw=1.0))
                ax.set_aspect("equal")
                ax.axis("off")
            # лист 1 — его правый край; лист 2 — левый край, одна высота
            r1, r2 = xs[0]["PTS"], xs[1]["PTS"]
            mx1 = max(l[10][0] for l in lines if min(p[0] for p in r1) < l[10][0] < max(p[0] for p in r1))
            y0 = min(p[1] for p in r1) + 1000
            axs[0].set_xlim(mx1 - 380, mx1 + 20)
            axs[0].set_ylim(y0, y0 + 450)
            mn2 = min(l[10][0] for l in lines if min(p[0] for p in r2) + 1 < l[10][0] < max(p[0] for p in r2))
            axs[1].set_xlim(mn2 - 20, mn2 + 380)
            axs[1].set_ylim(y0, y0 + 450)
            axs[0].set_title("Лист 1, правый край: зигзаг по полосе, лапки\n(пунктир — гиб лапки 90° назад, отверстие М6)", fontsize=10)
            axs[1].set_title("Лист 2, левый край: ответные лапки\n(встают спина к спине с лапками листа 1)", fontsize=10)
            fig.tight_layout()
            fig.savefig(os.path.join(out, "styk_krupno.png"), dpi=130)
            plt.close(fig)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "out")
