#!/usr/bin/env bash
# 仓库保活脚本
#
# 背景：GitHub 对公开仓库有一条规则——如果仓库连续 60 天没有任何活动（commit/push），
# 所有 schedule 触发的 workflow 会被自动停用，需要手动去 Actions 页面重新启用。
# 这会直接导致每日自动登录「悄悄」失效。
#
# 本脚本做两件事：
#   1. 距离上次保活提交超过 INTERVAL_DAYS 天时，更新 .github/keepalive 并推送一个 commit，
#      从而重置 GitHub 的 60 天无活动计时器（不需要每天提交，避免刷屏 commit 历史）。
#   2. 顺手检查 login.yml 是否处于 disabled 状态，如果是则调用 REST API 重新启用，
#      这样即使之前已经被停用，手动跑一次本 workflow 也能自动恢复。
#
# 需要的权限：contents: write（提交）、actions: write（重新启用 workflow）
set -euo pipefail

KEEPALIVE_FILE="${KEEPALIVE_FILE:-.github/keepalive}"
INTERVAL_DAYS="${INTERVAL_DAYS:-25}"
WORKFLOW_FILE="${WORKFLOW_FILE:-login.yml}"

log() { printf '[keepalive] %s\n' "$*"; }

# ---------------------------------------------------------------- 1. 定期提交
today="$(date -u +%Y-%m-%d)"
now_ts="$(date -u +%s)"
need_commit=1

if [ -f "$KEEPALIVE_FILE" ]; then
  last="$(tr -d '[:space:]' < "$KEEPALIVE_FILE" || true)"
  if [ -n "$last" ] && last_ts="$(date -u -d "$last" +%s 2>/dev/null)"; then
    age_days=$(( (now_ts - last_ts) / 86400 ))
    log "上次保活提交：${last}（${age_days} 天前）"
    if [ "$age_days" -lt "$INTERVAL_DAYS" ]; then
      log "距今不足 ${INTERVAL_DAYS} 天，本次跳过提交"
      need_commit=0
    fi
  else
    log "无法解析 ${KEEPALIVE_FILE} 中的日期（内容：${last:-空}），本次强制提交"
  fi
else
  log "保活文件不存在，本次创建"
fi

if [ "$need_commit" -eq 1 ]; then
  printf '%s\n' "$today" > "$KEEPALIVE_FILE"
  git config user.name  "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  git add "$KEEPALIVE_FILE"

  if git diff --cached --quiet; then
    log "文件内容无变化，跳过提交"
  else
    git commit -m "chore(keepalive): ${today} [skip ci]"
    branch="${GITHUB_REF_NAME:-main}"
    # 并发/远端有新提交时重试几次
    for i in 1 2 3; do
      if git push origin "HEAD:${branch}"; then
        log "已推送保活提交 ${today} 到 ${branch}"
        break
      fi
      if [ "$i" -eq 3 ]; then
        log "push 最终失败（不影响登录任务本身，下次运行会再试）"
      else
        log "push 失败，第 ${i} 次重试前先 rebase"
        git pull --rebase --autostash origin "$branch" || true
        sleep $((i * 5))
      fi
    done
  fi
fi

# ------------------------------------------------- 2. 若 workflow 被停用则重新启用
if [ -z "${GH_TOKEN:-}" ]; then
  log "未提供 GH_TOKEN，跳过自动重新启用检查"
  exit 0
fi

api="https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/workflows/${WORKFLOW_FILE}"
state="$(curl -sS -o /tmp/wf.json -w '%{http_code}' \
  -H "Authorization: Bearer ${GH_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "${api}")"

if [ "$state" != "200" ]; then
  log "查询 ${WORKFLOW_FILE} 状态失败（HTTP ${state}），跳过"
  exit 0
fi

if grep -q '"state": *"disabled' /tmp/wf.json; then
  log "${WORKFLOW_FILE} 处于 disabled 状态，尝试重新启用"
  code="$(curl -sS -o /dev/null -w '%{http_code}' -X PUT \
    -H "Authorization: Bearer ${GH_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "${api}/enable")"
  if [ "$code" = "204" ]; then
    log "已重新启用 ${WORKFLOW_FILE}"
  else
    log "重新启用失败（HTTP ${code}），请到 Actions 页面手动启用（需 actions: write 权限）"
  fi
else
  log "${WORKFLOW_FILE} 状态正常，无需启用"
fi
