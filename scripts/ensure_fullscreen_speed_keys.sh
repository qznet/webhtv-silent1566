#!/usr/bin/env bash
# 全屏调速守护：确保 leanback flavor 的「全屏播放中短按上下键调节倍速」定制未被上游覆盖。
#
# 背景：本仓库通过 -X theirs 合并上游，上游若重构 VideoActivity / CustomKeyDownVod，
# 可能把我们的stepSpeed / onSpeedStepUp / onSpeedStepDown /短按映射 覆盖掉，导致
# 全屏上下键不再调速。此脚本在每次 release 前运行：
#   1) 检测关键实现是否还在；
#   2) 若缺失，自动重新应用补丁（幂等）。
#
# 用法： bash scripts/ensure_fullscreen_speed_keys.sh
# 退出码：0 = 定制完好（或已成功修复）；1 = 修复失败，需人工介入。
set -euo pipefail

CK="app/src/leanback/java/com/fongmi/android/tv/ui/custom/CustomKeyDownVod.java"
VA="app/src/leanback/java/com/fongmi/android/tv/ui/activity/VideoActivity.java"
CA="app/src/leanback/java/com/fongmi/android/tv/ui/activity/CastActivity.java"

fail() {
  echo "::error title=全屏调速定制缺失::$1"
  exit 1
}

[ -f "$CK" ] || fail "缺少 $CK"
[ -f "$VA" ] || fail "缺少 $VA"

need_fix=0

# ---- 1. CustomKeyDownVod：短按上下键映射 + Listener 新方法 ----
if grep -q "onSpeedStepUp" "$CK"; then
  echo "OK  CustomKeyDownVod 含 onSpeedStepUp 映射"
else
  echo "WARN CustomKeyDownVod 缺少 onSpeedStepUp 映射，尝试重新应用"
  need_fix=1
fi

if grep -q "void onSpeedStepDown();" "$CK"; then
  echo "OK  CustomKeyDownVod Listener 含 onSpeedStepDown"
else
  echo "WARN CustomKeyDownVod Listener 缺少 onSpeedStepDown，尝试重新应用"
  need_fix=1
fi

if grep -q "void onShowControl();" "$CK"; then
  echo "OK  CustomKeyDownVod Listener 含 onShowControl"
else
  echo "WARN CustomKeyDownVod Listener 缺少 onShowControl，尝试重新应用"
  need_fix=1
fi

# ---- 2. VideoActivity：stepSpeed 实现 ----
if grep -q "private void stepSpeed(float delta)" "$VA"; then
  echo "OK  VideoActivity 含 stepSpeed 实现"
else
  echo "WARN VideoActivity 缺少 stepSpeed，尝试重新应用"
  need_fix=1
fi

if [ "$need_fix" -eq 0 ]; then
  # 定制完好时仍需确认所有 Listener 实现类都补齐了新方法（CastActivity 投屏也实现了该接口）
  if [ -f "$CA" ] && ! grep -q "public void onSpeedStepUp()" "$CA"; then
    echo "WARN CastActivity 未实现 onSpeedStepUp（Listener 新方法），尝试补齐"
    need_fix=1
  fi
fi

if [ "$need_fix" -eq 0 ]; then
  echo "全屏调速定制完好，无需修复。"
  exit 0
fi

echo "开始重新应用全屏调速补丁..."

# ---- 3. 重新应用：CustomKeyDownVod ----
python3 - "$CK" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
orig = s

# 3a. 短按上键 -> onSpeedStepUp；短按下键 -> onSpeedStepDown
old_up = """} else if (KeyUtil.isActionUp(event) && KeyUtil.isUpKey(event)) {
            if (changeSpeed) listener.onSpeedEnd();
            else listener.onKeyUp();
            changeSpeed = false;
        } else if (KeyUtil.isActionUp(event) && KeyUtil.isDownKey(event)) {
            listener.onKeyDown();
        }"""
new_up = """} else if (KeyUtil.isActionUp(event) && KeyUtil.isUpKey(event) && !event.isLongPress()) {
            if (changeSpeed) listener.onSpeedEnd();
            else listener.onSpeedStepUp();
            changeSpeed = false;
        } else if (KeyUtil.isActionUp(event) && KeyUtil.isDownKey(event) && !event.isLongPress()) {
            if (!showControlArmed) listener.onSpeedStepDown();
            showControlArmed = false;
        }"""
if old_up in s:
    s = s.replace(old_up, new_up, 1)
    print("  patched: short-press up/down mapping")
elif "onSpeedStepUp" in s:
    print("  short-press mapping already present, skip")
else:
    # 上游结构可能变了，退回到更宽松的定位：只要有 isActionUp + isUpKey 分支就改写它
    print("  WARN: could not locate exact short-press block; manual review needed")
    sys.exit(3)

# 3b. 长按下键 -> 显示控制栏
if "listener.onShowControl();" not in s:
    anchor = """            listener.onSpeedUp();
            changeSpeed = true;
        }"""
    repl = """            listener.onSpeedUp();
            changeSpeed = true;
        } else if (event.isLongPress() && KeyUtil.isDownKey(event)) {
            listener.onShowControl();
            showControlArmed = true;
        }"""
    if anchor in s:
        s = s.replace(anchor, repl, 1)
        print("  patched: long-press down -> onShowControl")
    else:
        print("  WARN: could not locate long-press anchor; manual review needed")
        sys.exit(3)

# 3c. showControlArmed 字段
if "private boolean showControlArmed;" not in s:
    s = s.replace("    private boolean changeSpeed;",
                  "    private boolean changeSpeed;\n    private boolean showControlArmed;", 1)
    print("  patched: showControlArmed field")

# 3d. Listener 新方法
if "void onSpeedStepUp();" not in s:
    s = s.replace("        void onSpeedEnd();",
                  "        void onSpeedEnd();\n\n        void onSpeedStepUp();\n\n        void onSpeedStepDown();\n\n        void onShowControl();", 1)
    print("  patched: Listener methods")

if s != orig:
    open(p, "w", encoding="utf-8").write(s)
    print("  CustomKeyDownVod updated")
else:
    print("  CustomKeyDownVod unchanged")
PY

# ---- 4. 重新应用：VideoActivity ----
python3 - "$VA" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
orig = s

if "private void stepSpeed(float delta)" in s:
    print("  stepSpeed already present, skip")
else:
    # 插到 onKeyCenter 之前（该方法在两个仓库都稳定存在）
    anchor = "    @Override\n    public void onKeyCenter() {"
    block = """    @Override
    public void onSpeedStepUp() {
        stepSpeed(0.1f);
    }

    @Override
    public void onSpeedStepDown() {
        stepSpeed(-0.1f);
    }

    @Override
    public void onShowControl() {
        showControl(getFocus2());
    }

    /** 全屏播放中短按上下键调节倍速（±0.1），暂停时不生效。 */
    private void stepSpeed(float delta) {
        if (player() == null || !player().isPlaying()) return;
        float speed = Math.round((player().getSpeed() + delta) * 10f) / 10f;
        speed = Math.min(5.0f, Math.max(0.25f, speed));
        CharSequence text = player().setSpeed(speed);
        mBinding.control.action.speed.setText(text);
        Notify.show(String.valueOf(text));
        if (mHistory != null) mHistory.setUserSpeed(player().getSpeed());
    }

"""
    if anchor in s:
        s = s.replace(anchor, block + anchor, 1)
        open(p, "w", encoding="utf-8").write(s)
        print("  VideoActivity: stepSpeed + handlers inserted")
    else:
        print("  ERROR: could not locate onKeyCenter anchor in VideoActivity")
        sys.exit(3)
PY

# ---- 4b. 重新应用：CastActivity（另一个 Listener 实现类，投屏场景不调速，仅唤出控制栏）----
if [ -f "$CA" ] && ! grep -q "public void onSpeedStepUp()" "$CA"; then
python3 - "$CA" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
anchor = """    @Override
    public void onKeyDown() {
        showControl();
    }"""
block = anchor + """

    // 投屏场景不提供倍速调节，短按上下键统一唤出控制栏。
    @Override
    public void onSpeedStepUp() {
        showControl();
    }

    @Override
    public void onSpeedStepDown() {
        showControl();
    }

    @Override
    public void onShowControl() {
        showControl();
    }"""
if anchor in s:
    s = s.replace(anchor, block, 1)
    open(p, "w", encoding="utf-8").write(s)
    print("  CastActivity: Listener methods inserted")
else:
    print("  ERROR: could not locate onKeyDown anchor in CastActivity")
    sys.exit(3)
PY
fi

# ---- 5. 复检 ----
echo "复检..."
rc=0
for pat in "onSpeedStepUp" "onSpeedStepDown" "onShowControl"; do
  if ! grep -q "$pat" "$CK"; then echo "::error title=补丁复检失败::CustomKeyDownVod 仍缺 $pat"; rc=1; fi
done
# 接口必须保留 onKeyUp/onKeyDown（CastActivity 等实现类依赖）
for pat in "void onKeyUp();" "void onKeyDown();"; do
  if ! grep -q "$pat" "$CK"; then echo "::error title=补丁复检失败::Listener 仍缺 $pat（会导致实现类编译失败）"; rc=1; fi
done
if ! grep -q "private void stepSpeed(float delta)" "$VA"; then echo "::error title=补丁复检失败::VideoActivity 仍缺 stepSpeed"; rc=1; fi
if [ -f "$CA" ]; then
  for pat in "public void onSpeedStepUp()" "public void onSpeedStepDown()" "public void onShowControl()"; do
    if ! grep -q "$pat" "$CA"; then echo "::error title=补丁复检失败::CastActivity 仍缺 $pat（Listener 实现不完整）"; rc=1; fi
  done
fi
[ "$rc" -eq 0 ] && echo "全屏调速定制已修复并复检通过。"
exit $rc