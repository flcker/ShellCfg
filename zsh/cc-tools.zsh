# ============================================================
# Claude Code 工具集 — 模型切换 & 版本管理
# ============================================================
# 模块加载后提供 cc 命令：
#   cc ds|deepseek    切换到 DeepSeek 系列
#   cc glm            切换到 GLM 系列
#   cc claude         切换到 Claude 官方系列
#   cc gpt            切换到 GPT 系列
#   cc official       恢复官方默认
#   cc model          显示当前模型配置
#   cc update [ver]   更新/管理 Claude Code CLI 版本
#   cc help           显示帮助
#
# 配置（在 ~/.zshrc 中设置）：
#   export CC_MODEL_API_KEY="sk-..."       # API 密钥（必需）
#   export CC_MODEL_BASE_URL="http://..."  # 代理地址（可选，默认走官方）
# ============================================================

source "${0:A:h}/../submodule/cc-tools/cc.zsh"
