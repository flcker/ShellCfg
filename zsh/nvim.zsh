################################################################################
# nvim
# alias vim/vi
if command -v nvim >/dev/null 2>&1; then
    # 加载 submodule 中的 nvim 配置 `../submodule/nvim/init.lua`
    # SKIP_NVIM_SUBMODULE=1 可跳过子模块配置
    function nvim_fun() {
        local cfg="${ZSH_CONFIG_NVIM_DIR}/init.lua"
        if [[ -f "$cfg" && "$SKIP_NVIM_SUBMODULE" != "1" ]]; then
            command nvim -u "$cfg" "$@"
        else
            command nvim "$@"
        fi
    }

    alias nvim='nvim_fun'
    alias vim='nvim_fun'
    alias vi='nvim_fun'
fi
