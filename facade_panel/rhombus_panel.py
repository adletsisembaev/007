#!/usr/bin/env python3
"""Ворота / фасад из кассет с ромбами-пирамидами -> DXF для лазера (сразу раскладка на листы).

Конструкция
  * Ворота W x H собираются из одинаковых кассет (по умолчанию 1000 x 1000).
    Узор сквозной: на краях кассеты стоят половинки/четвертинки пирамид с вертикальной
    стенкой; две соседние кассеты вместе дают целую пирамиду. Удлинить ворота =
    добавить столбец кассет (ширина кассеты кратна ширине ромба).
  * Кассета: задний лист + отбортовка по периметру (крепление к раме ворот).
  * Модуль-пирамида вырезается одной деталью (веер граней + полки), полки загибаются
    под пирамиду и крепятся к заднему листу через совпадающие отверстия.

В DXF только слой CUT — всё в файле режется:
  * контуры деталей с перемычками (петельками) --bridge мм, чтобы детали держались в листе;
  * линии гиба — пунктирный прорез: штрих --dash мм / перемычка --bridge мм (гнуть руками);
  * отверстия.

python3 rhombus_panel.py out --gate 4000x2000 --cassette 1000x1000 --rhomb 200x250 \
    --depth 40 --thickness 2 --sheet 1500x3000 --bridge 2
"""
import argparse
import math
import os
from collections import Counter, OrderedDict

import numpy as np


# ======================================================================= DXF R12
class DXF:
    def __init__(self):
        self.e = []

    def _poly(self, pts, closed, layer):
        e = ["0", "POLYLINE", "8", layer, "66", "1", "10", "0", "20", "0", "30", "0",
             "70", "1" if closed else "0"]
        for x, y in pts:
            e += ["0", "VERTEX", "8", layer, "10", f"{x:.3f}", "20", f"{y:.3f}", "30", "0"]
        self.e += e + ["0", "SEQEND", "8", layer]

    def poly_open(self, pts, layer="CUT"):
        self._poly(pts, False, layer)

    def line(self, p, q, layer="CUT"):
        self.e += ["0", "LINE", "8", layer, "10", f"{p[0]:.3f}", "20", f"{p[1]:.3f}", "30", "0",
                   "11", f"{q[0]:.3f}", "21", f"{q[1]:.3f}", "31", "0"]

    def circle(self, c, r, layer="CUT"):
        self.e += ["0", "CIRCLE", "8", layer, "10", f"{c[0]:.3f}", "20", f"{c[1]:.3f}", "30", "0",
                   "40", f"{r:.3f}"]

    def save(self, path):
        hdr = ["0", "SECTION", "2", "HEADER", "9", "$ACADVER", "1", "AC1009",
               "9", "$INSUNITS", "70", "4", "0", "ENDSEC"]
        lay = ["0", "SECTION", "2", "TABLES", "0", "TABLE", "2", "LAYER", "70", "1",
               "0", "LAYER", "2", "CUT", "70", "0", "62", "1", "6", "CONTINUOUS",
               "0", "ENDTAB", "0", "ENDSEC"]
        body = ["0", "SECTION", "2", "ENTITIES"] + self.e + ["0", "ENDSEC", "0", "EOF"]
        with open(path, "w", encoding="ascii", newline="\r\n") as f:
            f.write("\n".join(hdr + lay + body) + "\n")


# ======================================================================= геометрия
def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


def ang_between(u, v):
    return math.acos(float(np.clip(unit(u) @ unit(v), -1, 1)))


class Part:
    """2D-деталь: контур, отверстия, линии гиба, подписи (подписи — только в превью)."""

    def __init__(self, name, outline, holes=(), bends=(), marks=()):
        self.name = name
        self.outline = np.asarray(outline, float)
        self.holes = list(holes)
        self.bends = list(bends)      # (p, q, angle_deg)
        self.marks = list(marks)      # (p, text)

    def tf(self, R, t):
        f = lambda p: np.asarray(p, float) @ R.T + t
        return Part(self.name, f(self.outline), [(f(c), r) for c, r in self.holes],
                    [(f(p), f(q), a) for p, q, a in self.bends],
                    [(f(p), s) for p, s in self.marks])

    def rotated(self, deg):
        c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
        return self.tf(np.array([[c, -s], [s, c]]), np.zeros(2))

    def moved(self, d):
        return self.tf(np.eye(2), np.asarray(d, float))

    def bbox(self):
        return self.outline.min(0), self.outline.max(0)

    def size(self):
        return np.ptp(self.outline, axis=0)

    def to_origin(self):
        return self.moved(-self.bbox()[0])

    def best_rotation(self):
        d = min(range(0, 180), key=lambda d: np.prod(self.rotated(d).size()))
        return self.rotated(d).to_origin()


def clip_poly(poly, x0, y0, x1, y1):
    """Sutherland–Hodgman: обрезка многоугольника прямоугольником."""
    def clip(pts, inside, inter):
        out = []
        for i in range(len(pts)):
            cur, prv = pts[i], pts[i - 1]
            if inside(cur):
                if not inside(prv):
                    out.append(inter(prv, cur))
                out.append(cur)
            elif inside(prv):
                out.append(inter(prv, cur))
        return out

    def ix(xc):
        return lambda p, q: p + (q - p) * ((xc - p[0]) / (q[0] - p[0]))

    def iy(yc):
        return lambda p, q: p + (q - p) * ((yc - p[1]) / (q[1] - p[1]))
    e = 1e-9
    pts = [np.asarray(p, float) for p in poly]
    pts = clip(pts, lambda p: p[0] >= x0 - e, ix(x0))
    pts = clip(pts, lambda p: p[0] <= x1 + e, ix(x1)) if pts else pts
    pts = clip(pts, lambda p: p[1] >= y0 - e, iy(y0)) if pts else pts
    pts = clip(pts, lambda p: p[1] <= y1 + e, iy(y1)) if pts else pts
    res = []
    for p in pts:
        if not res or np.linalg.norm(p - res[-1]) > 1e-6:
            res.append(p)
    if len(res) > 1 and np.linalg.norm(res[0] - res[-1]) < 1e-6:
        res.pop()
    return res


# ======================================================================= модуль
def pyramid_net(base, apex_xy, h, flange, hole_off, hole_d, relief=1.0, name="M"):
    """Развёртка пирамиды над многоугольником `base` (2D, CCW, в координатах кассеты)
    с вершиной над точкой apex_xy (внутри или на границе основания) на высоте h.
    Боковые треугольники раскладываются веером вокруг вершины, шов — по ребру к
    самой нижней вершине основания. По каждой стороне основания — полка, загибается
    внутрь под пирамиду. Возвращает (Part, отверстия в коорд. кассеты, инфо)."""
    B = [np.asarray(b, float) for b in base]
    n = len(B)
    start = min(range(n), key=lambda i: (round(B[i][1], 6), round(B[i][0], 6)))
    B = B[start:] + B[:start]
    A3 = np.array([apex_xy[0], apex_xy[1], h])
    B3 = [np.array([b[0], b[1], 0.0]) for b in B]
    tip = [ang_between(B[i - 1] - B[i], B[(i + 1) % n] - B[i]) for i in range(n)]
    normals = [unit(np.cross(B3[k] - A3, B3[(k + 1) % n] - A3)) for k in range(n)]
    apex_ang = [ang_between(B3[k] - A3, B3[(k + 1) % n] - A3) for k in range(n)]
    total = sum(apex_ang)
    if total >= 2 * math.pi - 1e-3:
        raise ValueError("развёртка не раскладывается веером")
    gap = 2 * math.pi - total
    th = -math.pi / 2 + gap / 2
    rays = []
    for k in range(n + 1):
        L = np.linalg.norm(B3[k % n] - A3)
        rays.append(L * np.array([math.cos(th), math.sin(th)]))
        if k < n:
            th += apex_ang[k]
    O = np.zeros(2)
    outline = [O]
    holes2d, holes3d, bends = [], [], []
    for k in range(n):
        X, Y = rays[k], rays[k + 1]
        X3, Y3 = B[k], B[(k + 1) % n]
        Le = np.linalg.norm(Y - X)
        u = (Y - X) / Le
        nrm = np.array([u[1], -u[0]])
        if nrm @ ((X + Y) / 2) < 0:
            nrm = -nrm
        u3 = (Y3 - X3) / np.linalg.norm(Y3 - X3)
        in3 = np.array([-u3[1], u3[0]])          # внутрь основания (основание CCW)
        tx = 1 / math.tan(tip[k] / 2)
        ty = 1 / math.tan(tip[(k + 1) % n] / 2)
        f = flange
        if f * (tx + ty) + 2 * relief > Le - 12:      # короткая сторона — сужаем полку
            f = max(8.0, (Le - 12 - 2 * relief) / (tx + ty))
        Xf = X + nrm * f + u * (f * tx + relief)
        Yf = Y + nrm * f - u * (f * ty + relief)
        if k == 0:
            outline.append(X)
        outline += [Xf, Yf, Y]
        slope = math.degrees(math.acos(np.clip(normals[k][2], -1, 1)))
        bends.append((X, Y, 180 - slope))
        if k < n - 1:
            bends.append((O, Y, math.degrees(ang_between(normals[k], normals[k + 1]))))
        d = min(hole_off, f * 0.65)
        s0 = d * tx + relief
        s1 = Le - (d * ty + relief)
        if s1 - s0 > hole_d * 2 + 4:
            sm = (s0 + s1) / 2
            holes2d.append((X + u * sm + nrm * d, hole_d / 2))
            holes3d.append(X3 + u3 * sm + in3 * d)
    kbig = max(range(n), key=lambda k: abs(rays[k][0] * rays[k + 1][1] - rays[k][1] * rays[k + 1][0]))
    marks = [((rays[kbig] + rays[kbig + 1]) / 3, name)]
    P = Part(name, np.array(outline), holes2d, bends, marks)
    return P, holes3d, dict(gap_deg=math.degrees(gap))


# ======================================================================= кассета
def pattern_pieces(W, H, a, b, gap):
    """Ромбы шахматкой с периодом (a, b), обрезанные по кассете [0,W]x[0,H]."""
    p0, q0 = a / 2, b / 2
    d0 = p0 * q0 / math.hypot(p0, q0)
    s = (d0 - gap / 2) / d0
    p, q = p0 * s, q0 * s
    nx, ny = int(round(W / a)), int(round(H / b))
    centers = [((i + 0.5) * a, (j + 0.5) * b) for j in range(ny) for i in range(nx)]
    centers += [(i * a, j * b) for j in range(ny + 1) for i in range(nx + 1)]
    out = []
    for cx, cy in centers:
        rh = [(cx, cy - q), (cx + p, cy), (cx, cy + q), (cx - p, cy)]
        poly = clip_poly(rh, 0, 0, W, H)
        if len(poly) < 3:
            continue
        pa = np.array(poly)
        area = 0.5 * abs(np.dot(pa[:, 0], np.roll(pa[:, 1], -1)) - np.dot(pa[:, 1], np.roll(pa[:, 0], -1)))
        if area < 0.2 * p * q:
            continue
        out.append(((cx, cy), poly))
    return out, p, q


def piece_type(center, W, H):
    cx, cy = center
    t = "L" if abs(cx) < 1e-6 else ("R" if abs(cx - W) < 1e-6 else "")
    t += "B" if abs(cy) < 1e-6 else ("T" if abs(cy - H) < 1e-6 else "")
    return t or "M"


TYPE_RU = {"M": "целая", "L": "половина, левый край", "R": "половина, правый край",
           "B": "половина, нижний край", "T": "половина, верхний край",
           "LB": "четверть, левый нижний угол", "RB": "четверть, правый нижний угол",
           "LT": "четверть, левый верхний угол", "RT": "четверть, правый верхний угол"}


def cassette_part(W, H, rim, holes3d, rivet_d, mount_d, name):
    r = rim
    o = [(0, -r), (W, -r), (W, 0), (W + r, 0), (W + r, H), (W, H), (W, H + r),
         (0, H + r), (0, H), (-r, H), (-r, 0), (0, 0)]
    holes = [(np.array(h[:2]), rivet_d / 2) for h in holes3d]

    def row(L):
        k = max(2, int(round(L / 250)) + 1)
        return np.linspace(60, L - 60, k)
    for x in row(W):
        holes += [(np.array([x, -r / 2]), mount_d / 2), (np.array([x, H + r / 2]), mount_d / 2)]
    for y in row(H):
        holes += [(np.array([-r / 2, y]), mount_d / 2), (np.array([W + r / 2, y]), mount_d / 2)]
    c = [(0, 0), (W, 0), (W, H), (0, H)]
    bends = [(np.array(c[i], float), np.array(c[(i + 1) % 4], float), 90) for i in range(4)]
    return Part(name, np.array(o, float), holes, bends, [(np.array([W / 2 - 20, H / 2]), name)])


# ======================================================================= рез
def cut_geometry(P, bridge, dash, joints):
    """Всё, что режет лазер: контур с перемычками, пунктир по линиям гиба, отверстия."""
    polys = []
    o = P.outline
    n = len(o)
    seg = sorted(((np.linalg.norm(o[(i + 1) % n] - o[i]), i) for i in range(n)), reverse=True)
    jl = set(i for _, i in seg[:joints]) if joints else set()
    if not jl:
        polys.append(np.vstack([o, o[:1]]))
    else:
        start = min(jl)
        cur, first_tail = None, None
        for k in range(n):
            i = (start + k) % n
            a_, b_ = o[i], o[(i + 1) % n]
            if i in jl:
                m, u = (a_ + b_) / 2, unit(b_ - a_)
                g1, g2 = m - u * bridge / 2, m + u * bridge / 2
                if cur is None:
                    first_tail = g1
                else:
                    cur.append(g1)
                    polys.append(np.array(cur))
                cur = [g2, b_]
            else:
                cur.append(b_)
        cur.append(first_tail)
        polys.append(np.array(cur))
    key = lambda p: (round(float(p[0]), 2), round(float(p[1]), 2))
    ends = Counter()
    for p, q, _ in P.bends:
        ends[key(p)] += 1
        ends[key(q)] += 1
    for p, q, _ in P.bends:
        L = np.linalg.norm(q - p)
        u = (q - p) / L
        t0 = bridge * (2 if ends[key(p)] >= 3 else 1)
        t1 = bridge * (2 if ends[key(q)] >= 3 else 1)
        U = L - t0 - t1
        if U <= 1:
            continue
        k = max(1, int(round((U + bridge) / (dash + bridge))))
        dl = (U - (k - 1) * bridge) / k
        t = t0
        for _ in range(k):
            polys.append(np.array([p + u * t, p + u * (t + dl)]))
            t += dl + bridge
    return polys, list(P.holes)


def write_cut_dxf(geo, path):
    d = DXF()
    for polys, circles in geo:
        for pl in polys:
            if len(pl) == 2:
                d.line(pl[0], pl[1])
            else:
                d.poly_open(pl)
        for c, r in circles:
            d.circle(c, r)
    d.save(path)


# ======================================================================= раскладка
def pack(parts, SW, SH, gap=6.0, margin=10.0):
    """Гильотинная упаковка по габаритам (крупные первыми), поворот 0/90."""
    items = sorted(parts, key=lambda P: -np.prod(P.size()))
    sheets = []

    def try_place(sh, P):
        w, h = P.size()
        best = None
        for fi, (x, y, fw, fh) in enumerate(sh["free"]):
            for rot in (False, True):
                ww, hh = (h, w) if rot else (w, h)
                if ww + gap <= fw + 1e-6 and hh + gap <= fh + 1e-6:
                    score = (y, x)
                    if best is None or score < best[0]:
                        best = (score, fi, rot, ww, hh)
        if best is None:
            return False
        _, fi, rot, ww, hh = best
        x, y, fw, fh = sh["free"].pop(fi)
        Q = (P.rotated(90).to_origin() if rot else P).moved((x, y))
        sh["parts"].append(Q)
        for r in ((x + ww + gap, y, fw - ww - gap, hh + gap), (x, y + hh + gap, fw, fh - hh - gap)):
            if r[2] > 20 and r[3] > 20:
                sh["free"].append(r)
        sh["free"].sort(key=lambda r: (r[1], r[0]))
        return True

    for P in items:
        w, h = P.size()
        if not ((w <= SW - 2 * margin and h <= SH - 2 * margin) or (h <= SW - 2 * margin and w <= SH - 2 * margin)):
            raise SystemExit(f"Деталь {P.name} {w:.0f}x{h:.0f} не помещается на лист {SW:.0f}x{SH:.0f}")
        for sh in sheets:
            if try_place(sh, P):
                break
        else:
            sh = {"free": [(margin, margin, SW - 2 * margin + gap, SH - 2 * margin + gap)], "parts": []}
            try_place(sh, P)
            sheets.append(sh)
    return [s["parts"] for s in sheets]


# ======================================================================= картинки
def _plt():
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    return plt


def preview_sheet(parts, geo, SW, SH, path, title):
    plt = _plt()
    sc = 11 / max(SW, SH)
    fig, ax = plt.subplots(figsize=(SW * sc + 0.5, SH * sc + 0.9))
    ax.add_patch(plt.Rectangle((0, 0), SW, SH, fill=False, ec="0.5", lw=0.8))
    for P in parts:
        ax.fill(P.outline[:, 0], P.outline[:, 1], color="#e3e8eb", lw=0)
    for polys, circles in geo:
        for pl in polys:
            ax.plot(pl[:, 0], pl[:, 1], color="#c62828", lw=0.45)
        for c, r in circles:
            ax.add_patch(plt.Circle(c, r, fill=False, ec="#c62828", lw=0.35))
    for P in parts:
        for p, s in P.marks:
            ax.text(p[0], p[1], s, fontsize=4 if P.name[0] != "K" else 9, color="#1565c0")
    ax.set_aspect("equal")
    ax.set_xlim(-30, SW + 30)
    ax.set_ylim(-30, SH + 30)
    ax.set_title(title, fontsize=8)
    ax.axis("off")
    fig.tight_layout()
    fig.savefig(path, dpi=160)
    plt.close(fig)


def preview_types(types, path, bridge, dash):
    plt = _plt()
    names = list(types)
    cols = 3
    rows = math.ceil(len(names) / cols)
    fig, axs = plt.subplots(rows, cols, figsize=(cols * 5, rows * 5))
    axs = np.atleast_1d(axs).ravel()
    for ax, nm in zip(axs, names):
        P, cnt = types[nm]
        polys, circles = cut_geometry(P, bridge, dash, 2)
        ax.fill(P.outline[:, 0], P.outline[:, 1], color="#e3e8eb", lw=0)
        for pl in polys:
            ax.plot(pl[:, 0], pl[:, 1], color="#c62828", lw=1.0)
        for c, r in circles:
            ax.add_patch(plt.Circle(c, r, fill=False, ec="#c62828", lw=0.9))
        for p, q, a_ in P.bends:
            m = (p + q) / 2
            ax.text(m[0], m[1], f"{a_:.0f}°", fontsize=7, color="#2e7d32", ha="center", va="center",
                    bbox=dict(fc="white", ec="none", pad=0.5, alpha=0.8))
        ax.set_title(f"{nm} — {TYPE_RU.get(nm.split('-')[0], nm)}: {cnt} шт", fontsize=9)
        ax.set_aspect("equal")
        ax.axis("off")
    for ax in axs[len(names):]:
        ax.axis("off")
    fig.suptitle(f"Модули: красное — режется (пунктир {dash:g}/{bridge:g} мм = линия гиба), "
                 f"зелёное — угол гиба. Все гибы в одну сторону: грани вверх, полки под пирамиду.",
                 fontsize=10)
    fig.tight_layout()
    fig.savefig(path, dpi=120)
    plt.close(fig)


def render_gate(GW, GH, cas_list, pieces, h, path):
    plt = _plt()
    from matplotlib.patches import Polygon, Rectangle
    light = unit(np.array([-0.6, 0.5, 0.65]))
    fig, ax = plt.subplots(figsize=(14, 14 * GH / GW + 0.6))
    ax.add_patch(Rectangle((0, 0), GW, GH, color="#8a9499"))
    for (x0, y0, w, hh) in cas_list:
        for (cx, cy), base in pieces[(w, hh)]:
            A = np.array([cx + x0, cy + y0, h])
            Bp = [np.array([bx + x0, by + y0, 0]) for bx, by in base]
            for k in range(len(Bp)):
                t = [A, Bp[k], Bp[(k + 1) % len(Bp)]]
                nn = np.cross(t[1] - t[0], t[2] - t[0])
                if np.linalg.norm(nn) < 1e-9 or abs(unit(nn)[2]) < 1e-6:
                    continue
                s = 0.35 + 0.65 * max(0, unit(nn) @ light)
                ax.add_patch(Polygon([v[:2] for v in t], closed=True, fc=(s, s, s), ec="#5f6b70", lw=0.25))
        ax.add_patch(Rectangle((x0, y0), w, hh, fill=False, ec="#d84315", lw=1.0, ls="--"))
    ax.set_xlim(-20, GW + 20)
    ax.set_ylim(-20, GH + 20)
    ax.set_aspect("equal")
    ax.axis("off")
    ax.set_title(f"Ворота {GW:.0f} x {GH:.0f} мм — вид спереди. Пунктир — стыки кассет", fontsize=10)
    fig.tight_layout()
    fig.savefig(path, dpi=130)
    plt.close(fig)


# ======================================================================= main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--gate", default="4000x2000", help="ворота: длина x высота, мм")
    ap.add_argument("--cassette", default="1000x1000", help="кассета: ширина x высота, мм")
    ap.add_argument("--rhomb", default="200x250", help="диагонали ромба: ширина x высота, мм")
    ap.add_argument("--depth", type=float, default=40, help="высота пирамиды, мм")
    ap.add_argument("--gap", type=float, default=2, help="зазор между пирамидами, мм")
    ap.add_argument("--flange", type=float, default=30, help="полка модуля, мм")
    ap.add_argument("--hole-off", type=float, default=20, help="отверстие от линии гиба полки, мм")
    ap.add_argument("--rim", type=float, default=30, help="отбортовка кассеты, мм")
    ap.add_argument("--rivet", type=float, default=4.2, help="отверстие модуль-кассета, мм")
    ap.add_argument("--mount", type=float, default=6.5, help="отверстие крепления кассеты к раме, мм")
    ap.add_argument("--thickness", type=float, default=2.0)
    ap.add_argument("--sheet", default="1500x3000")
    ap.add_argument("--bridge", type=float, default=2.0, help="перемычка (петелька), мм")
    ap.add_argument("--dash", type=float, default=10.0, help="прорез на линии гиба, мм")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for f_ in os.listdir(a.out):
        if f_.endswith((".dxf", ".png", ".txt")):
            os.remove(os.path.join(a.out, f_))
    SW, SH = sorted(float(v) for v in a.sheet.lower().split("x"))
    GW, GH = (float(v) for v in a.gate.lower().split("x"))
    CW, CH = (float(v) for v in a.cassette.lower().split("x"))
    ra, rb = (float(v) for v in a.rhomb.lower().split("x"))
    for nm, v, st in (("ширина кассеты", CW, ra), ("высота кассеты", CH, rb),
                      ("длина ворот", GW, ra), ("высота ворот", GH, rb)):
        if abs(v / st - round(v / st)) > 1e-6:
            raise SystemExit(f"{nm} {v:.0f} должна быть кратна {st:.0f} мм (размер ромба)")

    def split(L, C):
        n = int(L // C)
        rest = L - n * C
        return [C] * n + ([rest] if rest > 1e-6 else [])
    cols, rws = split(GW, CW), split(GH, CH)
    cas_list, x = [], 0.0
    for w in cols:
        y = 0.0
        for hh in rws:
            cas_list.append((x, y, w, hh))
            y += hh
        x += w

    pieces, cas_parts, mod_parts, mod_types = {}, [], [], OrderedDict()
    ctype_count = Counter((w, hh) for _, _, w, hh in cas_list)
    multi = len(ctype_count) > 1
    for ci, ((w, hh), cnt) in enumerate(ctype_count.items(), 1):
        pcs, p, q = pattern_pieces(w, hh, ra, rb, a.gap)
        pieces[(w, hh)] = pcs
        holes3d, local = [], OrderedDict()
        for center, base in pcs:
            t = piece_type(center, w, hh)
            P, h3, _ = pyramid_net(base, center, a.depth, a.flange, a.hole_off, a.rivet, name=t)
            holes3d += h3
            local.setdefault(t, [P, 0])[1] += 1
        K = cassette_part(w, hh, a.rim, holes3d, a.rivet, a.mount,
                          f"K{ci}" if multi else "K").to_origin()
        cas_parts += [K] * cnt
        for t, (P, n_) in local.items():
            nm = f"{t}-{ci}" if multi else t
            P.name = nm
            P.marks = [(m[0], nm) for m in P.marks]
            Pz = P.best_rotation()
            mod_types.setdefault(nm, [Pz, 0])[1] += n_ * cnt
            mod_parts += [Pz] * (n_ * cnt)

    sheets = pack(cas_parts + mod_parts, SW, SH)
    for i, parts in enumerate(sheets, 1):
        geo = [cut_geometry(P, a.bridge, a.dash, 4 if P.name.startswith("K") else 2) for P in parts]
        write_cut_dxf(geo, os.path.join(a.out, f"LIST_{i:02d}_{SW:.0f}x{SH:.0f}_{a.thickness:g}mm.dxf"))
        cnt = Counter(P.name for P in parts)
        desc = ", ".join(f"{k}×{v}" for k, v in sorted(cnt.items()))
        preview_sheet(parts, geo, SW, SH, os.path.join(a.out, f"LIST_{i:02d}.png"),
                      f"Лист {i}/{len(sheets)} {SW:.0f}x{SH:.0f}, {a.thickness:g} мм. Всё красное режется.\n{desc}")
    preview_types(mod_types, os.path.join(a.out, "MODULI_kak_gnut.png"), a.bridge, a.dash)
    render_gate(GW, GH, cas_list, pieces, a.depth, os.path.join(a.out, "VOROTA_vid.png"))

    def area(o):
        return 0.5 * abs(np.dot(o[:, 0], np.roll(o[:, 1], -1)) - np.dot(o[:, 1], np.roll(o[:, 0], -1)))
    mass = sum(area(P.outline) for P in cas_parts + mod_parts) * a.thickness * 7.85e-6
    rep = [f"Ворота {GW:.0f} x {GH:.0f} мм, металл {a.thickness:g} мм, лист {SW:.0f}x{SH:.0f}",
           "Кассеты: " + ", ".join(f"{w:.0f}x{hh:.0f} — {c} шт" for (w, hh), c in ctype_count.items()),
           f"Сетка кассет: {len(cols)} по длине x {len(rws)} по высоте",
           f"Ромб {ra:.0f}x{rb:.0f}, пирамида {a.depth:.0f} мм, зазор {a.gap:g} мм",
           "Модули:"]
    for nm, (P, c) in mod_types.items():
        rep.append(f"  {nm:5s} {TYPE_RU.get(nm.split('-')[0], nm):30s} {c:4d} шт")
    rep += [f"Листов: {len(sheets)}",
            f"Масса металла (сталь {a.thickness:g} мм): ~{mass:.0f} кг (без рамы ворот)",
            f"Рез: контуры с перемычками {a.bridge:g} мм; линии гиба — прорез {a.dash:g} мм / перемычка {a.bridge:g} мм",
            "Удлинение: добавить столбец кассет (ширина кратна ширине ромба), узор продолжится без разрыва."]
    open(os.path.join(a.out, "report.txt"), "w").write("\n".join(rep) + "\n")
    print("\n".join(rep))


if __name__ == "__main__":
    main()
