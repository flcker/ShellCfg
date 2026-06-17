################################################################################
# 需要在 "~/.zshrc" 中调用
################################################################################

# config dir vars
#   ${(%):-%x}   → prompt expansion 获取当前被 source 文件的路径（等效 bash $BASH_SOURCE）
#   :A           → 转为绝对路径（resolve symlinks）
#   :h           → 取父目录（head = dirname）
ZSH_CONFIG_DIR="${${(%):-%x}:A:h}"
ZSH_CONFIG_STARSHIP_DIR="$ZSH_CONFIG_DIR/submodule/starship"
ZSH_CONFIG_NVIM_DIR="$ZSH_CONFIG_DIR/submodule/nvim"

# proxy
PROXY_HOST="127.0.0.1"
PROXY_PORT="7890"

# module loader
ZSH_MODULE_DIR="$ZSH_CONFIG_DIR/zsh"

for config_file in "$ZSH_MODULE_DIR"/*.zsh; do
  if [[ -f "$config_file" ]]; then
    source "$config_file"
  fi
done
