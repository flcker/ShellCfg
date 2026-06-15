################################################################################
# function
# 定义一些常用的函数
function color_echo() {
  local color="$1"
  shift
  case "$color" in
    red) echo -e "\033[31m$*\033[0m" ;;
    green) echo -e "\033[32m$*\033[0m" ;;
    yellow) echo -e "\033[33m$*\033[0m" ;;
    blue) echo -e "\033[34m$*\033[0m" ;;
    magenta) echo -e "\033[35m$*\033[0m" ;;
    cyan) echo -e "\033[36m$*\033[0m" ;;
    *) echo "$*" ;;
  esac
}

alias cehco='color_echo' # 定义别名，方便使用 color_echo 函数

# proxyon: 设置系统代理
function proxyon() {
  export http_proxy="http://127.0.0.1:7890"
  export https_proxy="http://127.0.0.1:7890"
  export all_proxy="socks5://127.0.0.1:7890"
}

# proxyoff: 取消系统代理
function proxyoff() {
  unset http_proxy
  unset https_proxy
  unset all_proxy
}

# ghostty common keybindings helper function
# 这个函数用于显示 Ghostty 的常用快捷键，方便用户记忆和使用。
# 例如，用户可以输入 `gtykeys` 来查看 Ghostty 的快捷键列表。
function ghostty_keybinds() {
  echo
  color_echo green "============================================================"
  color_echo green "   Ghostty Keybindings Helper   "
  color_echo green "   Common Shortcuts for Ghostty "
  color_echo green "============================================================"
  echo
  color_echo yellow " <CMD+T>       : Open a new terminal tab"
  color_echo yellow " <CMD+W>       : Close the current terminal tab"
  color_echo yellow " <CMD+Shift+[> : Move the current tab to the left"
  color_echo yellow " <CMD+Shift+]> : Move the current tab to the right"
  color_echo yellow " <CMD+[>       : Move to the previous split pane"
  color_echo yellow " <CMD+]>       : Move to the next split pane"
  color_echo yellow " <CMD+~>       : Toggle quick terminal"
  color_echo green "============================================================"
}

alias gtykeys='ghostty_keybinds'
