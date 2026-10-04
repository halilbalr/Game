"""
Authoring script for Blockheim's original 16x16 item and plant sprites.

Run:  python3 tools/asset-pipeline/author_sprites.py [--preview]
Writes src/data/sprites.json. Shapes are drawn from simple primitives (lines,
filled polygons, hand-placed pixel rows) and then shaded automatically, so the
art is defined here rather than as opaque image files.

Grid characters map to palette entries; '.' is transparent. A palette value
prefixed with 't' is drawn as a grey tint mask (biome-tinted at render time).
"""
import json
import os
import sys

N = 16
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', '..', 'src', 'data', 'sprites.json')


def blank():
    return [['.'] * N for _ in range(N)]


def put(g, x, y, c):
    if 0 <= x < N and 0 <= y < N:
        g[y][x] = c


def line(g, x0, y0, x1, y1, c):
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    while True:
        put(g, x0, y0, c)
        if x0 == x1 and y0 == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def poly(g, pts, c):
    """Scanline fill of a polygon given pixel-centre vertices."""
    ys = [p[1] for p in pts]
    for y in range(min(ys), max(ys) + 1):
        xs = []
        for i in range(len(pts)):
            (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % len(pts)]
            if y0 == y1:
                continue
            if min(y0, y1) <= y < max(y0, y1) or (y == max(ys) and y == max(y0, y1)):
                xs.append(x0 + (y - y0) * (x1 - x0) / (y1 - y0))
        xs.sort()
        for i in range(0, len(xs) - 1, 2):
            for x in range(int(round(xs[i])), int(round(xs[i + 1])) + 1):
                put(g, x, y, c)
    for i in range(len(pts)):
        line(g, *pts[i], *pts[(i + 1) % len(pts)], c)


def shade(g, base, light, dark):
    """Pixels of `base` lit from the top-left: exposed up/left -> `light`,
    exposed down/right -> `dark`, exposed on both sides -> unchanged."""
    src = [row[:] for row in g]
    for y in range(N):
        for x in range(N):
            if src[y][x] != base:
                continue
            up = src[y - 1][x] if y > 0 else '.'
            left = src[y][x - 1] if x > 0 else '.'
            down = src[y + 1][x] if y < N - 1 else '.'
            right = src[y][x + 1] if x < N - 1 else '.'
            lit = up == '.' or left == '.'
            shadow = down == '.' or right == '.'
            if lit and not shadow:
                g[y][x] = light
            elif shadow and not lit:
                g[y][x] = dark


def rows(text):
    lines = [l.strip() for l in text.strip('\n').split('\n')]
    g = blank()
    top = (N - len(lines)) // 2
    left = (N - max(len(l) for l in lines)) // 2
    for j, l in enumerate(lines):
        for i, ch in enumerate(l):
            put(g, left + i, top + j, ch)
    return g


def handle(g, length=9):
    """Two-pixel diagonal stick along x + y = 15 from the bottom-left corner."""
    for t in range(length):
        put(g, 1 + t, 14 - t, 'h')
        put(g, 2 + t, 14 - t, 'H')


def pixels(g, pts, c):
    for x, y in pts:
        put(g, x, y, c)


def tool_pickaxe():
    g = blank()
    handle(g, 9)
    outer = [(2, 3), (3, 2), (4, 1), (5, 1), (6, 1), (7, 1), (8, 1), (9, 2), (10, 2), (11, 3),
             (12, 4), (13, 5), (13, 6), (14, 7), (14, 8), (14, 9), (14, 10), (14, 11), (13, 12), (12, 13)]
    mid = [(3, 3), (4, 2), (5, 2), (6, 2), (7, 2), (8, 2), (9, 3), (10, 3), (11, 4), (12, 5), (12, 6),
           (13, 7), (13, 8), (13, 9), (13, 10), (13, 11), (12, 12)]
    inner = [(2, 4), (5, 3), (6, 3), (7, 3), (8, 3), (9, 4), (10, 4), (11, 5), (11, 6), (12, 7),
             (12, 8), (12, 9), (12, 10), (11, 13)]
    pixels(g, outer, 'm')
    pixels(g, mid, 'M')
    pixels(g, inner, 'd')
    return g


def tool_axe():
    g = blank()
    handle(g, 11)
    blade = {1: (6, 9), 2: (5, 10), 3: (4, 10), 4: (4, 9), 5: (5, 8), 6: (6, 7)}
    for y, (a, b) in blade.items():
        for x in range(a, b + 1):
            put(g, x, y, 'M')
    shade(g, 'M', 'm', 'd')
    return g


def tool_shovel():
    g = blank()
    handle(g, 9)
    head = {1: (12, 13), 2: (10, 14), 3: (9, 14), 4: (9, 13), 5: (9, 12), 6: (10, 11)}
    for y, (a, b) in head.items():
        for x in range(a, b + 1):
            put(g, x, y, 'M')
    shade(g, 'M', 'm', 'd')
    return g


def tool_hoe():
    g = blank()
    handle(g, 12)
    for x in range(5, 12):
        put(g, x, 2, 'M')
    pixels(g, [(5, 3), (6, 3), (5, 4)], 'M')
    for x in range(6, 12):
        put(g, x, 1, 'm')
    pixels(g, [(6, 3), (5, 4)], 'd')
    return g


def tool_sword():
    g = blank()
    # Blade along the anti-diagonal x + y = 15, three pixels thick.
    for y in range(1, 10):
        put(g, 14 - y, y, 'm')
        put(g, 15 - y, y, 'M')
        put(g, 16 - y, y, 'd')
    put(g, 15, 0, 'm')
    # Cross-guard perpendicular to the blade.
    for t in range(5):
        put(g, 3 + t, 8 + t, 'd')
    pixels(g, [(4, 11), (3, 12), (2, 13)], 'h')
    pixels(g, [(5, 11), (4, 12), (3, 13)], 'H')
    pixels(g, [(1, 14), (2, 14), (1, 13)], 'd')
    return g


SPRITES = {}
PALETTES = {}


def add(name, grid, palette):
    SPRITES[name] = [''.join(r) for r in grid]
    PALETTES[name] = palette


TOOL_PAL = {'h': '#a0784a', 'H': '#5e4426'}
for t, fn in [('pickaxe', tool_pickaxe), ('axe', tool_axe), ('shovel', tool_shovel), ('hoe', tool_hoe), ('sword', tool_sword)]:
    add('tool_' + t, fn(), TOOL_PAL)

g = blank()
for t in range(10):
    put(g, 3 + t, 12 - t, 'a')
    put(g, 4 + t, 12 - t, 'b')
add('stick', g, {'a': '#a0784a', 'b': '#5e4426'})

add('coal', rows('''
....kkk.....
..kkKKkkk...
.kKKkkkKkk..
.kkkkkkkKk..
kkKkkkKkkkk.
kkkkkkkkKkk.
.kkKkkkkkk..
.kkkkKkkkk..
..kkkkkkk...
....kkkk....
'''), {'k': '#2b2b2b', 'K': '#4a4a4a'})

def ingot(light, mid, dark):
    return rows("""
......mmmmmm..
....mmMMMMMMd.
..mmMMMMMMMMd.
.mMMMMMMMMMd..
.dMMMMMMMMd...
..dddddddd....
"""), {'m': light, 'M': mid, 'd': dark}

add('ingot_iron', *ingot('#f2f2f2', '#c9c9c9', '#7d7d7d'))
add('ingot_gold', *ingot('#fff59a', '#f1c533', '#a87d12'))
add('brick', *ingot('#d98a6a', '#b0553a', '#6e2e1e'))

add('diamond', rows('''
...dddddd...
..dmmMMMMd..
.dmmMMMMMMd.
dMMMMMMMMMMd
.dMMMMMMMMd.
..dMMMMMMd..
...dMMMMd...
....dMMd....
.....dd.....
'''), {'d': '#0f6b66', 'M': '#3fd4c6', 'm': '#c8fff8'})

add('apple', rows('''
......s.....
......s.gg..
...rrrsrgg..
..rhhrrrrrr.
.rhhrrrrrrrr
.rhrrrrrrrRr
.rrrrrrrrrRr
.rrrrrrrrRRr
.RrrrrrrrRR.
..RrrrrrRR..
...RRRRRR...
'''), {'r': '#d42a2a', 'R': '#931717', 'h': '#ff8a7a', 's': '#5a3a1a', 'g': '#4fae3f'})

add('bread', rows('''
....bbbbbb....
..bbBBbBBbbb..
.bBBbBBbBBbBb.
bbbbbbbbbbbbbb
bccccccccccccb
.bccccccccccb.
..bbbbbbbbbb..
'''), {'b': '#b9802f', 'B': '#e1b25a', 'c': '#8a5a1f'})

def meat(pal):
    return rows('''
.....pppp...
...ppPPPpp..
..pPPPPPPpp.
.pPPPfPPPPp.
.pPPPPPPfPp.
.pPfPPPPPPp.
..pPPPPPPp..
...ppPPPp...
....wppp....
...ww.......
..ww........
'''), pal

add('porkchop_raw', *meat({'p': '#c75a5a', 'P': '#f29a9a', 'f': '#ffd4d4', 'w': '#eeeeee'}))
add('porkchop_cooked', *meat({'p': '#6b3a1a', 'P': '#b0703a', 'f': '#d9a26a', 'w': '#e6dccb'}))

def steak(pal):
    return rows('''
...rrrrrr...
.rrRRRRRRrr.
rRRfRRRRRRRr
rRRRRRfRRRRr
rRRRRRRRRfRr
rRfRRRRRRRRr
.rRRRRRRRRr.
..rrrrrrrr..
'''), pal

add('beef_raw', *steak({'r': '#8e1f1f', 'R': '#d64545', 'f': '#f3c4c4'}))
add('beef_cooked', *steak({'r': '#4a2410', 'R': '#8a4b22', 'f': '#b9814d'}))

def drumstick(pal):
    return rows('''
....cccc....
...cCCCCc...
..cCCCCCCc..
..cCCCCCCc..
..cCCCCCCc..
...cCCCCc...
....cCCc....
.....bb.....
....bbbb....
....b..b....
'''), pal

add('chicken_raw', *drumstick({'c': '#d9a3a3', 'C': '#f5d0c8', 'b': '#eeeeee'}))
add('chicken_cooked', *drumstick({'c': '#7a4a1e', 'C': '#c98a4a', 'b': '#e6dccb'}))

add('rotten_flesh', rows('''
....gggg....
..ggGGrgg...
.gGrGGGGgg..
.gGGGGrGGg..
gGGrGGGGGGg.
gGGGGGGrGGg.
.ggGGGGGgg..
...gggggg...
'''), {'g': '#5e6b2a', 'G': '#8a9a3e', 'r': '#7a2e2e'})

add('leather', rows('''
..ll....ll..
.lLLllllLLl.
.lLLLLLLLLl.
..lLLLLLLl..
..lLLLLLLl..
.lLLLLLLLLl.
.lLLllllLLl.
..ll....ll..
'''), {'l': '#6e3d1c', 'L': '#a3622c'})

g = blank()
line(g, 3, 13, 12, 2, 's')
for t in range(8):
    put(g, 5 + t, 9 - t, 'f')
    put(g, 6 + t, 10 - t, 'f')
    put(g, 4 + t, 8 - t, 'F')
add('feather', g, {'s': '#bdbdbd', 'f': '#ffffff', 'F': '#e6e6e6'})

add('clay_ball', rows('''
...cccc...
.ccCCCCcc.
.cCCCCCCc.
cCCCCCCCCc
cCCCCCCCCc
.cCCCCCCc.
.ccCCCCcc.
...cccc...
'''), {'c': '#7d8494', 'C': '#a7aebc'})

def bucket(fill):
    pal = {'o': '#3a3a3a', 'i': '#d6d6d6', 'I': '#a6a6a6', 'w': fill or '#3a3a3a'}
    return rows('''
.oooooooooo.
o' + ('wwwwwwwwww' if fill else 'oooooooooo') + 'o
oiwwwwwwwwIo
.oiiiiiiiIo.
.oiiiiiiiIo.
..oiiiiiIo..
..oiiiiiIo..
...oooooo...
'''.replace("' + ('wwwwwwwwww' if fill else 'oooooooooo') + '", 'wwwwwwwwww' if fill else 'oooooooooo')), pal

add('bucket', *bucket(None))
add('bucket_water', *bucket('#3a63d8'))
add('bucket_lava', *bucket('#e86a12'))

add('bed', rows('''
..............
.ww...........
.wwPPrrrrrrrr.
.wwPPrrrrrrrr.
.wwRRRRRRRRRRw
.wwbbbbbbbbbbw
.w..........w.
'''), {'w': '#9c7a46', 'b': '#6b522c', 'r': '#c53030', 'R': '#8e1c1c', 'P': '#f4f4f4'})

g = blank()
pts = [(2, 12), (4, 10), (5, 11), (7, 8), (8, 9), (10, 6), (11, 7), (13, 3)]
for i in range(len(pts) - 1):
    line(g, *pts[i], *pts[i + 1], 's')
add('string', g, {'s': '#f0f0f0'})

g = blank()
line(g, 4, 11, 11, 4, 'b')
line(g, 5, 11, 11, 5, 'B')
for p in [(3, 11), (4, 12), (3, 12), (11, 3), (12, 4), (12, 3)]:
    put(g, *p, 'b')
add('bone', g, {'b': '#f2efe6', 'B': '#cfc9b8'})

add('pumpkin_pie', rows('''
....cccccc....
..ccPPPPPPcc..
.cPPPPPPPPPPc.
cPPPPPPPPPPPPc
cccccccccccccc
.cCCCCCCCCCCc.
..cccccccccc..
'''), {'c': '#b9802f', 'P': '#e48a2b', 'C': '#8a5a1f'})

add('seeds', rows('''
..s.....s..
.sS..s.....
.....sS..s.
..s.......S
.sS...s....
......sS...
...s.......
..sS....s..
.........S.
'''), {'s': '#5fa83a', 'S': '#3b7a22'})

add('wheat', rows('''
.....y.y.y..
....yYyYyY..
.....yYyY...
......gYg...
......g.g...
.....g.g....
.....gg.....
....gg......
...gg.......
..gg........
'''), {'y': '#e2c25a', 'Y': '#b8952e', 'g': '#9a8a3a'})

# ---- plants (block textures drawn as cross quads) ----
add('tall_grass', rows('''
................
.......g........
..g....g....g...
..g...gG...g....
...g..gG..gG....
...gG.g...g..g..
.g..g.gG.gG.gG..
.gG.gG.g.g..g...
..g..g.gGg.gG.g.
..gG.gGgg.gG.gG.
...g..gGg.g..g..
...gG.ggGgG.gG..
....g.gGggg.g...
....gGgGgGggG...
.....gggggggg...
................
'''), {'g': 't#a8a8a8', 'G': 't#888888'})

add('yellow_flower', rows('''
................
................
................
................
......yy........
.....yYYy.......
.....yYOYy......
......yYy.......
.......g........
.......g..gg....
.......g.gg.....
.....gGg........
....gg.g........
.......g........
.......g........
................
'''), {'y': '#ffe14d', 'Y': '#ffd000', 'O': '#e69a00', 'g': '#4f9a2a', 'G': '#3b7a1e'})

add('red_flower', rows('''
................
................
................
.......rr.......
.....rrRRr......
....rRRkRRr.....
....rRkkkRr.....
.....rRRRr......
......rrr.......
.......g........
.......g.gg.....
.....ggg.g......
....gg.g........
.......g........
.......g........
................
'''), {'r': '#e02525', 'R': '#b81414', 'k': '#2a1a0a', 'g': '#4f9a2a'})

add('dead_bush', rows('''
................
................
..b........b....
...b..b...b.....
...b...b.b..b...
....b..b.b.b....
.b...b.bbb.b....
..b...bbbbb...b.
...b...bbb...b..
....bb.bbb..b...
......bbbbbb....
.......bbb......
.......bb.......
.......b........
.......b........
................
'''), {'b': '#8a5e2a'})

def sapling(leaf, leaf2):
    return rows('''
................
................
......ll........
....llLll.......
...lLLllLl......
...lLlLLlll.....
....lllLlLl.....
.....lLllL......
......llt.......
.......t........
.......t........
......tt........
.......t........
.......t........
.......t........
................
'''), {'l': leaf, 'L': leaf2, 't': '#6b4a26'}

add('oak_sapling', *sapling('#4a9a2e', '#2f6e1c'))
add('birch_sapling', *sapling('#7fbf4a', '#5a9a32'))
add('spruce_sapling', *sapling('#2e5e3a', '#1e4228'))

add('torch', rows('''
................
................
................
................
................
................
.......yy.......
.......YO.......
.......ww.......
.......ww.......
.......ww.......
.......ww.......
.......ww.......
.......ww.......
.......ww.......
.......ww.......
'''), {'y': '#fff3a0', 'Y': '#ffd23a', 'O': '#ff8a00', 'w': '#8a6436'})

STALKS = [(1, 0), (4, 1), (6, -1), (9, 0), (11, 1), (14, -1)]
for stage in range(8):
    g = blank()
    height = 2 + stage * 12 // 7
    for col, jitter in STALKS:
        top = max(1, 15 - height + jitter)
        for y in range(top, 16):
            put(g, col, y, 'g')
        if stage >= 2:
            put(g, col + 1, min(15, top + 3), 'G')
        if stage >= 4:
            put(g, col - 1, min(15, top + 5), 'G')
        if stage >= 6:
            for y in range(top, top + 3):
                put(g, col, y, 'y')
            put(g, col + 1, top + 1, 'Y')
            if stage == 7:
                put(g, col - 1, top, 'Y')
    pal = {'g': ['#3f9a2a', '#3f9a2a', '#4f9f2c', '#5aa52e', '#7aa62f', '#9aa233', '#b8a03a', '#cfa94a'][stage],
           'G': ['#2f7a1e', '#2f7a1e', '#3a8420', '#468a24', '#5f8a26', '#7d8a2a', '#98862e', '#a8862a'][stage],
           'y': '#e2c25a', 'Y': '#b8952e'}
    add('wheat_%d' % stage, g, pal)

# ---- overlays used by block painters ----
add('overlay_crafting_front', rows('''
................
................
..hhhhh..ss.....
..hHHHh..ss.....
....H....ss.....
....H....ss.....
....H...ssss....
....H...ssss....
................
................
'''), {'h': '#6b6b6b', 'H': '#5e4426', 's': '#9a9a9a'})

add('overlay_furnace_mouth', rows('''
..........
.dddddddd.
.dkkkkkkd.
.dkkkkkkd.
.dkkkkkkd.
.dddddddd.
'''), {'d': '#3a3a3a', 'k': '#111111'})

add('overlay_furnace_mouth_lit', rows('''
..........
.dddddddd.
.dkyOykkd.
.dyOROyOd.
.dORRRORd.
.dddddddd.
'''), {'d': '#3a3a3a', 'k': '#2a1508', 'y': '#ffe066', 'O': '#ff9a1a', 'R': '#e8380a'})

add('overlay_chest_latch', rows('''
..mm..
.mMMm.
.mkkm.
..mm..
'''), {'m': '#c8c8c8', 'M': '#ffffff', 'k': '#3a3a3a'})


def preview():
    for name, grid in SPRITES.items():
        print(name)
        for r in grid:
            print('   ' + r)


if __name__ == '__main__':
    for name, grid in SPRITES.items():
        assert len(grid) == N and all(len(r) == N for r in grid), name
        used = set(''.join(grid)) - {'.'}
        allowed = set(PALETTES[name]) | ({'m', 'M', 'd'} if name.startswith('tool_') else set())
        missing = used - allowed
        assert not missing, (name, missing)
    if '--preview' in sys.argv:
        preview()
    with open(OUT, 'w') as f:
        json.dump({'size': N, 'sprites': {k: {'rows': v, 'palette': PALETTES[k]} for k, v in SPRITES.items()},
                   'toolPalettes': {
                       'wood': {'m': '#c49a5c', 'M': '#9c7a46', 'd': '#5e4426'},
                       'stone': {'m': '#b4b4b4', 'M': '#8a8a8a', 'd': '#555555'},
                       'iron': {'m': '#ffffff', 'M': '#d0d0d0', 'd': '#8c8c8c'},
                       'gold': {'m': '#fff59a', 'M': '#f1c533', 'd': '#a87d12'},
                       'diamond': {'m': '#c8fff8', 'M': '#3fd4c6', 'd': '#127a72'},
                   }}, f, indent=1)
    print('wrote', len(SPRITES), 'sprites to', os.path.relpath(OUT))
