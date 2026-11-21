#!/usr/bin/env python3
"""Ворота из цельных листов: ромбы-«пирамиды» из отгибных лепестков.

Каждая панель ворот = один цельный лист (по умолчанию 1500x3000, ставится вертикально).
В каждом ромбе лазер режет КРЕСТ по диагоналям -> 4 треугольных лепестка.
Лепестки отгибаются наружу по сторонам ромба (линия гиба — пунктир-прорез с
перемычками), получается открытая пирамида. Отверстий нет, только рез.

Ворота любой длины: панели ставятся рядом, ширина панели кратна ширине ромба.
Удлинить ворота = добавить ещё одну панель.

python3 vorota_list.py out --gate 4000x2000 --sheet 1500x3000 --rhomb 200x250 --thickness 2
"""
import argparse
import math
import os

import numpy as np


# ------------------------------------------------------------------ DXF R12, только слой CUT
class DXF:
    def __init__(self):
        self.e = []

    def line(self, p, q):
        self.e += ["0", "LINE", "8", "CUT", "10", f"{p[0]:.3f}", "20", f"{p[1]:.3f}", "30", "0",
                   "11", f"{q[0]:.3f}", "21", f"{q[1]:.3f}", "31", "0"]

    def save(self, path):
        hdr = ["0", "SECTION", "2", "HEADER", "9", "$ACADVER", "1", "AC1009",
               "9", "$INSUNITS", "70", "4", "0", "ENDSEC"]
        lay = ["0", "SECTION", "2", "TABLES", "0", "TABLE", "2", "LAYER", "70", "1",
               "0", "LAYER", "2", "CUT", "70", "0", "62", "1", "6", "CONTINUOUS",
               "0", "ENDTAB", "0", "ENDSEC"]
        body = ["0", "SECTION", "2", "ENTITIES"] + self.e + ["0", "ENDSEC", "0", "EOF"]
        with open(path, "w", encoding="ascii", newline="\r\n") as f:
            f.write("\n".join(hdr + lay + body) + "\n")


def dashed(p, q, dash, bridge, end_gap):
    """Пунктир-прорез по линии гиба: штрих dash, перемычка bridge, на концах end_gap без реза."""
    p, q = np.asarray(p, float), np.asarray(q, float)
    L = np.linalg.norm(q - p)
    u = (q - p) / L
    U = L - 2 * end_gap
    if U <= 1:
        return []
    k = max(1, int(round((U + bridge) / (dash + bridge))))
    dl = (U - (k - 1) * bridge) / k
    out, t = [], end_gap
    for _ in range(k):
        out.append((p + u * t, p + u * (t + dl)))
        t += dl + bridge
    return out


def split_gate(GW, max_w, step):
    """Делим длину ворот на панели шириной <= max_w, кратные step, по возможности равные."""
    n = math.ceil(GW / max_w - 1e-9)
    while True:
        cells = int(round(GW / step))
        base, extra = divmod(cells, n)
        widths = [(base + (1 if i < extra else 0)) * step for i in range(n)]
        if max(widths) <= max_w + 1e-6:
            return widths
        n += 1


def panel(W, H, a, b, strip, border, bridge, dash):
    """Геометрия одной панели. Возвращает (cuts, bends, rhombs)."""
    p0, q0 = a / 2, b / 2
    # отступ стороны ромба внутрь на strip/2 -> между соседними ромбами полоса strip
    d0 = p0 * q0 / math.hypot(p0, q0)
    s = (d0 - strip / 2) / d0
    p, q = p0 * s, q0 * s
    x0, x1, y0, y1 = border, W - border, border, H - border
    nx = int((x1 - x0) // a)
    ny = int((y1 - y0) // b)
    ox = x0 + ((x1 - x0) - nx * a) / 2
    oy = y0 + ((y1 - y0) - ny * b) / 2
    centers = [(ox + (i + 0.5) * a, oy + (j + 0.5) * b) for j in range(ny) for i in range(nx)]
    centers += [(ox + i * a, oy + j * b) for j in range(1, ny) for i in range(1, nx)]
    cuts, bends, rhombs = [], [], []
    # контур листа: 4 перемычки по середине сторон, чтобы панель не выпала из листа
    corners = [(0, 0), (W, 0), (W, H), (0, H)]
    for i in range(4):
        P, Q = np.array(corners[i], float), np.array(corners[(i + 1) % 4], float)
        m, u = (P + Q) / 2, (Q - P) / np.linalg.norm(Q - P)
        cuts += [(P, m - u * bridge / 2), (m + u * bridge / 2, Q)]
    for cx, cy in centers:
        S, E, N, Wv = (np.array(v) for v in ((cx, cy - q), (cx + p, cy), (cx, cy + q), (cx - p, cy)))
        rhombs.append((np.array([cx, cy]), [S, E, N, Wv]))
        cuts += [(S, N), (Wv, E)]                      # крест по диагоналям — сквозной рез
        for A_, B_ in ((S, E), (E, N), (N, Wv), (Wv, S)):
            bends += dashed(A_, B_, dash, bridge, bridge)
    return cuts, bends, rhombs, (p, q)


def preview_panel(W, H, cuts, bends, path, title, zoom=None):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    if zoom:
        fig, ax = plt.subplots(figsize=(8, 8 * (zoom[3] - zoom[1]) / (zoom[2] - zoom[0])))
        lw = 1.4
    else:
        fig, ax = plt.subplots(figsize=(6, 6 * H / W + 0.5))
        lw = 0.4
    ax.add_patch(plt.Rectangle((0, 0), W, H, color="#e3e8eb"))
    for P, Q in cuts:
        ax.plot([P[0], Q[0]], [P[1], Q[1]], color="#c62828", lw=lw)
    for P, Q in bends:
        ax.plot([P[0], Q[0]], [P[1], Q[1]], color="#1565c0", lw=lw)
    ax.set_aspect("equal")
    if zoom:
        ax.set_xlim(zoom[0], zoom[2]); ax.set_ylim(zoom[1], zoom[3])
    ax.axis("off")
    ax.set_title(title, fontsize=9)
    fig.tight_layout()
    fig.savefig(path, dpi=150)
    plt.close(fig)


def render_gate(GW, GH, panels, theta, path):
    """Вид ворот спереди: лепестки отогнуты на угол theta."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import Polygon, Rectangle
    light = np.array([-0.55, 0.45, 0.70])
    light /= np.linalg.norm(light)
    th = math.radians(theta)
    fig, ax = plt.subplots(figsize=(14, 14 * GH / GW + 0.6))
    ax.add_patch(Rectangle((0, 0), GW, GH, color="#2b2f31"))       # что видно сквозь щели
    x = 0
    for W, H, rhombs in panels:
        ax.add_patch(Rectangle((x, 0), W, H, color="#9aa3a7"))
        for c, V in rhombs:
            ax.add_patch(Polygon([v + [x, 0] for v in V], closed=True, color="#2b2f31"))
            for k in range(4):
                X, Y = V[k], V[(k + 1) % 4]
                e = (Y - X) / np.linalg.norm(Y - X)
                F = X + e * ((c - X) @ e)                 # проекция центра на сторону
                r = c - F
                tip2 = F + r * math.cos(th)
                rh = r / np.linalg.norm(r)
                n3 = np.array([-rh[0] * math.sin(th), -rh[1] * math.sin(th), math.cos(th)])
                sh = 0.35 + 0.65 * max(0.0, float(n3 @ light))
                ax.add_patch(Polygon([X + [x, 0], Y + [x, 0], tip2 + [x, 0]], closed=True,
                                     fc=(sh, sh, sh), ec="#5f6b70", lw=0.25))
        ax.add_patch(Rectangle((x, 0), W, H, fill=False, ec="#d84315", lw=1.0, ls="--"))
        x += W
    ax.set_xlim(-20, GW + 20)
    ax.set_ylim(-20, GH + 20)
    ax.set_aspect("equal")
    ax.axis("off")
    ax.set_title(f"Ворота {GW:.0f} x {GH:.0f} мм — вид спереди, лепестки отогнуты на {theta:.0f}°. "
                 f"Пунктир — стыки панелей", fontsize=10)
    fig.tight_layout()
    fig.savefig(path, dpi=130)
    plt.close(fig)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--gate", default="4000x2000", help="ворота длина x высота, мм")
    ap.add_argument("--sheet", default="1500x3000", help="лист, мм")
    ap.add_argument("--rhomb", default="200x250", help="ромб: ширина x высота (диагонали), мм")
    ap.add_argument("--strip", type=float, default=14, help="перемычка металла между ромбами, мм")
    ap.add_argument("--border", type=float, default=30, help="ровное поле по краю панели (под сварку к раме), мм")
    ap.add_argument("--angle", type=float, default=35, help="угол отгиба лепестков (для картинки), °")
    ap.add_argument("--thickness", type=float, default=2.0)
    ap.add_argument("--bridge", type=float, default=2.0, help="перемычка (петелька), мм")
    ap.add_argument("--dash", type=float, default=10.0, help="длина прореза на линии гиба, мм")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for f in os.listdir(a.out):
        if f.endswith((".dxf", ".png", ".txt")):
            os.remove(os.path.join(a.out, f))
    GW, GH = (float(v) for v in a.gate.lower().split("x"))
    sw, sh = sorted(float(v) for v in a.sheet.lower().split("x"))
    ra, rb = (float(v) for v in a.rhomb.lower().split("x"))
    if GH > sh:
        raise SystemExit(f"Высота ворот {GH:.0f} больше длины листа {sh:.0f}")
    max_w = sw - 10                     # 5 мм от края листа с каждой стороны
    if abs(GW / ra - round(GW / ra)) > 1e-6:
        raise SystemExit(f"Длина ворот должна быть кратна ширине ромба {ra:.0f} мм")
    widths = split_gate(GW, max_w, ra)
    panels, rep = [], []
    for i, W in enumerate(widths, 1):
        cuts, bends, rhombs, (p, q) = panel(W, GH, ra, rb, a.strip, a.border, a.bridge, a.dash)
        # кладём панель на лист с отступом 5 мм
        off = np.array([5.0, 5.0])
        d = DXF()
        for P, Q in cuts + bends:
            d.line(P + off, Q + off)
        fn = f"PANEL_{i}_{W:.0f}x{GH:.0f}_list_{sw:.0f}x{sh:.0f}_{a.thickness:g}mm.dxf"
        d.save(os.path.join(a.out, fn))
        preview_panel(W, GH, cuts, bends, os.path.join(a.out, f"PANEL_{i}.png"),
                      f"Панель {i}: {W:.0f} x {GH:.0f} мм на листе {sw:.0f}x{sh:.0f}, {a.thickness:g} мм\n"
                      f"красное — сквозной рез, синий пунктир — рез с перемычками {a.bridge:g} мм (гиб)")
        if i == 1:
            c = rhombs[0][0]
            preview_panel(W, GH, cuts, bends, os.path.join(a.out, "KRUPNO.png"),
                          f"Крупно: крест — режется насквозь; стороны ромба — прорез {a.dash:g} мм / "
                          f"перемычка {a.bridge:g} мм, по ним отгибаем лепестки",
                          zoom=(c[0] - ra * 1.1, c[1] - rb * 0.9, c[0] + ra * 1.1, c[1] + rb * 0.9))
        panels.append((W, GH, rhombs))
        rep.append(f"Панель {i}: {W:.0f} x {GH:.0f} мм, ромбов {len(rhombs)}, файл {fn}")
    render_gate(GW, GH, panels, a.angle, os.path.join(a.out, "VOROTA_vid.png"))
    mass = sum(W * GH for W in widths) * a.thickness * 7.85e-6
    lines = [f"Ворота {GW:.0f} x {GH:.0f} мм из {len(widths)} цельных листов {sw:.0f}x{sh:.0f}, металл {a.thickness:g} мм",
             f"Ромб {ra:.0f}x{rb:.0f} мм, металл между ромбами {a.strip:g} мм, поле по краю {a.border:g} мм",
             *rep,
             f"Масса листов: ~{mass:.0f} кг (без рамы)",
             "Резка: крест в каждом ромбе — насквозь; стороны ромба — прорез с перемычками (петельками).",
             f"Гибка: каждый лепесток отогнуть наружу на {a.angle:.0f}° (одинаково), получится открытая пирамида.",
             "Удлинение: добавить панель сбоку (ширина кратна ширине ромба)."]
    open(os.path.join(a.out, "report.txt"), "w").write("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
