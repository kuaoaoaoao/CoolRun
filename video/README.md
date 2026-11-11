# CoolRun 介绍短片（代码生成）

`coolrun_intro.mp4` 不是剪出来的，是**渲染**出来的：`render.py` 里每一帧都是
一个纯函数 `render(t)`，算出 1920×1080 的像素，通过管道直接喂给 ffmpeg。

- 1920×1080 / 30fps / 30s / H.264（无音轨）
- 首次渲染约 40 秒，改完重跑即可整条重生

## 改法

```bash
python3 video/render.py                        # 出整片 -> /tmp/coolrun_video/coolrun_intro.mp4
python3 video/render.py --probe 6 15 19         # 只出指定秒数的静帧，调版式时用
python3 video/render.py --frames 300            # 只渲前 10 秒
```

常用的旋钮都在文件顶部：

| 位置 | 作用 |
| --- | --- |
| `W, H, FPS, DUR` | 分辨率 / 帧率 / 时长 |
| `ACCENT, GOLD, UP, DOWN` | 取自 `Core/AppTheme.swift` 的品牌色（涨红跌绿按中国习惯） |
| `CONTENTS` | 五个内容段落的时间窗与绘制函数 |
| `CAPS` | 左侧字幕（小标 + 大标题 + 说明） |
| `MODS` | 左侧导航栏的十个模块 |

文案在 `c_*` 函数里，模块名与 `ViewMode` 对齐；`AppTheme` 的配色改了就同步改顶部常量。

## 依赖

macOS 自带字体（Hiragino Sans GB / SF Pro），Pillow + numpy + ffmpeg。
