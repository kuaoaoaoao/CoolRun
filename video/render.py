# -*- coding: utf-8 -*-
"""CoolRun 产品介绍短片 —— 纯代码逐帧渲染 (Pillow + numpy) -> ffmpeg"""
import os, sys, math, time, subprocess
import numpy as np
from PIL import Image, ImageDraw, ImageFont

W, H = 1920, 1080
SS   = 1.5
CW, CH = int(W*SS), int(H*SS)
FPS  = 30
DUR  = 30.0
NF   = int(round(DUR*FPS))
OUT  = '/tmp/coolrun_video/coolrun_intro.mp4'

# ---------------- color ----------------
def C(h):
    h = h.lstrip('#'); return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))
def mix(a, b, t):
    t = 0.0 if t < 0 else (1.0 if t > 1 else t)
    return tuple(int(round(a[i] + (b[i]-a[i])*t)) for i in range(3))
def A(col, a):
    a = 0.0 if a < 0 else (1.0 if a > 1 else a)
    return (col[0], col[1], col[2], int(round(255*a)))

BG0, BG1 = C('07080d'), C('12172a')
ACCENT   = C('7a99ff')
ACCENT2  = C('4fe0c0')
GOLD     = C('e0a544')
UP, DOWN = C('f25c5c'), C('2ec26a')
WARN     = C('f2a626')
WHITE    = (255, 255, 255)
GRAY     = C('8f96ad')
DIM      = C('5c6377')

# ---------------- easing ----------------
def cl(x): return 0.0 if x < 0 else (1.0 if x > 1 else x)
def seg(t, a, b):
    if b <= a: return 1.0 if t >= b else 0.0
    return cl((t-a)/(b-a))
def eo(x):  x = cl(x); return 1-(1-x)**3
def eo5(x): x = cl(x); return 1-(1-x)**5
def eio(x):
    x = cl(x)
    return 4*x*x*x if x < 0.5 else 1-((-2*x+2)**3)/2
def back(x):
    x = cl(x); c = 1.9
    return 1+(c+1)*(x-1)**3+c*(x-1)**2

# ---------------- fonts ----------------
FP_CJK  = '/System/Library/Fonts/Hiragino Sans GB.ttc'
FP_SF   = '/System/Library/Fonts/SFNS.ttf'
FP_MONO = '/System/Library/Fonts/SFNSMono.ttf'
_fc = {}
def F(kind, size):
    sz = max(6, int(round(size*SS)))
    k = (kind, sz)
    if k in _fc: return _fc[k]
    if   kind == 'cn':  f = ImageFont.truetype(FP_CJK, sz, index=0)
    elif kind == 'cnb': f = ImageFont.truetype(FP_CJK, sz, index=2)
    elif kind == 'mono':f = ImageFont.truetype(FP_MONO, sz)
    else:
        f = ImageFont.truetype(FP_SF, sz)
        try:
            f.set_variation_by_name({'sf':'Regular','sfm':'Medium','sfb':'Semibold',
                                     'sfbb':'Bold','sfh':'Heavy'}.get(kind,'Regular'))
        except Exception: pass
    _fc[k] = f; return f
def vw(s, font): return font.getlength(s)/SS      # visible width in 1x units

# ---------------- draw wrapper ----------------
class D:
    def __init__(self, img, ox=0.0, oy=0.0):
        self.img = img; self.d = ImageDraw.Draw(img, 'RGBA'); self.ox = ox; self.oy = oy
    def _p(self, x, y): return ((x+self.ox)*SS, (y+self.oy)*SS)
    def _b(self, box): return [*( (box[0]+self.ox)*SS, (box[1]+self.oy)*SS),
                               ((box[2]+self.ox)*SS), ((box[3]+self.oy)*SS)]
    def rr(self, box, r=0, fill=None, outline=None, width=1):
        x0, y0, x1, y1 = self._b(box)
        if x1-x0 < 0.5 or y1-y0 < 0.5: return
        r = max(0.0, min(r*SS, (x1-x0)/2, (y1-y0)/2))
        wk = None if outline is None else max(1, int(round(width*SS)))
        if fill is None and outline is None: return
        self.d.rounded_rectangle([x0, y0, x1, y1], radius=r, fill=fill,
                                 outline=outline, width=wk or 1)
    def rect(self, box, fill):
        x0, y0, x1, y1 = self._b(box); self.d.rectangle([x0, y0, x1, y1], fill=fill)
    def ell(self, box, fill=None, outline=None, width=1):
        x0, y0, x1, y1 = self._b(box)
        wk = None if outline is None else max(1, int(round(width*SS)))
        self.d.ellipse([x0, y0, x1, y1], fill=fill, outline=outline, width=wk or 1)
    def line(self, pts, fill, width=1.0):
        pp = [self._p(x, y) for x, y in pts]
        self.d.line(pp, fill=fill, width=max(1, int(round(width*SS))), joint='curve')
    def poly(self, pts, fill):
        self.d.polygon([self._p(x, y) for x, y in pts], fill=fill)
    def txt(self, xy, s, font, fill, anchor='la'):
        x, y = self._p(xy[0], xy[1])
        self.d.text((x, y), s, font=font, fill=fill, anchor=anchor)
    # text helpers -------------------------------------------------
    def tcenter(self, cx, cy, s, font, fill, ls=0.0):
        if ls:
            tot = sum(vw(c, font) for c in s)+ls*(len(s)-1)
            x = cx-tot/2
            for ch in s:
                self.txt((x, cy), ch, font, fill, anchor='lm'); x += vw(ch, font)+ls
        else:
            self.txt((cx, cy), s, font, fill, anchor='mm')
    def tw(self, s, font): return vw(s, font)
def wrap(s, font, maxw):
    out, cur = [], ''
    for ch in s:
        if ch == '\n':
            out.append(cur); cur = ''; continue
        if vw(cur+ch, font) > maxw and cur:
            out.append(cur); cur = ch
        else:
            cur += ch
    if cur: out.append(cur)
    return out
def ml(d, xy, s, font, fill, lh, maxw=None):
    ls = [s] if maxw is None else wrap(s, font, maxw)
    y = xy[1]
    for L in ls:
        d.txt((xy[0], y), L, font, fill); y += lh
    return y

# ---------------- background ----------------
def make_bg():
    yy, xx = np.mgrid[0:CH, 0:CW].astype(np.float32)
    nx, ny = xx/CW, yy/CH
    img = np.zeros((CH, CW, 3), np.float32)
    g = ny**1.1
    for i in range(3):
        img[..., i] = BG0[i]+(BG1[i]-BG0[i])*g
    for cx, cy, r, col, amp in [(0.70, 0.16, 0.62, ACCENT, 0.115),
                                (0.22, 0.88, 0.66, ACCENT2, 0.055),
                                (0.02, 0.06, 0.55, ACCENT, 0.05),
                                (0.55, 0.95, 0.45, GOLD, 0.030)]:
        f = np.exp(-(((nx-cx)**2+(ny-cy)**2)/(r*r))*2.3)[..., None]
        img += f*np.array(col, np.float32)*amp
    step = int(48*SS)
    gd = np.zeros((CH, CW), np.float32)
    gd[:, ::step] = 1.0; gd[::step, :] = 1.0
    img += gd[..., None]*np.array([255, 255, 255], np.float32)*0.016
    r2 = ((nx-0.5)**2*1.05+(ny-0.5)**2*1.25)
    img *= (1-np.clip(r2*1.25, 0, 1)[..., None]*0.62)
    rng = np.random.default_rng(7)
    img += rng.normal(0, 1.5, (CH, CW, 1)).astype(np.float32)
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), 'RGB')

BG = make_bg()

# ---------------- layout ----------------
MB_H = 46
PX, PY, PW, PH = 1272, 64, 448, 720
CR = (66, 16, 430, 704)          # content rect (panel-local)
RAIL_X, RAIL_IW, RAIL_IH, RAIL_GAP = 8, 44, 44, 10
RAIL_TOP = (PH-(10*RAIL_IH+9*RAIL_GAP))/2

MODS = [('sun','今天',ACCENT), ('bars','监控',ACCENT2), ('trend','金价',GOLD),
        ('cal','日历',ACCENT), ('abc','背单词',ACCENT2), ('spark','额度',ACCENT),
        ('note','笔记',GOLD), ('clip','剪贴板',ACCENT2), ('cross','诊断',ACCENT),
        ('brain','AI',ACCENT2)]

def icon(d, kind, cx, cy, s, col, a=1.0):
    """vector-ish glyph, s = half-size"""
    f = A(col, a)
    if kind == 'sun':
        d.ell([cx-s*0.42, cy-s*0.42, cx+s*0.42, cy+s*0.42], fill=f)
        for k in range(8):
            ang = k*math.pi/4
            d.line([(cx+math.cos(ang)*s*0.66, cy+math.sin(ang)*s*0.66),
                    (cx+math.cos(ang)*s*0.95, cy+math.sin(ang)*s*0.95)], f, 1.6)
    elif kind == 'bars':
        for i, hh in enumerate([0.45, 0.85, 0.62]):
            x = cx-s*0.8+i*s*0.62
            d.rr([x, cy+s-hh*s*1.9, x+s*0.36, cy+s], s*0.18, fill=f)
    elif kind == 'trend':
        d.line([(cx-s*0.95, cy+s*0.6), (cx-s*0.3, cy-s*0.1),
                (cx+s*0.15, cy+s*0.25), (cx+s*0.95, cy-s*0.72)], f, 1.9)
        d.ell([cx+s*0.72, cy-s*0.95, cx+s*1.12, cy-s*0.55], fill=f)
    elif kind == 'cal':
        d.rr([cx-s*0.85, cy-s*0.7, cx+s*0.85, cy+s*0.9], s*0.22, outline=f, width=1.6)
        d.line([(cx-s*0.85, cy-s*0.18), (cx+s*0.85, cy-s*0.18)], f, 1.4)
        for i in range(2):
            for j in range(2):
                d.ell([cx-s*0.5+i*s*0.62, cy+s*0.12+j*s*0.45,
                       cx-s*0.2+i*s*0.62, cy+s*0.42+j*s*0.45], fill=f)
    elif kind == 'abc':
        ft = F('sfbb', max(8, s*1.9))
        d.txt((cx, cy), 'A', ft, f, anchor='mm')
    elif kind == 'spark':
        pts = []
        for k in range(8):
            ang = k*math.pi/4-math.pi/2
            r = s*0.95 if k % 2 == 0 else s*0.28
            pts.append((cx+math.cos(ang)*r, cy+math.sin(ang)*r))
        d.poly(pts, f)
    elif kind == 'note':
        d.rr([cx-s*0.8, cy-s*0.9, cx+s*0.8, cy+s*0.9], s*0.25, outline=f, width=1.6)
        for i in range(3):
            d.line([(cx-s*0.45, cy-s*0.35+i*s*0.42),
                    (cx+s*0.45-(s*0.3 if i == 2 else 0), cy-s*0.35+i*s*0.42)], f, 1.4)
    elif kind == 'clip':
        d.rr([cx-s*0.75, cy-s*0.75, cx+s*0.75, cy+s*0.9], s*0.22, outline=f, width=1.6)
        d.rr([cx-s*0.32, cy-s*1.0, cx+s*0.32, cy-s*0.6], s*0.14, fill=f)
    elif kind == 'cross':
        d.ell([cx-s*0.9, cy-s*0.9, cx+s*0.9, cy+s*0.9], outline=f, width=1.6)
        d.line([(cx-s*0.4, cy), (cx+s*0.4, cy)], f, 1.6)
        d.line([(cx, cy-s*0.4), (cx, cy+s*0.4)], f, 1.6)
    elif kind == 'brain':
        d.rr([cx-s*0.95, cy-s*0.8, cx+s*0.95, cy+s*0.62], s*0.4, outline=f, width=1.6)
        d.poly([(cx-s*0.3, cy+s*0.55), (cx+s*0.05, cy+s*0.55), (cx-s*0.32, cy+s*1.0)], f)
        for i in range(3):
            d.ell([cx-s*0.42+i*s*0.42, cy-s*0.18, cx-s*0.18+i*s*0.42, cy+s*0.06], fill=f)

# ---------------- panel contents ----------------
def c_today(d, t, a, ts):
    x0, y0, x1, y1 = CR; w = x1-x0
    d.txt((x0, y0+8), '今天', F('cnb', 21), A(WHITE, 0.95*a))
    d.txt((x0, y0+38), '11月11日 · 下班前要看的几件事', F('cn', 12), A(GRAY, 0.9*a))
    rows = [('金价', '积存金 ¥1,082.45', '涨 1.24%', UP),
            ('系统', 'CPU 42% · 温度 71°C', '正常', DOWN),
            ('学习', '待复习 12 个词', '5 分钟', ACCENT2)]
    y = y0+78
    for i, (k, v, tag, col) in enumerate(rows):
        ra  = a*eo(seg(t, ts+0.10+i*0.14, ts+0.70+i*0.14))
        sl  = (1-ra)*16
        d.rr([x0, y+sl, x1, y+58+sl], 13, fill=A(WHITE, 0.055*ra))
        d.rr([x0+15, y+23+sl, x0+19, y+35+sl], 2, fill=A(col, 0.95*ra))
        d.txt((x0+32, y+12+sl), k, F('cnb', 14), A(WHITE, 0.92*ra))
        d.txt((x0+32, y+34+sl), v, F('cn', 11.5), A(GRAY, 0.95*ra))
        d.txt((x1-15, y+29+sl), tag, F('cnb', 12), A(col, 0.95*ra), anchor='rm')
        y += 70
    ra = a*eo(seg(t, ts+0.62, ts+1.15))
    d.rr([x0, y0+330, x1, y0+420], 13, fill=A(ACCENT, 0.075*ra),
         outline=A(ACCENT, 0.20*ra), width=1)
    d.txt((x0+18, y0+348), '⌘ 0–9', F('sfb', 15), A(ACCENT, 0.95*ra))
    d.txt((x0+18, y0+376), '直接跳到对应模块，不用点。', F('cn', 12), A(WHITE, 0.62*ra))
    d.txt((x0+18, y0+472), '十个模块 · 全部本地存储', F('cn', 11.5), A(DIM, a))

def c_monitor(d, t, a, ts):
    x0, y0, x1, y1 = CR; w = x1-x0
    d.txt((x0, y0+8), '系统监控', F('cnb', 21), A(WHITE, 0.95*a))
    pr = eo(seg(t, ts+0.05, ts+0.5))
    d.ell([x0+88, y0+18, x0+96, y0+26], fill=A(DOWN, 0.9*a*pr))
    d.txt((x0+102, y0+14), '实时', F('cn', 11), A(DOWN, 0.85*a*pr))
    mets = [('CPU', 0.42, '42%', C('33c76a')), ('内存', 0.68, '68%', WARN),
            ('磁盘', 0.71, '71%', WARN), ('温度', 0.48, '71°C', C('33c76a'))]
    y = y0+62
    for i, (name, frac, val, col) in enumerate(mets):
        ra = a*eo(seg(t, ts+0.12+i*0.11, ts+0.62+i*0.11))
        pf = eo(seg(t, ts+0.30+i*0.11, ts+1.25+i*0.11))
        d.txt((x0, y+sl_dummy(0)), name, F('cn', 12.5), A(GRAY, 0.95*ra))
        d.txt((x1, y), val, F('sfb', 13), A(WHITE, 0.92*ra), anchor='rm')
        d.rr([x0, y+22, x1, y+28], 3, fill=A(WHITE, 0.10*ra))
        bw = max(2.0, (w)*frac*ra*pf)
        d.rr([x0, y+22, x0+bw, y+28], 3, fill=A(col, 0.92*ra))
        y += 58
    d.txt((x0, y0+330), '进程 TOP 3', F('cnb', 12.5), A(GRAY, 0.95*a))
    procs = [('Google Chrome', '38.2%', '1.2 GB'), ('Xcode', '21.4%', '980 MB'),
             ('WindowServer', '9.8%', '410 MB')]
    y = y0+358
    for i, (n, c, m) in enumerate(procs):
        ra = a*eo(seg(t, ts+0.55+i*0.12, ts+1.05+i*0.12))
        d.rr([x0, y, x1, y+46], 10, fill=A(WHITE, 0.04*ra))
        d.txt((x0+14, y+10), n, F('cn', 12), A(WHITE, 0.85*ra))
        d.txt((x0+14, y+26), m, F('cn', 10.5), A(DIM, 0.95*ra))
        d.txt((x1-14, y+18), c, F('sfm', 12), A(ACCENT2, 0.9*ra), anchor='rm')
        y += 52
def sl_dummy(v): return v

def c_gold(d, t, a, ts):
    x0, y0, x1, y1 = CR; w = x1-x0
    d.txt((x0, y0+8), '金价 · 积存金', F('cnb', 21), A(WHITE, 0.95*a))
    d.txt((x0, y0+38), '中国银行 · 实时', F('cn', 11.5), A(GRAY, 0.85*a))
    p = eo5(seg(t, ts+0.10, ts+1.35))
    val = 1064.0+(1082.45-1064.0)*p
    d.txt((x0, y0+72), '¥', F('cn', 20), A(WHITE, 0.6*a))
    d.txt((x0+22, y0+62), f'{val:,.2f}', F('sfb', 40), A(WHITE, 0.97*a))
    ca = eo(seg(t, ts+0.95, ts+1.35))
    d.rr([x0, y0+126, x0+92, y0+152], 13, fill=A(UP, 0.16*ca*a))
    d.txt((x0+46, y0+139), '+1.24%', F('sfb', 13), A(UP, 0.98*ca*a), anchor='mm')
    d.txt((x0+104, y0+139), '+¥13.42', F('cnb', 12), A(UP, 0.85*ca*a), anchor='lm')
    # sparkline
    rng = np.random.default_rng(11)
    n = 44
    base = []
    for i in range(n):
        base.append(1060+22*eio(i/(n-1))+rng.normal(0, 2.4))
    lo, hi = min(base)-2, max(base)+2
    cx0, cy0, cx1, cy1 = x0+2, y0+186, x1-2, y0+352
    def pt(i, v):
        return (cx0+(cx1-cx0)*i/(n-1), cy1-(cy1-cy0)*(v-lo)/(hi-lo))
    k = max(2, int(n*eo(seg(t, ts+0.25, ts+1.85))))
    pa_ = a
    pts = [pt(i, base[i]) for i in range(k)]
    if k > 2:
        d.poly(pts+[(pts[-1][0], cy1), (pts[0][0], cy1)], A(GOLD, 0.10*pa_))
        d.line(pts, A(GOLD, 0.95*pa_), 2.0)
        lx, ly = pts[-1]
        d.ell([lx-7, ly-7, lx+7, ly+7], fill=A(GOLD, 0.16*pa_))
        d.ell([lx-3.2, ly-3.2, lx+3.2, ly+3.2], fill=A(WHITE, 0.95*pa_))
    chips = [('MA5', '1,069.2'), ('RSI', '58'), ('信号', '偏强')]
    y = y0+392
    for i, (k2, v2) in enumerate(chips):
        ra = a*eo(seg(t, ts+0.85+i*0.12, ts+1.25+i*0.12))
        bw2 = 108
        bx = x0+i*(bw2+8)
        d.rr([bx, y, bx+bw2, y+46], 10, fill=A(WHITE, 0.045*ra))
        d.txt((bx+10, y+8), k2, F('cn', 10.5), A(DIM, 0.95*ra))
        d.txt((bx+10, y+23), v2, F('sfm', 13), A(WHITE, 0.9*ra))
    note_a = a*eo(seg(t, ts+1.15, ts+1.55))
    d.txt((x0, y0+466), '涨红跌绿，按中国市场习惯着色。', F('cn', 11.5), A(DIM, note_a))

def c_chat(d, t, a, ts):
    x0, y0, x1, y1 = CR; w = x1-x0
    d.txt((x0, y0+8), 'AI 助手', F('cnb', 21), A(WHITE, 0.95*a))
    d.txt((x0, y0+38), '读得懂本机数据 · 可接入自己的模型', F('cn', 11.5), A(GRAY, 0.85*a))
    talk = [('user', '今天金价怎么样？'),
            ('ai', '积存金 ¥1,082.45，涨 1.24%。MACD 金叉，短线偏强，但已接近上轨。'),
            ('user', '那是谁在吃 CPU？'),
            ('ai', 'Google Chrome 占 38.2%，主要是前台标签页；Xcode 21.4%。')]
    y = y0+76
    for i, (who, s) in enumerate(talk):
        ra = a*eo(seg(t, ts+0.15+i*0.26, ts+0.75+i*0.26))
        sl = (1-ra)*14
        fnt = F('cn', 12)
        maxw = w*0.70
        lines = wrap(s, fnt, maxw-28)
        bh = len(lines)*19+22
        bw2 = max(vw(L, fnt) for L in lines)+28
        bw2 = min(bw2, maxw)
        if who == 'user':
            bx1 = x1; bx0 = x1-bw2; fill = A(ACCENT, 0.20*ra); tcol = A(WHITE, 0.95*ra)
        else:
            bx0 = x0; bx1 = x0+bw2; fill = A(WHITE, 0.06*ra); tcol = A(WHITE, 0.88*ra)
        d.rr([bx0, y+sl, bx1, y+bh+sl], 12, fill=fill)
        yy = y+11+sl
        for L in lines:
            d.txt((bx0+14, yy), L, fnt, tcol); yy += 19
        y += bh+12
    # typing dots / follow-up
    ra = a*eo(seg(t, ts+1.25, ts+1.6))
    d.rr([x0, y, x0+54, y+30], 15, fill=A(WHITE, 0.06*ra))
    for i in range(3):
        d.ell([x0+14+i*13, y+13, x0+19+i*13, y+18], fill=A(GRAY, 0.9*ra))

def c_more(d, t, a, ts):
    x0, y0, x1, y1 = CR; w = x1-x0
    d.txt((x0, y0+8), '还有这些', F('cnb', 21), A(WHITE, 0.95*a))
    d.txt((x0, y0+38), '同一套面板，各管一件事', F('cn', 11.5), A(GRAY, 0.85*a))
    tiles = [('cal', '日历', '农历 · 生日 · 倒计时', ACCENT),
             ('abc', '背单词', '分级词库 + 发音', ACCENT2),
             ('spark', 'Codex 额度', '用量与重置时间', ACCENT),
             ('note', '笔记', '分组 · 搜索 · 置顶', GOLD),
             ('clip', '剪贴板', '历史与快速粘贴', ACCENT2),
             ('cross', '诊断', '睡眠 · 网络 · 存储', ACCENT)]
    tw_, th_ = (w-12)/2, 92
    for i, (kind, name, sub, col) in enumerate(tiles):
        cxi, cyi = i % 2, i//2
        bx = x0+cxi*(tw_+12); by = y0+76+cyi*(th_+12)
        ra = a*eo(seg(t, ts+0.10+i*0.12, ts+0.60+i*0.12))
        sl = (1-ra)*14
        d.rr([bx, by+sl, bx+tw_, by+th_+sl], 13, fill=A(WHITE, 0.05*ra))
        d.rr([bx+12, by+14+sl, bx+38, by+40+sl], 9, fill=A(col, 0.16*ra))
        icon(d, kind, bx+25, by+27+sl, 8, col, 0.95*ra)
        d.txt((bx+12, by+50+sl), name, F('cnb', 13), A(WHITE, 0.92*ra))
        d.txt((bx+12, by+69+sl), sub, F('cn', 9.5), A(DIM, 0.95*ra))

CONTENTS = [(4.20, 8.30, c_today), (8.30, 12.70, c_monitor), (12.70, 17.10, c_gold),
            (17.10, 21.50, c_chat), (21.50, 25.00, c_more)]
CAPS = [(4.20, 8.30, '01 / 十个模块', ['一个菜单栏', '装下十件小事'], '点开就走，不占桌面'),
        (8.30, 12.70, '02 / 系统监控', ['CPU、内存、温度', '一眼看清'], '进程排行、电池、网络，都在这一个面板'),
        (12.70, 17.10, '03 / 金价', ['积存金实时行情', '和技术指标'], '涨红跌绿，按中国习惯着色'),
        (17.10, 21.50, '04 / AI 助手', ['问一句', '它读得懂你的机器'], '支持 OpenAI / Anthropic / Ollama'),
        (21.50, 25.00, '05 / 还有', ['日历 · 背单词 · 额度', '笔记 · 剪贴板 · 诊断'], '所有数据都留在本地')]

# ---------------- chrome: menubar / rail / panel ----------------
def logo(d, cx, cy, s, a=1.0):
    d.rr([cx-s, cy-s, cx+s, cy+s], s*0.30, fill=A(mix(ACCENT, WHITE, 0.06), a))
    d.rr([cx-s*0.9, cy-s*0.9, cx+s*0.9, cy+s*0.05], s*0.26, fill=A(WHITE, 0.12*a))
    r = s*0.46
    d.ell([cx-r, cy-r, cx+r, cy+r], outline=A(WHITE, 0.96*a), width=max(1.2, s*0.11))
    d.ell([cx+r*0.40, cy-r*0.74, cx+r*0.72, cy-r*0.42], fill=A(WHITE, 0.96*a))

def draw_menubar(d, t, a=1.0, dim=1.0):
    if a <= 0.004: return
    p = eo(seg(t, 0.62, 1.55))
    y0 = -(MB_H+3)+(MB_H+3)*p
    d.rect([0, y0, W, y0+MB_H], A(C('0a0c14'), 0.88*a*dim))
    d.rect([0, y0+MB_H, W, y0+MB_H+1.2], A(WHITE, 0.11*a*dim))
    fx = F('sfb', 13); fm = F('cn', 12.5)
    d.txt((26, y0+MB_H/2), 'Finder', fx, A(WHITE, 0.92*a*dim), anchor='lm')
    x = 100
    for m in ['文件', '编辑', '显示', '前往', '窗口', '帮助']:
        d.txt((x, y0+MB_H/2), m, fm, A(WHITE, 0.66*a*dim), anchor='lm')
        x += vw(m, fm)+20
    # right cluster
    d.txt((1884, y0+MB_H/2), '22:41', fx, A(WHITE, 0.88*a*dim), anchor='rm')
    ic = C('cfd4e6')
    # wifi
    for i, r in enumerate([1.6, 3.4, 5.2]):
        d.ell([1812-r, y0+MB_H/2+2-r, 1812+r, y0+MB_H/2+2+r], outline=A(ic, 0.55*a*dim), width=1.1)
    # battery
    d.rr([1832, y0+MB_H/2-5, 1856, y0+MB_H/2+5], 2.5, outline=A(ic, 0.6*a*dim), width=1.1)
    d.rr([1834.5, y0+MB_H/2-2.5, 1849, y0+MB_H/2+2.5], 1.5, fill=A(ic, 0.6*a*dim))
    # coolrun status item
    gl = 1.0 if t > 3.2 else 0.0
    pulse = 0.5+0.5*math.sin((t-3.2)*2.6) if t > 3.2 else 0.0
    if gl > 0:
        for k in range(2):
            e = 12+6*k+pulse*3
            d.rr([1694-e, y0+MB_H/2-e, 1694+e, y0+MB_H/2+e], 10+e*0.2,
                 fill=A(ACCENT, (0.10-0.04*k)*gl*a))
        d.rr([1676, y0+5, 1712, y0+MB_H-5], 8, fill=A(ACCENT, 0.22*gl*a))
    logo(d, 1694, y0+MB_H/2, 10, 0.95*a*dim)

def sel_index(t):
    trans = [(4.20, 0), (8.30, 1), (12.70, 2), (17.10, 9), (21.50, 3)]
    pos = 0.0
    for i, (ts, idx) in enumerate(trans):
        pp = eio(seg(t, ts-0.02, ts+0.42))
        if pp <= 0: continue
        base = trans[i-1][1] if i > 0 else 0
        pos = base+(idx-base)*pp
    return pos

def draw_rail(pd, t, a):
    pos = sel_index(t)
    # moving highlight
    hy = RAIL_TOP+pos*(RAIL_IH+RAIL_GAP)
    pd.rr([RAIL_X, hy, RAIL_X+RAIL_IW, hy+RAIL_IH], 12, fill=A(ACCENT, 0.16*a))
    pd.rr([RAIL_X, hy, RAIL_X+RAIL_IW, hy+RAIL_IH], 12, outline=A(ACCENT, 0.30*a), width=1)
    for i, (kind, name, col) in enumerate(MODS):
        ia = eo(seg(t, 4.35+i*0.19, 4.80+i*0.19))
        if ia <= 0.004: continue
        iy = RAIL_TOP+i*(RAIL_IH+RAIL_GAP)
        sel = max(0.0, 1-abs(pos-i))
        cx, cy = RAIL_X+RAIL_IW/2, iy+RAIL_IH/2
        col2 = mix(GRAY, WHITE, 0.18+0.80*sel)
        icon(pd, kind, cx, cy, 9.2, col2, ia*0.95)
        if i == 9 or i == 0:
            pass

def draw_panel(canvas, t):
    pa = eo(seg(t, 3.15, 4.10))
    if t > 24.80: pa *= 1-eo(seg(t, 24.80, 25.45))
    if pa <= 0.004: return
    dy = (1-pa)*(-28)
    pl = Image.new('RGBA', (int(PW*SS), int(PH*SS)), (0, 0, 0, 0))
    pd = D(pl)
    pd.rr([0, 0, PW, PH], 22, fill=A(C('161a27'), 0.96))
    pd.rr([1, 1, PW-1, 150], 20, fill=A(WHITE, 0.020))
    pd.rr([6, 6, 56, PH-6], 14, fill=A(WHITE, 0.032))
    pd.line([(63, 14), (63, PH-14)], A(WHITE, 0.07), 1)
    draw_rail(pd, t, 1.0)
    for i, (ts, te, fn) in enumerate(CONTENTS):
        ain = eo(seg(t, ts-0.36, ts+0.30)) if i > 0 else eo(seg(t, ts-0.60, ts+0.30))
        aout = seg(t, te-0.32, te+0.02)
        aa = ain*(1-aout)
        if aa <= 0.012: continue
        sl = (1-ain)*22-aout*22
        fn(D(pl, 0, sl), t, aa, ts)
    pd.line([(18, PH-56), (PW-18, PH-56)], A(WHITE, 0.07), 1)
    pd.txt((18, PH-44), '本地存储 · 不上传', F('cn', 10.5), A(DIM, 0.95))
    pd.txt((PW-20, PH-44), '设置', F('cn', 10.5), A(GRAY, 0.9), anchor='rm')
    pd.ell([PW-52, PH-47, PW-42, PH-37], outline=A(GRAY, 0.7), width=1.1)
    pd.ell([PW-48.5, PH-43.5, PW-45.5, PH-40.5], fill=A(GRAY, 0.7))
    pd.rr([0, 0, PW, PH], 22, outline=A(WHITE, 0.105), width=1.1)
    mask = Image.new('L', pl.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, pl.size[0]-1, pl.size[1]-1],
                                           radius=22*SS, fill=255)
    arr = np.asarray(pl).astype(np.float32)
    m = (np.asarray(mask).astype(np.float32)/255.0)[..., None]
    arr[..., 3] = arr[..., 3]*m[..., 0]*pa
    out = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), 'RGBA')
    cd = D(canvas)
    for e, aa2 in ((34, 0.016), (22, 0.022), (12, 0.030)):
        cd.rr([PX-e, PY+dy-e, PX+PW+e, PY+dy+PH+e], 22+e,
              fill=A(ACCENT, aa2*pa))
    canvas.paste(out, (int(PX*SS), int((PY+dy)*SS)), out)

def draw_captions(d, t):
    for (ts, te, eb, heads, body) in CAPS:
        ain = eo(seg(t, ts-0.22, ts+0.48))
        aout = seg(t, te-0.30, te+0.04)
        a = ain*(1-aout)
        if a <= 0.012: continue
        sl = (1-ain)*28-aout*28
        bx, by = 150, 396
        d.rr([bx, by+sl, bx+3.5, by+17+sl], 1.6, fill=A(ACCENT, 0.95*a))
        d.txt((bx+16, by+1+sl), eb, F('cnb', 13), A(ACCENT, 0.95*a))
        y = by+42+sl
        for hdt in heads:
            d.txt((bx, y), hdt, F('cnb', 46), A(WHITE, 0.97*a)); y += 62
        d.txt((bx, y+22), body, F('cn', 16), A(GRAY, 0.95*a))
        d.line([(bx, y+62), (bx+70, y+62)], A(ACCENT, 0.35*a), 1.4)

def draw_hero_title(d, t):
    ain = eo(seg(t, 1.25, 2.20))
    aout = seg(t, 3.05, 3.62)
    a = ain*(1-aout)
    if a <= 0.012: return
    sl = (1-ain)*30-aout*18
    logo(d, W/2, 382+sl, 52, a*0.95)
    d.tcenter(W/2, 516+sl, 'CoolRun', F('sfh', 112), A(WHITE, 0.98*a), ls=-2.0)
    d.tcenter(W/2, 622+sl, 'macOS 菜单栏里的十合一工具集', F('cn', 26), A(WHITE, 0.62*a))

def draw_outro(canvas, d, t):
    ain = eo(seg(t, 25.15, 26.30))
    if ain <= 0.006: return
    sl = (1-ain)*34
    logo(d, W/2, 350+sl, 48, ain*0.95)
    d.tcenter(W/2, 470+sl, 'CoolRun', F('sfh', 116), A(WHITE, 0.98*ain), ls=-2.0)
    d.tcenter(W/2, 566+sl, '轻，但什么都有。', F('cnb', 32), A(WHITE, 0.84*ain))
    a2 = eo(seg(t, 25.9, 26.9))
    d.tcenter(W/2, 634+sl, 'macOS 15+ · 十个模块 · 数据全部留在本地', F('cn', 16), A(GRAY, 0.9*a2))
    d.line([(W/2-96, 676+sl), (W/2+96, 676+sl)], A(ACCENT, 0.30*a2), 1.4)

# ---------------- main ----------------
def render(t):
    canvas = BG.copy()
    d = D(canvas)
    if t < 25.2:
        draw_menubar(d, t)
        draw_hero_title(d, t)
        draw_captions(d, t)
        draw_panel(canvas, t)
    else:
        draw_menubar(d, t, 1.0, dim=0.55)
        draw_outro(canvas, d, t)
    if t < 0.95:
        d.rect([0, 0, W, H], A((0, 0, 0), 1-eo(seg(t, 0.02, 0.95))))
    if t > 28.60:
        d.rect([0, 0, W, H], A((0, 0, 0), eo(seg(t, 28.60, 29.90))))
    return canvas

def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--probe', type=float, nargs='*')
    ap.add_argument('--frames', type=int, default=NF)
    ap.add_argument('--out', default=OUT)
    aa = ap.parse_args()
    if aa.probe:
        for tt in aa.probe:
            t0 = time.time()
            img = render(tt).resize((W, H), Image.LANCZOS)
            p = f'/tmp/coolrun_video/frames/probe_{tt:05.2f}.png'
            img.save(p)
            ar = np.asarray(img).astype(np.float32)
            print(f't={tt:5.2f} {time.time()-t0:5.2f}s  mean={ar.mean():6.2f} '
                  f'std={ar.std():5.2f}  -> {p}')
        return
    cmd = ['ffmpeg', '-y', '-loglevel', 'error', '-f', 'rawvideo', '-pix_fmt', 'rgb24',
           '-s', f'{W}x{H}', '-r', str(FPS), '-i', '-', '-an', '-c:v', 'libx264',
           '-preset', 'medium', '-crf', '17', '-pix_fmt', 'yuv420p',
           '-movflags', '+faststart', aa.out]
    pr = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    t0 = time.time()
    for i in range(aa.frames):
        t = i/FPS
        img = render(t).resize((W, H), Image.LANCZOS)
        pr.stdin.write(img.tobytes())
        if i % 60 == 0:
            el = time.time()-t0
            print(f'  frame {i}/{aa.frames}  {el:6.1f}s  eta {el/max(1,i)*(aa.frames-i):5.0f}s',
                  flush=True)
    pr.stdin.close(); pr.wait()
    print('done ->', aa.out, os.path.getsize(aa.out)//1024, 'KB')

if __name__ == '__main__':
    main()
