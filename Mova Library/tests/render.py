#!/usr/bin/env python3
"""Rough offline renderer for the mock instance tree: a small layout engine (UDim2, AnchorPoint,
UIPadding, UIListLayout, AutomaticSize, UIScale, UISizeConstraint) plus a PIL painter (rounded
rects, strokes, gradients, text). It is NOT Roblox - fonts, gradients and shadows are approximate -
but it is close enough to spot structure problems: overlaps, misalignment, bad spacing.

    python3 tests/render.py scene.lua out.png [--theme Mono] [--width 1280 --height 720]

The scene file receives (mock, Mova) and must return the ScreenGui/root to render (or nil for all
of CoreGui).
"""
import importlib
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FONT_DIR = "/usr/share/fonts/truetype/dejavu"


def font_for(size, weight):
    bold = weight in ("Bold", "SemiBold", "Heavy")
    path = os.path.join(FONT_DIR, "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf")
    # DejaVu renders wider than Gotham; scale down a touch so truncation behaves similarly
    return ImageFont.truetype(path, max(6, int(round(size * 0.86))))


# --------------------------------------------------------------------------- Lua -> Python tree
def lua_tree(obj):
    props = obj["_props"]
    node = {"class": obj["_class"], "props": {}, "children": [], "lua": obj}
    p = node["props"]
    for key in [
        "Name", "Visible", "Size", "Position", "AnchorPoint", "BackgroundColor3", "BackgroundTransparency", "ZIndex",
        "LayoutOrder", "ClipsDescendants", "AutomaticSize", "Text", "TextSize", "TextColor3", "TextTransparency",
        "TextXAlignment", "TextYAlignment", "TextWrapped", "TextTruncate", "Image", "ImageColor3", "ImageTransparency",
        "Rotation", "CornerRadius", "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight", "Padding",
        "FillDirection", "HorizontalAlignment", "VerticalAlignment", "SortOrder", "Wraps", "Color", "Thickness",
        "Transparency", "Scale", "MinSize", "MaxSize", "Enabled", "FontFace", "PlaceholderText", "PlaceholderColor3",
        "CanvasPosition", "ScrollBarThickness", "LineHeight", "Offset", "AspectRatio", "AbsoluteSize",
    ]:
        v = props[key]
        if v is not None:
            p[key] = convert(v)
    for child in obj["_children"].values():
        if not child["_destroyed"]:
            node["children"].append(lua_tree(child))
    return node


def convert(v):
    t = type(v).__name__
    if t in ("int", "float", "str", "bool"):
        return v
    try:
        keys = list(v.keys())
    except Exception:  # noqa: BLE001
        return str(v)
    if "Scale" in keys and "Offset" in keys:
        return ("UDim", float(v["Scale"]), float(v["Offset"]))
    if "X" in keys and "Y" in keys:
        x, y = v["X"], v["Y"]
        if hasattr(x, "keys"):
            return ("UDim2", float(x["Scale"]), float(x["Offset"]), float(y["Scale"]), float(y["Offset"]))
        return ("Vector2", float(x), float(y))
    if "R" in keys and "G" in keys:
        return ("Color3", float(v["R"]), float(v["G"]), float(v["B"]))
    if "Name" in keys and "EnumType" in keys:
        return ("Enum", v["Name"])
    if "Keypoints" in keys:
        pts = []
        kps = list(v["Keypoints"].values())
        for i, kp in enumerate(kps):
            if not hasattr(kp, "keys") or kp["Time"] is None:
                # ColorSequence.new(a, b) stores bare values
                val = kp
                pts.append((i / max(1, len(kps) - 1), convert(val) if hasattr(val, "keys") else float(val)))
            else:
                val = kp["Value"]
                pts.append((float(kp["Time"]), convert(val) if hasattr(val, "keys") else float(val)))
        return ("Seq", pts)
    if "Weight" in keys:
        w = v["Weight"]
        return ("Font", w["Name"] if hasattr(w, "keys") else str(w))
    return str(v)


# --------------------------------------------------------------------------- layout
def enum_name(v, default=None):
    if isinstance(v, tuple) and v[0] == "Enum":
        return v[1]
    return default


def text_width(text, fnt):
    if not text:
        return 0
    return fnt.getlength(text)


def wrap_text(text, fnt, width):
    words = text.split(" ")
    lines, cur = [], ""
    for w in words:
        trial = (cur + " " + w) if cur else w
        if text_width(trial, fnt) <= width or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines or [""]


class Box:
    __slots__ = ("node", "x", "y", "w", "h", "scale", "children", "clip", "z")

    def __init__(self, node):
        self.node = node
        self.x = self.y = self.w = self.h = 0.0
        self.scale = 1.0
        self.children = []
        self.clip = None
        self.z = 0


def gui_children(node):
    return [c for c in node["children"] if not c["class"].startswith("UI") and c["class"] not in ("Folder",)]


def modifiers(node):
    out = {"padding": (("UDim", 0, 0),) * 4, "list": None, "corner": 0, "stroke": None, "gradient": None, "scale": 1.0, "constraint": None}
    for c in node["children"]:
        cls, p = c["class"], c["props"]
        if cls == "UIPadding":
            out["padding"] = tuple(p.get(k, ("UDim", 0, 0)) for k in ("PaddingTop", "PaddingRight", "PaddingBottom", "PaddingLeft"))
        elif cls == "UIListLayout":
            out["list"] = p
        elif cls == "UICorner":
            out["corner"] = p.get("CornerRadius", ("UDim", 0, 8))
        elif cls == "UIStroke":
            out["stroke"] = p
        elif cls == "UIGradient":
            out["gradient"] = p
        elif cls == "UIScale":
            out["scale"] = float(p.get("Scale", 1))
        elif cls == "UISizeConstraint":
            out["constraint"] = p
    return out


def udim_px(u, parent):
    return u[1] * parent + u[2]


def text_size_px(node, width_limit):
    p = node["props"]
    txt = str(p.get("Text", ""))
    size = float(p.get("TextSize", 14))
    weight = p.get("FontFace", ("Font", "Regular"))[1] if isinstance(p.get("FontFace"), tuple) else "Regular"
    fnt = font_for(size, weight)
    if p.get("TextWrapped") and width_limit > 0:
        lines = wrap_text(txt, fnt, width_limit)
    else:
        lines = [txt]
    lh = size * float(p.get("LineHeight", 1.0) or 1.0)
    return max(text_width(l, fnt) for l in lines), lh * len(lines), lines, fnt


def layout(node, px, py, pw, ph, depth=0):
    """Compute absolute boxes. Returns Box (with children) or None when invisible."""
    p = node["props"]
    if p.get("Visible") is False or (node["class"] == "ScreenGui" and p.get("Enabled") is False):
        return None
    box = Box(node)
    box.z = int(p.get("ZIndex", 1) or 1)
    if node["class"] in ("ScreenGui", "Folder"):
        box.x, box.y, box.w, box.h = px, py, pw, ph
    else:
        size = p.get("Size", ("UDim2", 0, 100, 0, 100))
        pos = p.get("Position", ("UDim2", 0, 0, 0, 0))
        anchor = p.get("AnchorPoint", ("Vector2", 0, 0))
        w = udim_px(("UDim", size[1], size[2]), pw)
        h = udim_px(("UDim", size[3], size[4]), ph)
        auto = enum_name(p.get("AutomaticSize"), "None")
        mods = modifiers(node)
        if auto in ("Y", "XY", "X"):
            cw, ch = measure_content(node, w if auto != "X" else 1e9, mods)
            if auto in ("Y", "XY"):
                h = max(h, ch)
            if auto in ("X", "XY"):
                w = max(w, cw)
        c = mods["constraint"]
        if c:
            mn, mx = c.get("MinSize"), c.get("MaxSize")
            if mn:
                w, h = max(w, mn[1]), max(h, mn[2])
            if mx:
                w, h = min(w, mx[1]), min(h, mx[2])
        box.w, box.h = w, h
        box.x = px + udim_px(("UDim", pos[1], pos[2]), pw) - anchor[1] * w
        box.y = py + udim_px(("UDim", pos[3], pos[4]), ph) - anchor[2] * h
        box.scale = mods["scale"]
    if node["class"] in ("ScrollingFrame",) or p.get("ClipsDescendants"):
        box.clip = (box.x, box.y, box.x + box.w, box.y + box.h)
    place_children(box, node)
    return box


def measure_content(node, width, mods):
    """Height/width needed by children (for AutomaticSize)."""
    pt, pr, pb, pl = [u[2] for u in mods["padding"]]
    inner_w = max(0, width - pl - pr)
    if node["class"] in ("TextLabel", "TextButton", "TextBox"):
        tw, th, _, _ = text_size_px(node, inner_w)
        return tw + pl + pr, th + pt + pb
    lst = mods["list"]
    kids = [c for c in gui_children(node) if c["props"].get("Visible") is not False]
    if lst:
        gap = lst.get("Padding", ("UDim", 0, 0))[2]
        horizontal = enum_name(lst.get("FillDirection"), "Vertical") == "Horizontal"
        total, cross = 0.0, 0.0
        for k in kids:
            kw, kh = child_extent(k, inner_w)
            if horizontal:
                total += kw
                cross = max(cross, kh)
            else:
                total += kh
                cross = max(cross, kw)
        if kids:
            total += gap * (len(kids) - 1)
        if horizontal:
            return total + pl + pr, cross + pt + pb
        return cross + pl + pr, total + pt + pb
    maxx = maxy = 0.0
    for k in kids:
        kw, kh = child_extent(k, inner_w)
        kp = k["props"]
        pos = kp.get("Position", ("UDim2", 0, 0, 0, 0))
        anchor = kp.get("AnchorPoint", ("Vector2", 0, 0))
        x = pos[2] - anchor[1] * kw if pos[1] == 0 else 0
        y = pos[4] - anchor[2] * kh if pos[3] == 0 else 0
        if pos[1] == 0:
            maxx = max(maxx, x + kw)
        if pos[3] == 0:
            maxy = max(maxy, y + kh)
    return maxx + pl + pr, maxy + pt + pb


def child_extent(k, parent_w):
    kp = k["props"]
    size = kp.get("Size", ("UDim2", 0, 100, 0, 100))
    w = size[1] * parent_w + size[2]
    h = size[4]  # scale on Y can't be resolved against an auto parent; treat as 0
    auto = enum_name(kp.get("AutomaticSize"), "None")
    if auto != "None":
        mods = modifiers(k)
        cw, ch = measure_content(k, w if auto != "X" else 1e9, mods)
        if auto in ("Y", "XY"):
            h = max(h, ch)
        if auto in ("X", "XY"):
            w = max(w, cw)
    c = modifiers(k)["constraint"]
    if c and c.get("MinSize"):
        w, h = max(w, c["MinSize"][1]), max(h, c["MinSize"][2])
    return w, h


def place_children(box, node):
    mods = modifiers(node)
    pt, pr, pb, pl = [u[2] for u in mods["padding"]]
    ix, iy = box.x + pl, box.y + pt
    iw, ih = max(0, box.w - pl - pr), max(0, box.h - pt - pb)
    if node["class"] == "ScrollingFrame":
        cp = node["props"].get("CanvasPosition")
        if cp:
            ix -= cp[1]
            iy -= cp[2]
    kids = gui_children(node)
    lst = mods["list"]
    if lst:
        order = enum_name(lst.get("SortOrder"), "LayoutOrder")
        if order == "LayoutOrder":
            kids = sorted(kids, key=lambda c: (c["props"].get("LayoutOrder", 0), kids.index(c)))
        else:
            kids = sorted(kids, key=lambda c: str(c["props"].get("Name", "")))
        gap = lst.get("Padding", ("UDim", 0, 0))[2]
        horizontal = enum_name(lst.get("FillDirection"), "Vertical") == "Horizontal"
        halign = enum_name(lst.get("HorizontalAlignment"), "Left")
        valign = enum_name(lst.get("VerticalAlignment"), "Top")
        cursor = 0.0
        boxes = []
        for k in kids:
            if k["props"].get("Visible") is False:
                continue
            kw, kh = child_extent(k, iw)
            if horizontal:
                b = layout(k, ix + cursor, iy, iw, ih)
                if b:
                    b.x = ix + cursor
                    if valign == "Center":
                        b.y = iy + (ih - b.h) / 2
                    elif valign == "Bottom":
                        b.y = iy + ih - b.h
                    else:
                        b.y = iy
                    reposition_children(b, k)
                    cursor += b.w + gap
                    boxes.append(b)
            else:
                b = layout(k, ix, iy + cursor, iw, ih)
                if b:
                    if halign == "Center":
                        b.x = ix + (iw - b.w) / 2
                    elif halign == "Right":
                        b.x = ix + iw - b.w
                    else:
                        b.x = ix
                    b.y = iy + cursor
                    reposition_children(b, k)
                    cursor += b.h + gap
                    boxes.append(b)
        if not horizontal and valign == "Center" and boxes:
            total = cursor - gap
            shift = (ih - total) / 2
            for b in boxes:
                b.y += shift
                reposition_children(b, b.node)
        if horizontal and boxes and halign in ("Center", "Right"):
            total = cursor - gap
            shift = (iw - total) / 2 if halign == "Center" else iw - total
            for b in boxes:
                b.x += shift
                reposition_children(b, b.node)
        box.children = boxes
    else:
        for k in kids:
            b = layout(k, ix, iy, iw, ih)
            if b:
                box.children.append(b)


def reposition_children(box, node):
    box.children = []
    if node["class"] in ("ScrollingFrame",) or node["props"].get("ClipsDescendants"):
        box.clip = (box.x, box.y, box.x + box.w, box.y + box.h)
    place_children(box, node)


# --------------------------------------------------------------------------- paint
def col(c, default=(255, 255, 255)):
    if isinstance(c, tuple) and c[0] == "Color3":
        return (int(round(c[1] * 255)), int(round(c[2] * 255)), int(round(c[3] * 255)))
    return default


def blend(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def paint(img, box, clip=None):
    node = box.node
    p = node["props"]
    mods = modifiers(node)
    d = ImageDraw.Draw(img, "RGBA")
    x0, y0, x1, y1 = box.x, box.y, box.x + box.w, box.y + box.h
    myclip = clip
    if box.clip:
        myclip = box.clip if not clip else (max(clip[0], box.clip[0]), max(clip[1], box.clip[1]), min(clip[2], box.clip[2]), min(clip[3], box.clip[3]))
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer, "RGBA")
    cls = node["class"]
    radius = 0
    cr = mods["corner"]
    if cr:
        radius = cr[2] + cr[1] * min(box.w, box.h)
        radius = min(radius, min(box.w, box.h) / 2)
    if cls not in ("ScreenGui", "Folder"):
        bt = float(p.get("BackgroundTransparency", 0) or 0)
        if bt < 1 and box.w > 0 and box.h > 0:
            bg = col(p.get("BackgroundColor3"))
            g = mods["gradient"]
            drawn = False
            if g and float(g.get("Rotation", 0) or 0) == 0 and box.w >= 8 and (
                isinstance(g.get("Color"), tuple) or isinstance(g.get("Transparency"), tuple)
            ):
                # real horizontal gradient: sample colour + transparency per column
                def sample(seq, t, default):
                    if not (isinstance(seq, tuple) and seq[0] == "Seq"):
                        return default
                    conv = lambda v: v if isinstance(v, (int, float)) else col(v)
                    kps = [(kt, conv(kv)) for kt, kv in seq[1]]
                    if t <= kps[0][0]:
                        return kps[0][1]
                    for (ta, va), (tb, vb) in zip(kps, kps[1:]):
                        if ta <= t <= tb:
                            f = 0 if tb == ta else (t - ta) / (tb - ta)
                            if isinstance(va, (int, float)):
                                return va + (vb - va) * f
                            return blend(va, vb, f)
                    return kps[-1][1]
                strip = Image.new("RGBA", (max(1, int(x1 - x0)), max(1, int(y1 - y0))), (0, 0, 0, 0))
                sd = ImageDraw.Draw(strip)
                for cx in range(strip.width):
                    t = cx / max(1, strip.width - 1)
                    c = sample(g.get("Color"), t, None)
                    cc = tuple(int(bg[i] * (c[i] if c is not None else 255) / 255) for i in range(3))
                    tv = sample(g.get("Transparency"), t, 0.0)
                    a = int(round((1 - bt) * (1 - float(tv)) * 255))
                    sd.line([cx, 0, cx, strip.height], fill=cc + (max(0, min(255, a)),))
                if radius > 0:
                    mask = Image.new("L", strip.size, 0)
                    ImageDraw.Draw(mask).rounded_rectangle([0, 0, strip.width - 1, strip.height - 1], radius=radius, fill=255)
                    strip.putalpha(Image.composite(strip.split()[3], Image.new("L", strip.size, 0), mask))
                layer.alpha_composite(strip, (int(x0), int(y0)))
                drawn = True
            elif g:
                seq = g.get("Color")
                if isinstance(seq, tuple) and seq[0] == "Seq":
                    c0, c1 = col(seq[1][0][1]), col(seq[1][-1][1])
                    bg = tuple(int(bg[i] * blend(c0, c1, 0.5)[i] / 255) for i in range(3))
                tr = g.get("Transparency")
                if isinstance(tr, tuple) and tr[0] == "Seq":
                    avg = sum(v for _, v in tr[1]) / len(tr[1])
                    bt = 1 - (1 - bt) * (1 - avg)
            if not drawn:
                alpha = int(round((1 - bt) * 255))
                ld.rounded_rectangle([x0, y0, x1 - 1, y1 - 1], radius=radius, fill=bg + (alpha,))
        st = mods["stroke"]
        if st and float(st.get("Transparency", 0) or 0) < 1 and box.w > 0 and box.h > 0:
            sc = col(st.get("Color"), (0, 0, 0))
            sa = int(round((1 - float(st.get("Transparency", 0) or 0)) * 255))
            th = float(st.get("Thickness", 1) or 1)
            ld.rounded_rectangle([x0, y0, x1 - 1, y1 - 1], radius=radius, outline=sc + (sa,), width=max(1, int(round(th))))
        if cls in ("ImageLabel", "ImageButton") and p.get("Image"):
            it = float(p.get("ImageTransparency", 0) or 0)
            if it < 1:
                ic = col(p.get("ImageColor3"))
                ld.rounded_rectangle([x0 + 2, y0 + 2, x1 - 3, y1 - 3], radius=3, outline=ic + (int((1 - it) * 200),), width=1)
                ld.line([x0 + 4, y0 + 4, x1 - 5, y1 - 5], fill=ic + (int((1 - it) * 160),))
        if cls in ("TextLabel", "TextButton", "TextBox"):
            txt = str(p.get("Text", "") or "")
            placeholder = False
            if not txt and cls == "TextBox" and p.get("PlaceholderText"):
                txt, placeholder = str(p["PlaceholderText"]), True
            tt = float(p.get("TextTransparency", 0) or 0)
            if txt and tt < 1:
                tw, th, lines, fnt = text_size_px(node, box.w)
                tc = col(p.get("PlaceholderColor3") if placeholder else p.get("TextColor3"), (0, 0, 0))
                xa = enum_name(p.get("TextXAlignment"), "Center")
                ya = enum_name(p.get("TextYAlignment"), "Center")
                lh = th / max(1, len(lines))
                total = lh * len(lines)
                if ya == "Top":
                    ty = y0
                elif ya == "Bottom":
                    ty = y1 - total
                else:
                    ty = y0 + (box.h - total) / 2
                for i, line in enumerate(lines):
                    if not p.get("TextWrapped") and enum_name(p.get("TextTruncate"), "None") == "AtEnd":
                        while line and text_width(line + "…", fnt) > box.w and len(line) > 1:
                            line = line[:-1]
                        if line != lines[i]:
                            line += "…"
                    lw = text_width(line, fnt)
                    if xa == "Left":
                        tx = x0
                    elif xa == "Right":
                        tx = x1 - lw
                    else:
                        tx = x0 + (box.w - lw) / 2
                    ld.text((tx, ty + i * lh + (lh - fnt.size) / 2 - 1), line, font=fnt, fill=tc + (int((1 - tt) * 255),))
    if myclip:
        if myclip[2] <= myclip[0] or myclip[3] <= myclip[1]:
            return
        mask = Image.new("L", img.size, 0)
        ImageDraw.Draw(mask).rectangle([myclip[0], myclip[1], myclip[2] - 1, myclip[3] - 1], fill=255)
        layer.putalpha(Image.composite(layer.getchannel("A"), Image.new("L", img.size, 0), mask))
    img.alpha_composite(layer)
    for child in sorted(box.children, key=lambda b: b.z):
        paint(img, child, myclip)


# --------------------------------------------------------------------------- main
def render(scene_path, out_path, width=1280, height=720, theme=None):
    lua = importlib.import_module("lupa.lua54")
    rt = lua.LuaRuntime(unpack_returned_tuples=True)
    os.chdir(ROOT)
    g = rt.globals()
    g["SCENE_THEME"] = theme
    root = rt.execute(f"""
        local mock = dofile('tests/roblox_mock.lua')
        MOCK = mock
        local Mova = dofile('source.lua')
        if SCENE_THEME then Mova.DefaultTheme = SCENE_THEME end
        local chunk = assert(loadfile('{scene_path}'))
        local target, after = chunk(mock, Mova)
        SCENE_AFTER = after
        for _ = 1, 30 do mock.flush() end
        return target or mock.CoreGui
    """)
    vector2 = g["Vector2"]

    def do_layout():
        tree = lua_tree(root)
        boxes = []
        if tree["class"] == "ScreenGui":
            boxes.append(layout(tree, 0, 0, width, height))
        else:
            for c in tree["children"]:
                b = layout(c, 0, 0, width, height)
                if b:
                    boxes.append(b)
        return boxes

    def feed_back(box):
        # the library's responsive code reads AbsoluteSize; the mock has no layout engine, so hand
        # the computed sizes back and let it react (two passes settle card stacking etc.)
        obj = box.node["lua"]
        try:
            obj["AbsoluteSize"] = vector2["new"](box.w, box.h)
            obj["AbsolutePosition"] = vector2["new"](box.x, box.y)
        except Exception:  # noqa: BLE001
            pass
        for c in box.children:
            feed_back(c)

    boxes = do_layout()
    for step in range(3):
        for b in boxes:
            if b:
                feed_back(b)
        rt.execute("for _ = 1, 10 do MOCK.flush() end")
        if step == 1:
            # scene actions that depend on real positions (opening popups) run once sizes are known
            rt.execute("if SCENE_AFTER then SCENE_AFTER() end for _ = 1, 10 do MOCK.flush() end")
        boxes = do_layout()
    img = Image.new("RGBA", (width, height), (40, 42, 48, 255))
    for b in boxes:
        if b:
            paint(img, b)
    img.convert("RGB").save(out_path)
    print("rendered", out_path)


if __name__ == "__main__":
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        sys.exit(1)
    kw = {}
    if "--theme" in args:
        kw["theme"] = args[args.index("--theme") + 1]
    if "--width" in args:
        kw["width"] = int(args[args.index("--width") + 1])
    if "--height" in args:
        kw["height"] = int(args[args.index("--height") + 1])
    render(args[0], args[1], **kw)
