#!/usr/bin/env python3
"""Мини-интерпретатор подмножества AutoLISP для проверки vorota.lsp без AutoCAD.
Выполняет команду с заранее заданными ответами, собирает entmake-объекты
и ActiveX-вызовы (3D) и пишет DXF развёртки + PNG.

python3 mini_autolisp.py ../vorota.lsp out_dir answers...
"""
import math
import sys


class Sym(str):
    pass


class Pair:
    def __init__(self, a, d):
        self.a, self.d = a, d

    def __repr__(self):
        return f"({self.a!r} . {self.d!r})"


T = Sym("T")


def tokenize(s):
    i, out = 0, []
    while i < len(s):
        c = s[i]
        if c in " \t\r\n":
            i += 1
        elif c == ";":
            while i < len(s) and s[i] != "\n":
                i += 1
        elif c in "()'":
            out.append(c)
            i += 1
        elif c == '"':
            j, buf = i + 1, []
            while s[j] != '"':
                if s[j] == "\\":
                    nx = s[j + 1]
                    buf.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(nx, nx))
                    j += 2
                else:
                    buf.append(s[j])
                    j += 1
            out.append(("STR", "".join(buf)))
            i = j + 1
        else:
            j = i
            while j < len(s) and s[j] not in " \t\r\n()';\"":
                j += 1
            out.append(s[i:j])
            i = j
    return out


def parse(tokens):
    pos = 0

    def atom(t):
        if isinstance(t, tuple):
            return t[1]
        try:
            return int(t)
        except ValueError:
            pass
        try:
            return float(t)
        except ValueError:
            return Sym(t.upper())

    def read():
        nonlocal pos
        t = tokens[pos]
        pos += 1
        if t == "'":
            return [Sym("QUOTE"), read()]
        if t == "(":
            lst = []
            while tokens[pos] != ")":
                if tokens[pos] == ".":
                    pos += 1
                    d = read()
                    assert tokens[pos] == ")"
                    pos += 1
                    return Pair(lst[0], d) if len(lst) == 1 else lst
                lst.append(read())
            pos += 1
            return lst
        return atom(t)

    forms = []
    while pos < len(tokens):
        forms.append(read())
    return forms


class Interp:
    def __init__(self, answers):
        self.g = {Sym("PI"): math.pi, T: T, Sym("NIL"): None}
        self.answers = list(answers)
        self.ents = []
        self.solids = 0
        self.regions = 0
        self.vars = {"CMDECHO": 1}
        self.funcs = {}
        self.out = []
        self._builtins()

    def truthy(self, v):
        return v is not None and v != [] and v is not False

    # ---------------- builtins
    def _builtins(self):
        B = self.b = {}

        def num_div(*a):
            r = a[0]
            for x in a[1:]:
                if isinstance(r, int) and isinstance(x, int):
                    r = int(r / x)
                else:
                    r = r / x
            return r

        def lisp_rem(a, b):
            if isinstance(a, int) and isinstance(b, int):
                return int(math.fmod(a, b))
            return math.fmod(a, b)

        def car(x):
            return x.a if isinstance(x, Pair) else (x[0] if x else None)

        def cdr(x):
            return x.d if isinstance(x, Pair) else (x[1:] if x else None)

        def cons(a, d):
            if isinstance(d, list):
                return [a] + d
            if d is None:
                return [a]
            return Pair(a, d)

        def nth(i, l):
            return l[i] if l is not None and i < len(l) else None

        def rtos(v, mode=2, prec=4):
            return f"{v:.{prec}f}"

        def tb(x):
            return T if x else None
        B.update({
            "+": lambda *a: sum(a) if a else 0, "-": lambda *a: -a[0] if len(a) == 1 else a[0] - sum(a[1:]),
            "*": lambda *a: math.prod(a), "/": num_div, "REM": lisp_rem,
            "1+": lambda a: a + 1, "1-": lambda a: a - 1, "ABS": abs, "MIN": min, "MAX": max,
            "SQRT": math.sqrt, "SIN": math.sin, "COS": math.cos, "FIX": lambda a: int(a),
            "FLOAT": float, "=": lambda a, b: tb(a == b), "/=": lambda a, b: tb(a != b),
            "<": lambda a, b: tb(a < b), ">": lambda a, b: tb(a > b), "<=": lambda a, b: tb(a <= b),
            ">=": lambda a, b: tb(a >= b), "NOT": lambda a: tb(not self.truthy(a)),
            "NULL": lambda a: tb(not self.truthy(a)),
            "LIST": lambda *a: list(a), "CONS": cons, "CAR": car, "CDR": cdr,
            "CADR": lambda x: x[1] if x and len(x) > 1 else None, "NTH": nth,
            "LENGTH": lambda l: len(l) if l else 0, "APPEND": lambda *a: sum([x or [] for x in a], []),
            "REVERSE": lambda l: list(reversed(l)) if l else None, "LAST": lambda l: l[-1] if l else None,
            "DISTANCE": lambda a, b: math.dist(a[:2], b[:2]) if len(a) == 2 or len(b) == 2 else math.dist(a, b),
            "STRCAT": lambda *a: "".join(a), "ITOA": lambda a: str(a), "RTOS": rtos,
            "STRCASE": lambda s, *a: s.upper(), "WCMATCH": lambda s, p: None,
            "PRINC": self._princ, "INITGET": lambda *a: None, "VL-LOAD-COM": lambda: None,
            "GETREAL": self._get, "GETINT": self._get, "SETVAR": lambda n, v: self.vars.__setitem__(n, v),
            "GETVAR": lambda n: self.vars.get(n), "TBLSEARCH": lambda *a: None,
            "ENTMAKE": self._entmake, "ENTLAST": lambda: len(self.ents) - 1,
            "ENTDEL": lambda e: self.ents.__setitem__(e, None),
            "APPLY": lambda f, args: self.call(f, args),
            "MAPCAR": lambda f, *ls: [self.call(f, list(xs)) for xs in zip(*ls)] or None,
            # ActiveX заглушки
            "VLAX-GET-ACAD-OBJECT": lambda: "ACAD", "VLA-GET-ACTIVEDOCUMENT": lambda a: "DOC",
            "VLA-GET-MODELSPACE": lambda d: "MS", "VLA-STARTUNDOMARK": lambda d: None,
            "VLA-ENDUNDOMARK": lambda d: None, "VLA-ZOOMEXTENTS": lambda a: None,
            "VLAX-MAKE-SAFEARRAY": lambda *a: [None], "VLAX-VBOBJECT": 9,
            "VLAX-SAFEARRAY-PUT-ELEMENT": lambda arr, i, v: arr.__setitem__(i, v),
            "VLAX-ENAME->VLA-OBJECT": lambda e: ("OBJ", e),
            "VLA-ADDREGION": self._addregion, "VLAX-VARIANT-VALUE": lambda v: v,
            "VLAX-SAFEARRAY->LIST": lambda v: v,
            "VLA-ADDEXTRUDEDSOLID": self._extrude, "VLA-DELETE": lambda o: None,
            "VLA-PUT-LAYER": lambda o, l: None, "VLA-BOOLEAN": self._boolean,
            "VLA-ROTATE3D": self._rot, "VLAX-3D-POINT": lambda p: p, "VLA-ADDBOX": self._box,
        })

    def _princ(self, s=None):
        if s is not None:
            self.out.append(str(s))
        return s

    def _get(self, prompt):
        self.out.append(prompt)
        a = self.answers.pop(0) if self.answers else ""
        self.out.append(f"  -> {a!r}")
        if a == "":
            return None
        return float(a) if "." in a else int(a)

    def _entmake(self, data):
        d = {}
        pts = []
        for item in data:
            if isinstance(item, Pair):
                d.setdefault(item.a, item.d)
            elif isinstance(item, list) and item and item[0] == 10:
                pts.append(item[1:])
            elif isinstance(item, list):
                d.setdefault(item[0], item[1:])
        if pts:
            d["PTS"] = pts
            d.setdefault(10, pts[0])
        self.ents.append(d)
        return data

    def _addregion(self, ms, arr):
        self.regions += 1
        obj = arr[0]
        e = self.ents[obj[1]]
        pts = e["PTS"]
        # самопроверка: многоугольник не вырожден
        a = 0.5 * abs(sum(p[0] * q[1] - p[1] * q[0] for p, q in zip(pts, pts[1:] + pts[:1])))
        assert a > 1e-6, "вырожденный регион"
        return [("REGION", pts)]

    def _extrude(self, ms, reg, h, taper):
        assert h > 0
        self.solids += 1
        return ("SOLID", reg)

    def _boolean(self, a, op, b):
        assert op == 2
        return None

    def _rot(self, obj, p1, p2, ang):
        assert len(p1) == 3 and len(p2) == 3 and abs(ang) < math.pi
        self.rot = getattr(self, "rot", 0) + 1

    def _box(self, ms, c, l, w, h):
        assert l > 0 and w > 0 and h > 0, ("box", c, l, w, h)
        self.solids += 1
        return ("BOX",)

    # ---------------- eval
    def call(self, f, args):
        if isinstance(f, Sym):
            if f in self.funcs:
                return self.apply_user(self.funcs[f], args)
            if f in self.b:
                return self.b[f](*args)
            raise NameError(f"нет функции {f}")
        if isinstance(f, list) and f and f[0] == "LAMBDA":
            return self.apply_user((f[1], f[2:]), args)
        if callable(f):
            return f(*args)
        raise TypeError(f"не функция: {f!r}")

    def apply_user(self, fn, args):
        params, body = fn
        if "/" in params:
            k = params.index("/")
            ps, locs = params[:k], params[k + 1:]
        else:
            ps, locs = params, []
        if len(args) != len(ps):
            raise TypeError(f"неверное число аргументов: ждали {ps}, дали {len(args)}")
        saved = {s: self.g.get(s, "__UNBOUND__") for s in ps + locs}
        for s in locs:
            self.g[s] = None
        for s, v in zip(ps, args):
            self.g[s] = v
        saved_funcs = {s: self.funcs.get(s) for s in locs if s in self.funcs}
        try:
            r = None
            for f in body:
                r = self.ev(f)
            return r
        finally:
            for s, v in saved.items():
                if v == "__UNBOUND__":
                    self.g.pop(s, None)
                else:
                    self.g[s] = v

    def ev(self, x):
        if isinstance(x, Sym):
            if x in self.g:
                return self.g[x]
            if x in self.b or x in self.funcs:
                return x
            return None
        if not isinstance(x, list):
            return x
        if not x:
            return None
        h = x[0]
        if h == "QUOTE":
            return x[1]
        if h == "SETQ":
            r = None
            for i in range(1, len(x), 2):
                r = self.ev(x[i + 1])
                self.g[x[i]] = r
            return r
        if h == "DEFUN":
            name = x[1]
            self.funcs[name] = (x[2], x[3:])
            return name
        if h == "IF":
            if self.truthy(self.ev(x[1])):
                return self.ev(x[2])
            return self.ev(x[3]) if len(x) > 3 else None
        if h == "PROGN":
            r = None
            for f in x[1:]:
                r = self.ev(f)
            return r
        if h == "WHILE":
            r = None
            while self.truthy(self.ev(x[1])):
                for f in x[2:]:
                    r = self.ev(f)
            return r
        if h == "REPEAT":
            r = None
            for _ in range(self.ev(x[1])):
                for f in x[2:]:
                    r = self.ev(f)
            return r
        if h == "FOREACH":
            var, lst = x[1], self.ev(x[2])
            old = self.g.get(var)
            r = None
            for v in (lst or []):
                self.g[var] = v
                for f in x[3:]:
                    r = self.ev(f)
            self.g[var] = old
            return r
        if h == "COND":
            for clause in x[1:]:
                v = self.ev(clause[0])
                if self.truthy(v):
                    r = v
                    for f in clause[1:]:
                        r = self.ev(f)
                    return r
            return None
        if h == "AND":
            for f in x[1:]:
                if not self.truthy(self.ev(f)):
                    return None
            return T
        if h == "OR":
            for f in x[1:]:
                if self.truthy(self.ev(f)):
                    return T
            return None
        if h == "LAMBDA":
            return x
        f = h if isinstance(h, Sym) else self.ev(h)
        args = [self.ev(a) for a in x[1:]]
        if isinstance(f, Sym) and f in self.g and isinstance(self.g[f], list):
            f = self.g[f]
        return self.call(f, args)


def run(lsp, outdir, answers):
    import os
    src = open(lsp, encoding="utf-8").read()
    it = Interp(answers)
    for form in parse(tokenize(src)):
        it.ev(form)
    it.ev([Sym("C:VOROTA")])
    os.makedirs(outdir, exist_ok=True)
    lines = [e for e in it.ents if e and e.get(0) == "LINE"]
    circles = [e for e in it.ents if e and e.get(0) == "CIRCLE"]
    polys = [e for e in it.ents if e and e.get(0) == "LWPOLYLINE" and e.get(8) != "0"]
    texts = [e for e in it.ents if e and e.get(0) == "TEXT"]
    return it, lines, circles, polys, texts


if __name__ == "__main__":
    it, lines, circles, polys, texts = run(sys.argv[1], sys.argv[2], sys.argv[3:])
    print("\n".join(it.out[-6:]))
    print(f"LINE {len(lines)}, CIRCLE {len(circles)}, LWPOLYLINE {len(polys)}, TEXT {len(texts)}, "
          f"3D тел {it.solids}, регионов {it.regions}, поворотов {getattr(it, 'rot', 0)}")
