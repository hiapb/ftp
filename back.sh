#!/usr/bin/env bash

# ===================== 基本变量 =====================
CONFIG_DIR="$HOME/.ftp_backup_tool"
CONFIG_FILE="$CONFIG_DIR/ftp.conf"
TAG="# FTP_BACKUP"
SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"

mkdir -p "$CONFIG_DIR"

# ===================== 工具函数 =====================
pause() {
    echo
    read -rp "🔸 按回车键继续..." _
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ensure_command <cmd> <deb_pkg> <rhel_pkg> <other_pkg>
ensure_command() {
    local cmd="$1"
    local deb_pkg="$2"
    local rhel_pkg="$3"
    local other_pkg="$4"

    if command_exists "$cmd"; then
        return 0
    fi

    echo "⚙️  未检测到依赖：$cmd，尝试自动安装..."

    if command_exists apt-get; then
        # Debian / Ubuntu / Deepin 等
        local pkg="${deb_pkg:-$cmd}"
        echo "📦 使用 apt-get 安装：$pkg"
        sudo apt-get update && sudo apt-get install -y "$pkg"
    elif command_exists yum; then
        # CentOS / AlmaLinux / Rocky 等
        local pkg="${rhel_pkg:-$cmd}"
        echo "📦 使用 yum 安装：$pkg"
        sudo yum install -y "$pkg"
    elif command_exists dnf; then
        # 新一点的 RHEL 系
        local pkg="${rhel_pkg:-$cmd}"
        echo "📦 使用 dnf 安装：$pkg"
        sudo dnf install -y "$pkg"
    elif command_exists zypper; then
        local pkg="${other_pkg:-$cmd}"
        echo "📦 使用 zypper 安装：$pkg"
        sudo zypper install -y "$pkg"
    elif command_exists pacman; then
        local pkg="${other_pkg:-$cmd}"
        echo "📦 使用 pacman 安装：$pkg"
        sudo pacman -Sy --noconfirm "$pkg"
    else
        echo "❌ 未找到适配的包管理器，请手动安装：$cmd"
        return 1
    fi

    if command_exists "$cmd"; then
        echo "✅ $cmd 安装成功。"
        return 0
    else
        echo "❌ 自动安装 $cmd 失败，请手动安装后重试。"
        return 1
    fi
}

check_dependencies() {
    # lftp：各大发行版包名基本一样
    ensure_command lftp lftp lftp lftp || exit 1

    # crontab 命令：Debian 系 cron，RHEL 系 cronie
    # 这里即使安装失败也不退出，只要系统本身已经有 cron 就行
    ensure_command crontab cron cronie cron || true
}

# ===================== FTP 配置 =====================
is_ftp_configured() {
    [[ -f "$CONFIG_FILE" ]]
}

load_ftp_config() {
    if is_ftp_configured; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
    fi
}

config_ftp() {
    echo "────────────────────────────────"
    echo "🔑 配置 FTP 账号"
    echo "────────────────────────────────"
    read -rp "🌐 FTP 主机 (例如 ftp.example.com)： " FTP_HOST
    read -rp "🔢 FTP 端口 (默认 21，回车使用默认)： " FTP_PORT
    FTP_PORT=${FTP_PORT:-21}
    read -rp "👤 FTP 用户名： " FTP_USER
    read -rsp "🔒 FTP 密码（输入时不显示）： " FTP_PASS
    echo

    cat > "$CONFIG_FILE" <<EOF
FTP_HOST="$FTP_HOST"
FTP_PORT="$FTP_PORT"
FTP_USER="$FTP_USER"
FTP_PASS="$FTP_PASS"
EOF

    chmod 600 "$CONFIG_FILE"
    echo "✅ FTP 配置已保存到：$CONFIG_FILE"
    pause
}

# ===================== 备份执行逻辑（给定参数时执行） =====================
run_backup() {
    local LOCAL_PATH="$1"
    local REMOTE_DIR="$2"

    load_ftp_config

    if [[ -z "$FTP_HOST" || -z "$FTP_USER" || -z "$FTP_PASS" ]]; then
        echo "❌ FTP 配置不完整，请先在菜单中配置 FTP 账号。"
        exit 1
    fi

    if [[ ! -e "$LOCAL_PATH" ]]; then
        echo "❌ 本地路径不存在：$LOCAL_PATH"
        exit 1
    fi

    echo "🚀 开始备份："
    echo "  📁 本地路径：$LOCAL_PATH"
    echo "  📂 FTP 目标目录：$REMOTE_DIR"

    if [[ -d "$LOCAL_PATH" ]]; then
        # 目录 用 mirror -R
        lftp -u "$FTP_USER","$FTP_PASS" -p "$FTP_PORT" "$FTP_HOST" <<EOF
set ssl:verify-certificate no
mkdir -p "$REMOTE_DIR"
mirror -R "$LOCAL_PATH" "$REMOTE_DIR"
bye
EOF
    else
        # 文件 用 put
        local filename
        filename="$(basename "$LOCAL_PATH")"
        lftp -u "$FTP_USER","$FTP_PASS" -p "$FTP_PORT" "$FTP_HOST" <<EOF
set ssl:verify-certificate no
mkdir -p "$REMOTE_DIR"
cd "$REMOTE_DIR"
put "$LOCAL_PATH" -o "$filename"
bye
EOF
    fi

    if [[ $? -eq 0 ]]; then
        echo "✅ 备份完成。"
    else
        echo "❌ 备份失败，请检查网络与配置。"
    fi
}

# ===================== 定时任务相关 =====================
add_cron_job() {
    local CRON_EXPR="$1"
    local LOCAL_PATH="$2"
    local REMOTE_DIR="$3"

    # 将本地/远程路径中的双引号替换成转义形式，避免破坏 crontab 格式
    LOCAL_ESC=${LOCAL_PATH//\"/\\\"}
    REMOTE_ESC=${REMOTE_DIR//\"/\\\"}

    local CRON_LINE="$CRON_EXPR bash $SCRIPT_PATH run \"$LOCAL_ESC\" \"$REMOTE_ESC\" $TAG"

    (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -

    echo "✅ 定时任务已添加："
    echo "   $CRON_LINE"
    pause
}

list_cron_jobs() {
    echo "────────────────────────────────"
    echo "📋 当前备份任务"
    echo "────────────────────────────────"
    local lines
    lines=$(crontab -l 2>/dev/null | grep "$TAG" || true)

    if [[ -z "$lines" ]]; then
        echo "ℹ️  当前没有任何 FTP 备份定时任务。"
        pause
        return
    fi

    local i=1
    while IFS= read -r line; do
        echo "[$i] $line"
        i=$((i + 1))
    done <<< "$lines"

    pause
}

delete_cron_job() {
    echo "────────────────────────────────"
    echo "🗑 删除备份任务"
    echo "────────────────────────────────"
    local lines
    lines=$(crontab -l 2>/dev/null | grep "$TAG" || true)

    if [[ -z "$lines" ]]; then
        echo "ℹ️  没有可删除的备份任务。"
        pause
        return
    fi

    local i=1
    declare -a JOBS
    while IFS= read -r line; do
        JOBS[$i]="$line"
        echo "[$i] $line"
        i=$((i + 1))
    done <<< "$lines"

    read -rp "🔢 请输入要删除的任务编号： " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ -z "${JOBS[$choice]}" ]]; then
        echo "❌ 输入的编号无效。"
        pause
        return
    fi

    local target="${JOBS[$choice]}"

    crontab -l 2>/dev/null | grep -vF "$target" | crontab -

    echo "✅ 已删除任务：$target"
    pause
}

add_backup_job() {
    echo "────────────────────────────────"
    echo "➕ 新建备份任务"
    echo "────────────────────────────────"
    echo "⚠️  注意：为了避免转义问题，暂不支持路径中包含空格。"
    read -rp "📁 请输入要备份的本地文件/目录路径： " LOCAL_PATH

    if [[ "$LOCAL_PATH" =~ \  ]]; then
        echo "❌ 路径中包含空格，目前不支持，请换一个路径（可用软链接等方式）。"
        pause
        return
    fi

    if [[ ! -e "$LOCAL_PATH" ]]; then
        echo "❌ 该路径不存在，请确认后重新在菜单中添加。"
        pause
        return
    fi

    read -rp "📂 请输入 FTP 目标目录（例如 /backup/www 或 backup）： " REMOTE_DIR

    if [[ -z "$REMOTE_DIR" ]]; then
        echo "❌ FTP 目标目录不能为空。"
        pause
        return
    fi

    echo
    echo "⏱ 请选择定时方式："
    echo "  1) 🕒 每天固定时间备份"
    echo "  2) 🔁 每隔 N 分钟备份"
    read -rp "👉 请输入选项编号： " mode

    local CRON_EXPR=""

    case "$mode" in
        1)
            read -rp "🕒 每天几点（0-23）： " H
            read -rp "🕒 每天几分（0-59）： " M
            if ! [[ "$H" =~ ^[0-9]+$ ]] || ! [[ "$M" =~ ^[0-9]+$ ]] || ((H < 0 || H > 23)) || ((M < 0 || M > 59)); then
                echo "❌ 时间输入不合法。"
                pause
                return
            fi
            CRON_EXPR="$M $H * * *"
            ;;
        2)
            read -rp "🔁 每隔多少分钟执行一次（1-59）： " N
            if ! [[ "$N" =~ ^[0-9]+$ ]] || ((N < 1 || N > 59)); then
                echo "❌ 输入不合法。"
                pause
                return
            fi
            CRON_EXPR="*/$N * * * *"
            ;;
        *)
            echo "❌ 无效的选项。"
            pause
            return
            ;;
    esac

    add_cron_job "$CRON_EXPR" "$LOCAL_PATH" "$REMOTE_DIR"
}

uninstall_all() {
    echo "────────────────────────────────"
    echo "🧹 卸载工具"
    echo "────────────────────────────────"
    read -rp "⚠️  确定要卸载吗？这会删除所有 FTP 配置和本工具创建的定时任务。(y/N)： " ans
    case "$ans" in
        y|Y)
            # 删除带标记的 crontab 任务
            local current
            current=$(crontab -l 2>/dev/null || true)
            if [[ -n "$current" ]]; then
                echo "$current" | grep -v "$TAG" | crontab -
            fi

            # 删除配置目录
            rm -rf "$CONFIG_DIR"

            echo "✅ 卸载完成（已删除 FTP 配置和相关定时任务）。"
            ;;
        *)
            echo "ℹ️  已取消卸载。"
            ;;
    esac
    pause
}

# ===================== 主菜单 =====================
show_menu() {
    clear
    echo "======================================="
    echo "🌐 FTP 备份工具"
    echo "======================================="
    echo

    if is_ftp_configured; then
        echo "🔐 FTP 状态：已配置 ✅"
    else
        echo "🔐 FTP 状态：未配置 ❌（请先配置）"
    fi
    echo

    echo "1) 🔑 配置 / 修改 FTP 账号"
    echo "2) ➕ 新建备份任务"
    echo "3) 📋 查看备份任务"
    echo "4) 🗑 删除备份任务"
    echo "5) 🧹 卸载"
    echo "0) ❎ 退出"
    echo
    read -rp "👉 请输入选项编号： " choice

    # 没有 FTP 配置时，只允许选 1、5、0
    if ! is_ftp_configured && [[ "$choice" != "1" && "$choice" != "5" && "$choice" != "0" ]]; then
        echo
        echo "⚠️  当前尚未配置 FTP 账号，请先进行配置。"
        pause
        return
    fi

    case "$choice" in
        1) config_ftp ;;
        2) add_backup_job ;;
        3) list_cron_jobs ;;
        4) delete_cron_job ;;
        5) uninstall_all ;;
        0) exit 0 ;;
        *) echo "❌ 无效选项。"; pause ;;
    esac
}

# ===================== 入口逻辑 =====================

# 如果以参数方式调用：用于 crontab 定时执行
if [[ "$1" == "run" ]]; then
    # run <LOCAL_PATH> <REMOTE_DIR>
    run_backup "$2" "$3"
    exit $?
fi

# 普通交互模式
check_dependencies

while true; do
    show_menu
done
