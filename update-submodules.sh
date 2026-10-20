#!/usr/bin/env bash
#
# update-submodules.sh — 更新 submodule/ 下各配置分支到远端最新
#
# 用法:
#   ./update-submodules.sh            拉最新 + 打印父仓指针提交命令
#   ./update-submodules.sh --commit   拉最新 + 自动提交父仓指针
#                                     （含之前运行遗留未提交的指针变更）
#
# 分支取自 .gitmodules 的 branch 字段；更新用 rebase（与 update = rebase 配置
# 语义一致），submodule 内无本地新提交时即为 fast-forward。
#
# 注意: 不能用 `git submodule update --remote`，配合本仓浅克隆 + update=rebase
# 配置会因"要求干净工作区"的前置条件在未初始化/半初始化状态下失败。

set -euo pipefail

cd "$(dirname "$0")"

DO_COMMIT=false
if [[ "${1:-}" == "--commit" ]]; then
    DO_COMMIT=true
fi

updated=()
failed=()

# 本仓 submodule 的 name == path（如 submodule/nvim）
while IFS=' ' read -r key branch; do
    path=${key#submodule.}
    path=${path%.branch}
    name=${path#submodule/}

    # ---- 0. 未克隆的先初始化（--checkout 绕开 update=rebase 的前置条件）----
    status_line=$(git submodule status -- "$path")
    if [[ $status_line == -* ]]; then
        echo "[$name] 未初始化，先克隆到父仓记录的 commit"
        git submodule update --init --checkout -- "$path"
    fi

    # ---- 1. 拉取配置分支最新 ----
    if ! git -C "$path" fetch origin "$branch"; then
        echo "[$name] ✗ fetch origin $branch 失败，跳过"
        failed+=("$name")
        continue
    fi

    # 不在配置分支上（初始化后的 detached HEAD、遗留 main 等）则切回去
    current=$(git -C "$path" rev-parse --abbrev-ref HEAD)
    if [[ $current != "$branch" ]]; then
        if ! {
            git -C "$path" checkout "$branch" 2>/dev/null ||
                git -C "$path" checkout -b "$branch" FETCH_HEAD
        }; then
            echo "[$name] ✗ 切回 $branch 失败（工作区不干净?），跳过: cd $path && git status"
            failed+=("$name")
            continue
        fi
    fi

    old=$(git -C "$path" rev-parse HEAD)
    new=$(git -C "$path" rev-parse FETCH_HEAD)
    if [[ $old == "$new" ]]; then
        echo "[$name] 已是最新 ($branch @ ${old:0:7})"
        continue
    fi

    # ---- 2. rebase 到远端最新 ----
    if ! git -C "$path" rebase FETCH_HEAD; then
        git -C "$path" rebase --abort 2>/dev/null || true
        echo "[$name] ✗ rebase 失败（未提交改动或冲突），保持原状: cd $path && git status"
        failed+=("$name")
        continue
    fi

    count=$(git -C "$path" rev-list --count "$old..$new")
    echo "[$name] ${old:0:7} -> ${new:0:7} ($branch, +$count)"
    git -C "$path" log --oneline "$old..$new" | sed 's/^/    /' || true
    updated+=("$name")
done < <(git config -f .gitmodules --get-regexp '^submodule\..*\.branch$')

# 父仓视角待记录的指针变化（本次更新的 + 之前遗留未提交的）
pending=()
while IFS= read -r p; do
    pending+=("${p#submodule/}")
done < <(git diff --name-only HEAD -- submodule/)

echo
echo "----------------------------------------"
if [[ ${#updated[@]} -gt 0 || ${#pending[@]} -gt 0 ]]; then
    [[ ${#updated[@]} -eq 0 ]] || echo "已更新: ${updated[*]}"
    [[ ${#failed[@]} -eq 0 ]] || echo "失败/跳过: ${failed[*]}"
    if [[ ${#pending[@]} -gt 0 ]]; then
        msg="chore: 更新 submodule 指针（${pending[*]}）"
        if $DO_COMMIT; then
            git add submodule/
            git commit -m "$msg"
            echo "已提交: $msg"
        else
            echo "待记录父仓指针: ${pending[*]}"
            echo "    git add submodule/ && git commit -m \"$msg\""
        fi
    fi
else
    echo "全部 submodule 均已是最新，父仓指针无待记录变化"
    [[ ${#failed[@]} -eq 0 ]] || echo "失败/跳过: ${failed[*]}"
fi

[[ ${#failed[@]} -eq 0 ]]
