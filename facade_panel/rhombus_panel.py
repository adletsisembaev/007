#!/usr/bin/env python3
"""Фасадная кассета с ромбами-пирамидами -> DXF для лазерной резки.

Конструкция:
  * Кассета (задний лист) W x H с отбортовкой по периметру (крепление к подсистеме).
  * На кассету заклёпками крепятся модули-пирамиды. Модуль вырезается одной деталью:
    4 треугольные грани "веером" + 4 полки по основанию, загибаемые внутрь под пирамиду.
    Один шов от вершины до нижнего угла ромба — проварить (точечно/TIG) и зачистить.

Запуск (все размеры в мм):
  python3 rhombus_panel.py out --width 1000 --height 1000 --rhomb 200x250 --depth 40 \
      --thickness 1 --sheet 1250x2500

Слои DXF: CUT (резка, красный), BEND_OUT (гиб "горой" при виде на лицевую сторону, зелёный),
          BEND_IN (гиб "долиной", фиолетовый), MARK (гравировка/подписи, синий — НЕ резать).
"""
import argparse
import math
import os

import numpy as np


# ----------------------------------------------------------------- DXF R12
class DXF:
    COLORS = {"CUT": 1, "BEND_OUT": 3, "BEND_IN": 6, "MARK": 5}

    def __init__(self):
        self.e = []

    def poly(self, pts, layer="CUT"):
        e = ["0", "POLYLINE", "8", layer, "66", "1", "10", "0", "20", "0", "30", "0", "70", "1"]
        for x, y in pts:
            e += ["0", "VERTEX", "8", layer, "10", f"{x:.3f}", "20", f"{y:.3f}", "30", "0"]
        self.e += e + ["0", "SEQEND", "8", layer]

    def circle(self, c, r, layer="CUT"):
        self.e += ["0", "CIRCLE", "8", layer, "10", f"{c[0]:.3f}", "20", f"{c[1]:.3f}", "30", "0",
                   "40", f"{r:.3f}"]

    def line(self, p, q, layer):
        self.e += ["0", "LINE", "8", layer, "10", f"{p[0]:.3f}", "20", f"{p[1]:.3f}", "30", "0",
                   "11", f"{q[0]:.3f}", "21", f"{q[1]:.3f}", "31", "0"]

    def text(self, p, h, s, rot=0.0, layer="MARK"):
        self.e += ["0", "TEXT", "8", layer, "10", f"{p[0]:.3f}", "20", f"{p[1]:.3f}", "30", "0",
                   "40", f"{h:.3f}", "1", s, "50", f"{rot:.2f}"]

    def save(self, path):
        hdr = ["0", "SECTION", "2", "HEADER", "9", "$ACADVER", "1", "AC1009",
               "9", "$INSUNITS", "70", "4", "0", "ENDSEC"]
        lay = ["0", "SECTION", "2", "TABLES", "0", "TABLE", "2", "LAYER", "70", str(len(self.COLORS))]
        for n, c in self.COLORS.items():
            lay += ["0", "LAYER", "2", n, "70", "0", "62", str(c), "6", "CONTINUOUS"]
        lay += ["0", "ENDTAB", "0", "ENDSEC"]
        body = ["0", "SECTION", "2", "ENTITIES"] + self.e + ["0", "ENDSEC", "0", "EOF"]
        with open(path, "w", encoding="ascii", newline="\r\n") as f:
            f.write("\n".join(hdr + lay + body) + "\n")


# ----------------------------------------------------------------- деталь
class Part:
    """2D-деталь: контур, отверстия, линии гиба, подписи."""

    def __init__(self, name, outline, holes=(), bends=(), marks=()):
        self.name = name
        self.outline = np.asarray(outline, float)
        self.holes = list(holes)    # (center, r)
        self.bends = list(bends)    # (layer, p, q)
        self.marks = list(marks)    # (p, h, text, rot)

    def tf(self, R, t):
        f = lambda p: np.asarray(p, float) @ R.T + t
        ang = math.degrees(math.atan2(R[1, 0], R[0, 0]))
        return Part(self.name, f(self.outline), [(f(c), r) for c, r in self.holes],
                    [(l, f(p), f(q)) for l, p, q in self.bends],
                    [(f(p), h, s, rot + ang) for p, h, s, rot in self.marks])

    def rotated(self, deg):
        c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
        return self.tf(np.array([[c, -s], [s, c]]), np.zeros(2))

    def moved(self, d):
        return self.tf(np.eye(2), np.asarray(d, float))

    def bbox(self):
        return self.outline.min(0), self.outline.max(0)

    def to_origin(self):
        return self.moved(-self.bbox()[0])

    def best_rotation(self):
        best = min(range(0, 180, 1),
                   key=lambda d: np.prod(np.ptp(self.rotated(d).outline, axis=0)))
        return self.rotated(best).to_origin()

    def draw(self, d):
        d.poly(self.outline)
        for c, r in self.holes:
            d.circle(c, r)
        for l, p, q in self.bends:
            d.line(p, q, l)
        for p, h, s, rot in self.marks:
            d.text(p, h, s, rot)


def unit(v):
    return v / np.linalg.norm(v)


def rot2(v, a):
    c, s = math.cos(a), math.sin(a)
    return np.array([c * v[0] - s * v[1], s * v[0] + c * v[1]])


# ----------------------------------------------------------------- модуль-пирамида
def pyramid_module(p, q, h, flange, hole_d, relief, hole_off=None):
    hole_off = flange * 0.65 if hole_off is None else hole_off
    """p, q — полудиагонали ромба (гориз./верт.), h — высота пирамиды.
    Возвращает (Part, info). Развёртка: веер из 4 граней вокруг вершины A."""
    A = np.array([0, 0, h])
    B = {"S": np.array([0, -q, 0.]), "E": np.array([p, 0, 0.]),
         "N": np.array([0, q, 0.]), "W": np.array([-p, 0, 0.])}
    order = ["S", "E", "N", "W", "S"]
    L = {k: np.linalg.norm(B[k] - A) for k in B}
    ang = []
    for a_, b_ in zip(order, order[1:]):
        u, v = unit(B[a_] - A), unit(B[b_] - A)
        ang.append(math.acos(np.clip(u @ v, -1, 1)))
    total = sum(ang)
    gap = 2 * math.pi - total
    # угловые величины
    n_face = unit(np.cross(B["S"] - A, B["E"] - A))          # нормаль грани (наружу)
    n_face = n_face if n_face[2] > 0 else -n_face
    slope = math.degrees(math.acos(n_face[2]))                 # наклон грани к стене
    n2 = unit(np.cross(B["E"] - A, B["N"] - A))
    n2 = n2 if n2[2] > 0 else -n2
    m = np.array([n_face[0], -n_face[1], n_face[2]])           # соседняя грань S-W-? симметрия по x
    bend_EW = math.degrees(math.acos(np.clip(n_face @ n2, -1, 1)))   # ребро A-E и A-W
    nSW = np.array([-n_face[0], n_face[1], n_face[2]])
    bend_NS = math.degrees(math.acos(np.clip(n_face @ nSW, -1, 1)))  # ребро A-N (и шов A-S)
    tip_ang = {"S": 2 * math.atan(p / q), "N": 2 * math.atan(p / q),
               "E": 2 * math.atan(q / p), "W": 2 * math.atan(q / p)}

    # лучи веера: шов (S...S') смотрит вниз
    th = -math.pi / 2 + gap / 2
    pts = []
    for k, key in enumerate(order):
        pts.append(L[key] * np.array([math.cos(th), math.sin(th)]))
        if k < 4:
            th += ang[k]
    O = np.zeros(2)
    outline = [O]
    bends, holes, marks = [], [], []
    for k in range(4):
        X, Y = pts[k], pts[k + 1]
        kx, ky = order[k], order[k + 1]
        u = unit(Y - X)
        n = np.array([u[1], -u[0]])                      # наружу от вершины
        if n @ ((X + Y) / 2) < 0:
            n = -n
        cx = flange / math.tan(tip_ang[kx] / 2) + relief
        cy = flange / math.tan(tip_ang[ky] / 2) + relief
        Xf = X + n * flange + u * cx
        Yf = Y + n * flange - u * cy
        outline += [X, Xf, Yf, Y] if k == 0 else [Xf, Yf, Y]
        if k == 0:
            outline = [O, X, Xf, Yf, Y]
        bends.append(("BEND_OUT", X, Y))
        mid = (X + Y) / 2 + n * hole_off
        holes.append((mid, hole_d / 2))
        if k < 3:
            bends.append(("BEND_OUT", O, Y))
    outline = np.array(outline)
    # подписи углов гиба
    lab = lambda P, txt: marks.append((P, 4.0, txt, 0.0))
    for k in range(4):
        X, Y = pts[k], pts[k + 1]
        lab((X + Y) / 2 * 0.86 - np.array([8, 2]), f"{180 - slope:.0f}%%d")
    for k, key in zip((1, 2, 3), ("E", "N", "W")):
        a_ = bend_EW if key in "EW" else bend_NS
        lab(pts[k] * 0.45 - np.array([6, 2]), f"{a_:.0f}%%d")
    seam_mid = (pts[0] + pts[4]) / 2 * 0.55
    marks.append((seam_mid - np.array([8, 10]), 4.0, "SHOV", 0.0))
    # 3D-координаты отверстий полок (в плоскости стены, для кассеты)
    hole3d = []
    for kx, ky in zip(order, order[1:]):
        X3, Y3 = B[kx][:2], B[ky][:2]
        mid = (X3 + Y3) / 2
        hole3d.append(mid - unit(mid) * 0 + unit(-mid) * 0)  # заменим ниже
    hole3d = []
    for kx, ky in zip(order, order[1:]):
        X3, Y3 = B[kx][:2], B[ky][:2]
        e = unit(Y3 - X3)
        inward = np.array([-e[1], e[0]])
        if inward @ ((X3 + Y3) / 2) > 0:
            inward = -inward
        hole3d.append((X3 + Y3) / 2 + inward * hole_off)
    info = dict(gap_deg=math.degrees(gap), hole_off=hole_off, clear=hole_off*math.tan(math.atan(h/ (p*q/math.hypot(p,q)))), slope=slope, flange_bend=180 - slope,
                bend_EW=bend_EW, bend_NS=bend_NS, holes=hole3d,
                edge=math.hypot(p, q), lateral=(L["E"], L["N"]))
    return Part("M", outline, holes, bends, marks), info


# ----------------------------------------------------------------- кассета
def cassette(W, H, rim, hole_d, mount_d, pyr_holes, centers, relief=1.0):
    """Плоский лист W x H + отбортовка rim по 4 сторонам (угловые вырезы)."""
    r = rim
    o = [(0, -r), (W, -r), (W, 0), (W + r, 0), (W + r, H), (W, H), (W, H + r),
         (0, H + r), (0, H), (-r, H), (-r, 0), (0, 0)]
    # угловые вырезы с разгрузкой: контур уже проходит по углам листа (0,0)...
    holes = []
    bends = [("BEND_IN", (0, 0), (W, 0)), ("BEND_IN", (W, 0), (W, H)),
             ("BEND_IN", (W, H), (0, H)), ("BEND_IN", (0, H), (0, 0))]
    for c in centers:
        for hp in pyr_holes:
            holes.append((np.array(c) + hp, hole_d / 2))
    # крепёжные отверстия в отбортовке, шаг ~250 мм
    def row(n_len):
        n = max(2, int(round(n_len / 250)) + 1)
        return np.linspace(60, n_len - 60, n)
    for x in row(W):
        holes += [(np.array([x, -r / 2]), mount_d / 2), (np.array([x, H + r / 2]), mount_d / 2)]
    for y in row(H):
        holes += [(np.array([-r / 2, y]), mount_d / 2), (np.array([W + r / 2, y]), mount_d / 2)]
    marks = [((12, 12), 14, "K1", 0.0)]
    return Part("K", np.array(o, float), holes, bends, marks)


def rhombus_centers(W, H, a, b):
    """Полные ромбы (без обрезков) в шахматном порядке."""
    cs = []
    nx, ny = int(round(W / a)), int(round(H / b))
    for j in range(ny):
        for i in range(nx):
            cs.append(((i + 0.5) * a, (j + 0.5) * b))
    for j in range(1, ny):
        for i in range(1, nx):
            cs.append((i * a, j * b))
    return cs


# ----------------------------------------------------------------- раскладка
def nest(parts, SW, SH, gap=6.0, margin=10.0):
    """Полосовая раскладка по габаритам. parts: list of Part (уже у начала координат)."""
    sheets, cur, x, y, row_h = [], [], margin, margin, 0.0
    for P in parts:
        w, h = np.ptp(P.outline, axis=0)
        if w > SW - 2 * margin and h <= SW - 2 * margin:
            P = P.rotated(90).to_origin()
            w, h = h, w
        if x + w > SW - margin:
            x, y, row_h = margin, y + row_h + gap, 0.0
        if y + h > SH - margin:
            sheets.append(cur)
            cur, x, y, row_h = [], margin, margin, 0.0
        cur.append(P.moved((x, y)))
        x += w + gap
        row_h = max(row_h, h)
    if cur:
        sheets.append(cur)
    return sheets


def nest_modules(M, n, SW, SH, gap=5.0, margin=10.0):
    """Модули: чередуем поворот 0/180, чтобы плотнее; полосами."""
    A = M.best_rotation()
    B = A.rotated(180).to_origin()
    w, h = np.ptp(A.outline, axis=0)
    # подбираем сдвиг B относительно A вдоль x до отсутствия пересечения габаритов -> просто ряды
    out, sheets = [], []
    x, y, k = margin, margin, 0
    cur = []
    for i in range(n):
        if x + w > SW - margin:
            x, y = margin, y + h + gap
        if y + h > SH - margin:
            sheets.append(cur)
            cur, x, y = [], margin, margin
        cur.append(A.moved((x, y)))
        x += w + gap
    if cur:
        sheets.append(cur)
    return sheets


# ----------------------------------------------------------------- превью
def preview(parts, SW, SH, path, title):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    sc = 11 / max(SW, SH)
    fig, ax = plt.subplots(figsize=(SW * sc + 0.5, SH * sc + 0.9))
    ax.add_patch(plt.Rectangle((0, 0), SW, SH, fill=False, ec="0.5", lw=0.8))
    for P in parts:
        o = np.vstack([P.outline, P.outline[:1]])
        ax.fill(o[:, 0], o[:, 1], color="#dfe5e8", lw=0)
        ax.plot(o[:, 0], o[:, 1], color="#c62828", lw=0.6)
        for c, r in P.holes:
            ax.add_patch(plt.Circle(c, r, fill=False, ec="#c62828", lw=0.4))
        for l, p, q in P.bends:
            ax.plot([p[0], q[0]], [p[1], q[1]], lw=0.5,
                    color="#2e7d32" if l == "BEND_OUT" else "#8e24aa",
                    ls="-" if l == "BEND_OUT" else "--")
    ax.set_aspect("equal")
    ax.set_xlim(-30, SW + 30)
    ax.set_ylim(-30, SH + 30)
    ax.set_title(title, fontsize=8)
    ax.axis("off")
    fig.tight_layout()
    fig.savefig(path, dpi=130)
    plt.close(fig)


def preview_part(P, path, title, dpi=160):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    w, h = np.ptp(P.outline, axis=0)
    fig, ax = plt.subplots(figsize=(7, 7 * h / w + 0.6))
    o = np.vstack([P.outline, P.outline[:1]])
    ax.fill(o[:, 0], o[:, 1], color="#dfe5e8", lw=0)
    ax.plot(o[:, 0], o[:, 1], color="#c62828", lw=1.2, label="CUT — резка")
    for c, r in P.holes:
        ax.add_patch(plt.Circle(c, r, fill=False, ec="#c62828", lw=1))
    first = {"BEND_OUT": True, "BEND_IN": True}
    for l, p, q in P.bends:
        ax.plot([p[0], q[0]], [p[1], q[1]], lw=1.1,
                color="#2e7d32" if l == "BEND_OUT" else "#8e24aa",
                ls="-" if l == "BEND_OUT" else "--",
                label=("BEND_OUT — гиб «горой»" if l == "BEND_OUT" else "BEND_IN — гиб «долиной»")
                if first[l] else None)
        first[l] = False
    for p, hh, s, rot in P.marks:
        ax.text(p[0], p[1], s.replace("%%d", "°").replace("SHOV", "шов"), fontsize=8,
                color="#1565c0", rotation=rot)
    ax.set_aspect("equal")
    ax.legend(loc="upper right", fontsize=7)
    ax.set_title(title, fontsize=9)
    ax.axis("off")
    fig.tight_layout()
    fig.savefig(path, dpi=dpi)
    plt.close(fig)


def render3d(W, H, p, q, h, centers, path):
    """Вид спереди с освещением (как будет выглядеть на фасаде)."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib.patches import Polygon, Rectangle
    light = unit(np.array([-0.6, 0.5, 0.65]))
    fig, ax = plt.subplots(figsize=(8, 8 * H / W))
    ax.add_patch(Rectangle((0, 0), W, H, color="#8a9499"))
    for cx, cy in centers:
        A = np.array([cx, cy, h])
        V = [np.array([cx, cy - q, 0]), np.array([cx + p, cy, 0]),
             np.array([cx, cy + q, 0]), np.array([cx - p, cy, 0])]
        for k in range(4):
            t = [A, V[k], V[(k + 1) % 4]]
            n = unit(np.cross(t[1] - t[0], t[2] - t[0]))
            n = n if n[2] > 0 else -n
            s = 0.35 + 0.65 * max(0, n @ light)
            ax.add_patch(Polygon([x[:2] for x in t], closed=True, fc=(s, s, s * 1.02 if s < 0.98 else s),
                                 ec="#5f6b70", lw=0.3))
    ax.set_xlim(0, W); ax.set_ylim(0, H); ax.set_aspect("equal"); ax.axis("off")
    ax.set_title(f"Вид кассеты спереди {W:.0f}x{H:.0f} мм", fontsize=9)
    fig.tight_layout(); fig.savefig(path, dpi=140); plt.close(fig)


# ----------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--width", type=float, default=1000)
    ap.add_argument("--height", type=float, default=1000)
    ap.add_argument("--rhomb", default="200x250", help="диагонали ромба: ширина x высота, мм")
    ap.add_argument("--depth", type=float, default=40, help="высота пирамиды, мм")
    ap.add_argument("--gap", type=float, default=2, help="зазор между соседними пирамидами, мм")
    ap.add_argument("--flange", type=float, default=30, help="полка модуля под заклёпку, мм")
    ap.add_argument("--rim", type=float, default=30, help="отбортовка кассеты, мм")
    ap.add_argument("--rivet", type=float, default=4.2, help="отверстие под заклёпку, мм")
    ap.add_argument("--mount", type=float, default=6.5, help="отверстие крепления кассеты, мм")
    ap.add_argument("--thickness", type=float, default=1.0)
    ap.add_argument("--sheet", default="1250x2500")
    ap.add_argument("--qty", type=int, default=1, help="сколько кассет")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    SW, SH = sorted(float(v) for v in a.sheet.lower().split("x"))
    ra, rb = (float(v) for v in a.rhomb.lower().split("x"))
    W, H = a.width, a.height

    # уменьшаем ромб, чтобы между соседями был зазор a.gap
    p0, q0 = ra / 2, rb / 2
    d0 = p0 * q0 / math.hypot(p0, q0)
    s = (d0 - a.gap / 2) / d0
    p, q = p0 * s, q0 * s

    M, info = pyramid_module(p, q, a.depth, a.flange, a.rivet, relief=1.0)
    centers = rhombus_centers(W, H, ra, rb)
    n_mod = len(centers) * a.qty
    K = cassette(W, H, a.rim, a.rivet, a.mount, info["holes"], centers)

    Mz = M.best_rotation()
    # маркировка номера на модуле
    Mz.marks.append((np.ptp(Mz.outline, axis=0) / 2 - [10, 4], 7, "M1", 0.0))
    d = DXF(); Mz.draw(d); d.save(os.path.join(a.out, "module_M1.dxf"))
    Kz = K.to_origin()
    d = DXF(); Kz.draw(d); d.save(os.path.join(a.out, "cassette_K1.dxf"))
    preview_part(Mz, os.path.join(a.out, "module_M1.png"),
                 f"Модуль M1 — ромб {ra:.0f}x{rb:.0f}, высота {a.depth:.0f} мм, металл {a.thickness} мм. "
                 f"Кол-во: {n_mod} шт")
    preview_part(Kz, os.path.join(a.out, "cassette_K1.png"),
                 f"Кассета K1 {W:.0f}x{H:.0f}, отбортовка {a.rim:.0f} мм. Кол-во: {a.qty} шт", dpi=110)

    # раскладка: на каждый лист — кассета (если влезает) + модули в оставшееся место
    kw, kh = np.ptp(Kz.outline, axis=0)
    if kw > SW - 20 or kh > SH - 20:
        Kz = Kz.rotated(90).to_origin()
        kw, kh = np.ptp(Kz.outline, axis=0)
    if kw > SW - 20 or kh > SH - 20:
        raise SystemExit(f"Кассета {kw:.0f}x{kh:.0f} не помещается на лист {SW:.0f}x{SH:.0f}")
    mw, mh = np.ptp(Mz.outline, axis=0)
    g, mg = 6.0, 10.0

    def fill(region, left):
        x0, y0, x1, y1 = region
        out = []
        y = y0
        while y + mh <= y1 and left > len(out):
            x = x0
            while x + mw <= x1 and left > len(out):
                out.append(Mz.moved((x, y)))
                x += mw + g
            y += mh + g
        return out

    allsheets = []
    cas_left, mod_left = a.qty, n_mod
    while cas_left or mod_left:
        parts = []
        if cas_left:
            parts.append(Kz.moved((mg, mg)))
            cas_left -= 1
            regions = [(mg, mg + kh + g, SW - mg, SH - mg), (mg + kw + g, mg, SW - mg, mg + kh)]
        else:
            regions = [(mg, mg, SW - mg, SH - mg)]
        for rg in regions:
            got = fill(rg, mod_left)
            parts += got
            mod_left -= len(got)
        allsheets.append(parts)
    sheet_dir = os.path.join(a.out, "sheets")
    import shutil
    shutil.rmtree(sheet_dir, ignore_errors=True)
    os.makedirs(sheet_dir)
    for i, s_ in enumerate(allsheets, 1):
        d = DXF()
        for P in s_:
            P.draw(d)
        d.save(os.path.join(sheet_dir, f"sheet_{i}.dxf"))
        nk = sum(P.name == "K" for P in s_)
        preview(s_, SW, SH, os.path.join(sheet_dir, f"sheet_{i}.png"),
                f"Лист {i}/{len(allsheets)} {SW:.0f}x{SH:.0f}, металл {a.thickness} мм — "
                f"кассет {nk}, модулей {len(s_) - nk}")
    render3d(W, H, p, q, a.depth, centers, os.path.join(a.out, "view_3d.png"))

    def area(o):
        x, y = o[:, 0], o[:, 1]
        return 0.5 * abs(np.dot(x, np.roll(y, -1)) - np.dot(y, np.roll(x, -1)))
    am, ak = area(Mz.outline), area(Kz.outline)
    mass = (am * n_mod + ak * a.qty) * a.thickness * 7.85e-6
    rep = [
        f"Кассета {W:.0f} x {H:.0f} мм, кол-во {a.qty}",
        f"Ромб (диагонали) {ra:.0f} x {rb:.0f} мм, высота пирамиды {a.depth:.0f} мм, зазор {a.gap:.0f} мм",
        f"Модулей M1: {n_mod} шт (на одну кассету {len(centers)})",
        f"Наклон граней к стене: {info['slope']:.1f}°",
        f"Углы гиба: рёбра A-E/A-W {info['bend_EW']:.1f}°, ребро A-N {info['bend_NS']:.1f}°, "
        f"полки {info['flange_bend']:.1f}° (загиб под пирамиду, в плоскость стены)",
        f"Шов A-S (снизу): после гиба сходится стык, угол раскрытия в развёртке {info['gap_deg']:.1f}° — "
        f"проварить точками/TIG, зачистить",
        f"Отверстия Ø{a.rivet} мм: 4 на модуль (на {info['hole_off']:.0f} мм от линии гиба полки), совпадают с отверстиями в кассете. "
        f"Над отверстием до грани ~{info['clear']-2*a.thickness:.0f} мм свободно — для 2 мм надёжнее электрозаклёпка (сварка через отверстие), "
        f"либо вытяжная заклёпка 4 мм с короткой длиной захвата, вставлять с обратной стороны кассеты",
        f"Листов {SW:.0f}x{SH:.0f}: {len(allsheets)}",
        f"Масса металла (сталь {a.thickness} мм): ~{mass:.1f} кг",
        "Учёт гиба: развёртка по наружной поверхности; для 2 мм при углах гиба 33–42° погрешность ~1 мм, на полках 153° — ~2 мм. "
        "перед партией согните пробный модуль.",
    ]
    open(os.path.join(a.out, "report.txt"), "w").write("\n".join(rep) + "\n")
    print("\n".join(rep))


if __name__ == "__main__":
    main()
