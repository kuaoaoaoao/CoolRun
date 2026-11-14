#!/usr/bin/env bash
#
# 把 dsh-pet 插件里的动作视频转成 CoolRun 能播的格式。
#
# 为什么需要转：插件跑在 Electron 里，直接用 <video> 播 VP9-alpha 的 .webm；
# CoolRun 是原生 App，AVFoundation 不认识 VP9，只认 Apple 自己的 HEVC-with-alpha。
# 所以这里把 webm 解出透明通道、重新编成 hvc1 + ALPHA_MODE=1 的 .mov。
#
# 素材来源（插件包，npm 安装位置随 profile 不同）：
#   ~/.dsh/profiles/<profile>/node_modules/dsh-pet/assets/webm/*.webm
# 也可以用 DSH_PET_ASSETS 环境变量指过去。
#
# 裁剪：原始画面 640×360，角色实际只占中间约 215×270（实测包围盒
# x 203–428、y 60–329）。整帧缩放会让角色只剩一半大，所以统一裁成
# 336×300 @ (152,30) —— 角色四周留一点余量，走两步、甩尾巴都还在画面里。
#
# 用法：
#   ./scripts/pet-clips.sh            # 转全部已登记的片段
#   ./scripts/pet-clips.sh --list     # 只列出映射，不转码
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
OUT="$ROOT/CoolRun/Assets/PetClips"

SRC="${DSH_PET_ASSETS:-}"
if [ -z "$SRC" ]; then
    for candidate in "$HOME"/.dsh/profiles/*/node_modules/dsh-pet/assets/webm; do
        if [ -d "$candidate" ]; then SRC="$candidate"; fi
    done
fi
if [ ! -d "${SRC:-/nonexistent}" ]; then
    echo "找不到 dsh-pet 的素材目录。装一下插件，或者设 DSH_PET_ASSETS 指到 assets/webm。" >&2
    exit 1
fi

# 片段表：英文文件名 ← 插件里的中文动画名
# 右边第二个字段是播放方式：loop = 循环，once = 播完回待机。
CLIPS=(
    "idle:待机呼吸休闲:loop"
    "idleAlt:原地漂浮踏步:loop"
    "lookAround:东张西望:once"
    "drag:被鼠标拖拽悬空反馈:loop"
    "clickHappy:点击回应-开心跃动:once"
    "clickShy:点击回应-害羞惊讶:once"
    "clickAngry:点击回应-傲娇生气:once"
    "clickTickle:点击回应-挠痒咯咯笑:once"
    "clickWave:点击回应-元气挥手:once"
    "walkCrab:螃蟹走路:once"
    "run:原地左转奔跑:once"
    "sleepStart:睡觉-开始:once"
    "sleepLoop:睡觉-循环:loop"
    "wake:睡觉-起来:once"
    "workBusy:工作状态-忙碌点按:loop"
    "workThink:工作状态-思考冒泡:loop"
    "workArchive:工作状态-清点归档:loop"
    "workPace:工作状态-原地踱步张望:loop"
    "workCelebrate:工作状态-雀跃庆祝:once"
    "workTired:工作状态-垂头叹气冒汗:loop"
    "thinking:深度思考碎碎念:loop"
    "eatRice:吃白饭:once"
    "yawn:哈欠连天:once"
    "stretch:超大伸懒腰:once"
    "startled:被吓一跳:once"
    "whale:蓝鲸现世:once"

    # 吃什么（点她的时候偶尔抽到，或者吃完饭）
    "eatTangyuan:吃汤圆:once"
    "eatZongzi:吃粽子:once"
    "eatWatermelon:吃西瓜:once"
    "eatIceCream:吃冰淇淋融化:once"
    "eatHotpot:涮火锅:once"
    "eatTanghulu:吃糖葫芦:once"
    "eatDumpling:吃饺子:once"
    "eatNianGao:吃年糕:once"

    # 时节（按日期自动挑，见 PetClip.seasonal(for:)）
    "mooncake:中秋赏月吃月饼:once"
    "snowman:堆雪人:once"
    "christmasTree:装点圣诞树:once"
    "pumpkin:讨糖南瓜灯:once"
    "fu:写福字:once"
    "redPacket:收红包:once"
    "skyLantern:放孔明灯:once"
    "leaves:被落叶淹没:once"

    # 碎碎念
    "daydream:碎碎念-发呆碎碎念:once"
    "screenTalk:碎碎念-对屏碎碎念:once"
    "wipeTable:碎碎念-擦桌碎碎念:once"

    # 自己玩
    "cat:撸猫:once"
    "code:写代码:once"
    "ghost:萌化小幽灵:once"
    "bubbles:鲸鱼吐泡泡特效:once"
    "tailSlam:用鲸鱼尾巴拍打地面:once"
)

if [ "${1:-}" = "--list" ]; then
    for row in "${CLIPS[@]}"; do
        IFS=':' read -r key zh mode <<< "$row"
        printf '%-14s %-6s %s\n' "$key" "$mode" "$zh"
    done
    exit 0
fi

mkdir -p "$OUT"
total_before=$(du -sk "$OUT" 2>/dev/null | cut -f1 || echo 0)

for row in "${CLIPS[@]}"; do
    IFS=':' read -r key zh mode <<< "$row"
    src="$SRC/$zh.webm"
    dst="$OUT/$key.mov"
    if [ ! -f "$src" ]; then
        echo "跳过 $key：缺 $zh.webm" >&2
        continue
    fi
    if [ -f "$dst" ] && [ "$dst" -nt "$src" ]; then
        continue
    fi
    # -c:v libvpx-vp9 是必须的：默认解码器会把 alpha 丢掉，出来是黑底。
    #
    # 参数是照体积挑的：每段都固定 10 秒，q=50/24fps/alpha 0.8 一段要 650 KB，
    # 50 段就 32 MB。卡通形象降到 20fps、alpha 0.6、q=45 只掉一点点观感，
    # 体积却能省一半（实测同一段 613 KB → 340 KB）。
    ffmpeg -y -v error \
        -c:v libvpx-vp9 -i "$src" \
        -vf "crop=336:300:152:30,fps=20,format=yuva420p" \
        -c:v hevc_videotoolbox -alpha_quality 0.6 -q:v 45 \
        -tag:v hvc1 -pix_fmt yuva420p -an \
        "$dst"
    printf '%-14s %6s KB\n' "$key" "$(( $(stat -f%z "$dst") / 1024 ))"
done

total_after=$(du -sk "$OUT" | cut -f1)
echo "---"
echo "输出：$OUT"
echo "合计：$((total_after / 1024)) MB（转码前 $((total_before / 1024)) MB）"
