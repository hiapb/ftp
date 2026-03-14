#!/usr/bin/env bash

CONFIG_DIR="$HOME/.ftp_backup_tool"
ACCOUNTS_DIR="$CONFIG_DIR/accounts"
CONFIG_FILE="$CONFIG_DIR/ftp.conf"
TAG="# FTP_BACKUP"

RAW_SCRIPT_PATH="$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")"
SCRIPT_PATH="$RAW_SCRIPT_PATH"

SCRIPT_URL="https://raw.githubusercontent.com/hiapb/ftp/main/back.sh"
INSTALL_PATH="/root/back.sh"

mkdir -p "$ACCOUNTS_DIR"

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

normalize_script_path() {
    if [[ "$SCRIPT_PATH" == /dev/fd/* ]] || [[ "$SCRIPT_PATH" == /proc/*/fd/* ]] || [[ "$SCRIPT_PATH" == *"pipe:"* ]]; then
        if [[ ! -f "$INSTALL_PATH" ]]; then
            echo "📥 检测到通过 bash <(curl ...) 运行，正在自动安装脚本到：$INSTALL_PATH"
            if command_exists curl; then
                curl -fsSL "$SCRIPT_URL" -o "$INSTALL_PATH" || cat "$RAW_SCRIPT_PATH" > "$INSTALL_PATH"
            elif command_exists wget; then
                wget -qO "$INSTALL_PATH" "$SCRIPT_URL" || cat "$RAW_SCRIPT_PATH" > "$INSTALL_PATH"
            else
                cat "$RAW_SCRIPT_PATH" > "$INSTALL_PATH"
            fi
            chmod +x "$INSTALL_PATH"
            echo "✅ 安装完成，以后 crontab 将使用：$INSTALL_PATH"
        fi
        SCRIPT_PATH="$INSTALL_PATH"
    fi
}

normalize_script_path

pause() {
    echo
    read -rp "🔸 按回车键继续..." _
}

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
        local pkg="${deb_pkg:-$cmd}"
        echo "📦 使用 apt-get 安装：$pkg"
        sudo apt-get update && sudo apt-get install -y "$pkg"
    elif command_exists yum; then
        local pkg="${rhel_pkg:-$cmd}"
        echo "📦 使用 yum 安装：$pkg"
        sudo yum install -y "$pkg"
    elif command_exists dnf; then
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
    ensure_command lftp lftp lftp lftp || exit 1
    ensure_command crontab cron cronie cron || true
}

is_ftp_configured() {
    shopt -s nullglob
    local files=("$ACCOUNTS_DIR"/*.conf)
    shopt -u nullglob
    [[ ${#files[@]} -gt 0 ]]
}

get_ftp_count() {
    shopt -s nullglob
    local files=("$ACCOUNTS_DIR"/*.conf)
    shopt -u nullglob
    echo ${#files[@]}
}

load_ftp_account() {
    local account_id="$1"
    local file="$ACCOUNTS_DIR/$account_id.conf"
    if [[ ! -f "$file" ]]; then
        echo "❌ 找不到账号配置：$account_id"
        return 1
    fi
    source "$file"
    FTP_PROTO="${FTP_PROTO:-ftp}"
}

proto_to_type() {
    local proto="$1"
    case "$proto" in
        ftp)  echo "FTP" ;;
        ftps) echo "FTPS" ;;
        sftp) echo "SFTP" ;;
        *)    echo "$proto" ;;
    esac
}

add_ftp_account() {
    echo "────────────────────────────────"
    echo "➕ 新增 FTP/SFTP 账号"
    echo "────────────────────────────────"

    echo "🔐 请选择连接类型："
    echo "  1) FTP"
    echo "  2) FTPS"
    echo "  3) SFTP"
    read -rp "👉 请输入选项编号（默认 1）： " proto_choice
    case "$proto_choice" in
        2) FTP_PROTO="ftps" ;;
        3) FTP_PROTO="sftp" ;;
        *) FTP_PROTO="ftp" ;;
    esac
    local TYPE_LABEL
    TYPE_LABEL="$(proto_to_type "$FTP_PROTO")"

    read -rp "📝 为此账号起一个名称（例如 main、backup1）： " ACCOUNT_ID
    ACCOUNT_ID="${ACCOUNT_ID// /_}"

    if [[ -z "$ACCOUNT_ID" ]]; then
        echo "❌ 账号名称不能为空。"
        pause
        return
    fi

    local file="$ACCOUNTS_DIR/$ACCOUNT_ID.conf"
    if [[ -f "$file" ]]; then
        echo "⚠️  已存在同名账号配置，将覆盖该账号。"
    fi

    read -rp "🌐 远程主机 (例如 ftp.example.com 或 sftp.example.com)： " FTP_HOST

    local default_port
    case "$FTP_PROTO" in
        sftp) default_port=22 ;;
        *)    default_port=21 ;;
    esac
    read -rp "🔢 远程端口 (默认 $default_port，回车使用默认)： " FTP_PORT
    FTP_PORT=${FTP_PORT:-$default_port}

    read -rp "👤 用户名： " FTP_USER
    read -rp "🔒 密码： " FTP_PASS

    ESCAPED_PASS=${FTP_PASS//\\/\\\\}
    ESCAPED_PASS=${ESCAPED_PASS//\"/\\\"}
    ESCAPED_PASS=${ESCAPED_PASS//$/\\$}

    cat > "$file" <<EOF
ACCOUNT_ID="$ACCOUNT_ID"
FTP_HOST="$FTP_HOST"
FTP_PORT="$FTP_PORT"
FTP_USER="$FTP_USER"
FTP_PASS="$ESCAPED_PASS"
FTP_PROTO="$FTP_PROTO"
EOF

    chmod 600 "$file"
    echo "✅ 新账号已保存：$ACCOUNT_ID （类型：$TYPE_LABEL，主机：$FTP_HOST，端口：$FTP_PORT）"
    pause
}

show_ftp_accounts() {
    echo "────────────────────────────────"
    echo "📂 账号列表"
    echo "────────────────────────────────"

    shopt -s nullglob
    local files=("$ACCOUNTS_DIR"/*.conf)
    shopt -u nullglob

    if [[ ${#files[@]} -eq 0 ]]; then
        echo "ℹ️  当前没有任何账号配置。"
        pause
        return
    fi

    local i=1
    for f in "${files[@]}"; do
        source "$f"
        local proto="${FTP_PROTO:-ftp}"
        local type
        type="$(proto_to_type "$proto")"
        echo "[$i] 账号名：$ACCOUNT_ID  | 类型：$type  | 主机：$FTP_HOST  | 端口：$FTP_PORT  | 用户：$FTP_USER"
        i=$((i+1))
    done

    pause
}

delete_ftp_account() {
    echo "────────────────────────────────"
    echo "🗑 删除账号"
    echo "────────────────────────────────"

    shopt -s nullglob
    local files=("$ACCOUNTS_DIR"/*.conf)
    shopt -u nullglob

    if [[ ${#files[@]} -eq 0 ]]; then
        echo "ℹ️  当前没有可删除的账号。"
        pause
        return
    fi

    local i=1
    declare -a ACCOUNT_IDS
    for f in "${files[@]}"; do
        source "$f"
        ACCOUNT_IDS[$i]="$ACCOUNT_ID"
        local type
        type="$(proto_to_type "${FTP_PROTO:-ftp}")"
        echo "[$i] 账号名：$ACCOUNT_ID  | 类型：$type  | 主机：$FTP_HOST"
        i=$((i+1))
    done

    read -rp "🔢 请输入要删除的账号编号： " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ -z "${ACCOUNT_IDS[$choice]}" ]]; then
        echo "❌ 输入编号无效。"
        pause
        return
    fi

    local target_id="${ACCOUNT_IDS[$choice]}"
    local file="$ACCOUNTS_DIR/$target_id.conf"

    read -rp "⚠️  确认删除账号 [$target_id] 以及其所有备份任务吗？(y/N)： " yn
    case "$yn" in
        y|Y)
            rm -f "$file"
            if command_exists crontab; then
                local current
                current=$(crontab -l 2>/dev/null || true)
                if [[ -n "$current" ]]; then
                    echo "$current" | grep -v "$TAG\[$target_id\]" | crontab -
                fi
            fi
            echo "✅ 已删除账号 [$target_id] 及其相关定时任务。"
            ;;
        *)
            echo "ℹ️  已取消删除。"
            ;;
    esac
    pause
}

CHOSEN_ACCOUNT_ID=""

select_ftp_account() {
    shopt -s nullglob
    local files=("$ACCOUNTS_DIR"/*.conf)
    shopt -u nullglob

    if [[ ${#files[@]} -eq 0 ]]; then
        echo "❌ 当前没有账号，请先添加。"
        return 1
    fi

    echo "────────────────────────────────"
    echo "📂 可用账号列表："
    echo "────────────────────────────────"

    local i=1
    declare -a ACCOUNT_IDS
    for f in "${files[@]}"; do
        source "$f"
        local proto="${FTP_PROTO:-ftp}"
        local type
        type="$(proto_to_type "$proto")"
        ACCOUNT_IDS[$i]="$ACCOUNT_ID"
        echo "[$i] 账号名：$ACCOUNT_ID  | 类型：$type  | 主机：$FTP_HOST:$FTP_PORT"
        i=$((i+1))
    done

    echo
    read -rp "👉 请输入账号编号： " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ -z "${ACCOUNT_IDS[$choice]}" ]]; then
        echo "❌ 输入编号无效。"
        return 1
    fi

    CHOSEN_ACCOUNT_ID="${ACCOUNT_IDS[$choice]}"
    return 0
}

build_ssl_lines() {
    local proto="$1"
    if [[ "$proto" == "ftps" ]]; then
        printf '%s\n' \
            "set ftp:ssl-force true" \
            "set ftp:ssl-protect-data true" \
            "set ftp:ssl-auth TLS"
    else
        :
    fi
}

build_sftp_lines() {
    local proto="$1"
    if [[ "$proto" == "sftp" ]]; then
        printf '%s\n' \
            "set sftp:auto-confirm yes" \
            "set net:timeout 15" \
            "set net:max-retries 2" \
            "set net:persist-retries 0" \
            "set sftp:connect-program \"ssh -a -x -p $FTP_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null\""
    else
        :
    fi
}

get_lftp_target() {
    local proto="$1"
    local host="$2"

    if [[ "$proto" == "sftp" ]]; then
        echo "sftp://$host"
    else
        echo "$host"
    fi
}

browse_ftp_with_account() {
    CHOSEN_ACCOUNT_ID=""
    select_ftp_account || { pause; return; }
    local ACCOUNT_ID="$CHOSEN_ACCOUNT_ID"

    load_ftp_account "$ACCOUNT_ID" || { pause; return; }

    while true; do
        clear
        local proto_label="${FTP_PROTO:-ftp}"
        local type_label
        type_label="$(proto_to_type "$proto_label")"
        echo "======================================="
        echo "🔍 远程浏览 / 下载 / 删除"
        echo "======================================="
        echo "当前账号：$ACCOUNT_ID  ($type_label, $FTP_USER@$FTP_HOST:$FTP_PORT)"
        echo
        echo "1) 📁 列出某个远程目录内容"
        echo "2) 📥 下载远程文件到本地"
        echo "3) 📥 下载远程目录到本地"
        echo "4) ❌ 删除远程文件"
        echo "5) ⚠️ 删除远程目录"
        echo "0) ⬅ 返回上一层"
        echo
        read -rp "👉 请输入选项编号： " sub

        case "$sub" in
            1)
                read -rp "📂 请输入要查看的远程目录（例如 / 或 /backup/www）： " REMOTE_DIR
                if [[ -z "$REMOTE_DIR" ]]; then
                    echo "❌ 远程目录不能为空。"
                    pause
                    continue
                fi
                echo "📋 $REMOTE_DIR 下的内容："
                echo "────────────────────────────────"
                SSL_LINES="$(build_ssl_lines "$FTP_PROTO")"
                SFTP_LINES="$(build_sftp_lines "$FTP_PROTO")"
                LFTP_TARGET="$(get_lftp_target "$FTP_PROTO" "$FTP_HOST")"
                SSL_VERIFY_LINE=""
                if [[ "$FTP_PROTO" != "sftp" ]]; then
                    SSL_VERIFY_LINE="set ssl:verify-certificate no"
                fi
lftp -u "$FTP_USER","$FTP_PASS" -p "$FTP_PORT" "$LFTP_TARGET" <<EOF | awk '!($NF=="." || $NF=="..")'
$SSL_VERIFY_LINE
$SSL_LINES
$SFTP_LINES
cd "$REMOTE_DIR" || cd .
ls
bye
EOF
                echo "────────────────────────────────"
                pause
                ;;
            2)
                read -rp "📂 请输入远程文件所在目录（例如 / 或 /backup/www）： " RDIR
                read -rp "📄 请输入远程文件名（例如 index.html）： " RFN
                read -rp "📁 请输入下载到本地的目录（例如 /root/download）： " LDIR

                if [[ -z "$RDIR" || -z "$RFN" || -z "$LDIR" ]]; then
                    echo "❌ 目录、文件名和本地目录都不能为空。"
                    pause
                    continue
                fi

                mkdir -p "$LDIR"

                if [[ "$RDIR" == "/" ]]; then
                    NORMALIZED_RDIR=""
                    DISPLAY_RDIR="/"
                else
                    NORMALIZED_RDIR="${RDIR%/}"
                    DISPLAY_RDIR="$NORMALIZED_RDIR"
                fi

                read -rp "⚠️ 确认下载文件 $DISPLAY_RDIR/$RFN 到本地 $LDIR 并自动覆盖同名文件吗？(y/N)： " yn_dl
                case "$yn_dl" in
                    y|Y)
                        SSL_LINES="$(build_ssl_lines "$FTP_PROTO")"
                        SFTP_LINES="$(build_sftp_lines "$FTP_PROTO")"
                        LFTP_TARGET="$(get_lftp_target "$FTP_PROTO" "$FTP_HOST")"
                        SSL_VERIFY_LINE=""
                        if [[ "$FTP_PROTO" != "sftp" ]]; then
                            SSL_VERIFY_LINE="set ssl:verify-certificate no"
                        fi

                        if [[ -n "$NORMALIZED_RDIR" ]]; then
                            CD_CMD="cd \"$NORMALIZED_RDIR\" || exit 1"
                        else
                            CD_CMD=""
                        fi
lftp -u "$FTP_USER","$FTP_PASS" -p "$FTP_PORT" "$LFTP_TARGET" <<EOF
$SSL_VERIFY_LINE
$SSL_LINES
$SFTP_LINES
$CD_CMD
get "$RFN" -o "$LDIR/$RFN"
bye
EOF
                        if [[ $? -eq 0 ]]; then
                            echo "✅ 文件已下载到：$LDIR/$RFN"
                        else
                            echo "❌ 下载失败，请检查路径和权限。"
                        fi
                        pause
                        ;;
                    *)
                        echo "ℹ️ 已取消下载。"
                        pause
                        ;;
                esac
                ;;
            3)
                read -rp "📂 请输入要下载的远程目录路径（例如 / 或 /test）： " RDIR
                read -rp "📁 请输入下载到本地的目录（例如 /root/download）： " LDIR

                if [[ -z "$RDIR" || -z "$LDIR" ]]; then
                    echo "❌ 远程目录和本地目录都不能为空。"
                    pause
                    continue
                fi

                mkdir -p "$LDIR"

                if [[ "$RDIR" == "/" ]]; then
                    SRC_DIR="."
                    DISPLAY_SRC="/"
                else
                    SRC_DIR="${RDIR%/}"
                    DISPLAY_SRC="$SRC_DIR"
                fi

                read -rp "⚠️ 确认下载整个目录 $DISPLAY_SRC 到本地 $LDIR 吗？(y/N)： " yn_dir
                case "$yn_dir" in
                    y|Y)
                        SSL_LINES="$(build_ssl_lines "$FTP_PROTO")"
                        SFTP_LINES="$(build_sftp_lines "$FTP_PROTO")"
                        LFTP_TARGET="$(get_lftp_target "$FTP_PROTO" "$FTP_HOST")"
                        SSL_VERIFY_LINE=""
                        if [[ "$FTP_PROTO" != "sftp" ]]; then
                            SSL_VERIFY_LINE="set ssl:verify-certificate no"
                        fi
lftp -u "$FTP_USER","$FTP_PASS" -p "$FTP_PORT" "$LFTP_TARGET" <<EOF
$SSL_VERIFY_LINE
$SSL_LINES
$SFTP_LINES
mirror "$SRC_DIR" "$LDIR"
bye
EOF
                        if [[ $? -eq 0 ]]; then
                            echo "✅ 目录已成功下载到：$LDIR"
                        else
                            echo "❌ 目录下载失败，请检查路径和权限。"
                        fi
                        pause
                        ;;
                    *)
                        echo "ℹ️ 已取消目录下载。"
                        pause
                        ;;
                esac
                ;;
            4)
                read -rp "📂 请输入文件所在远程目录（例如 / 或 /backup/www）： " REMOTE_DIR
                read -rp "📄 请输入要删除的文件名（例如 index.html）： " REMOTE_FILE

                if [[ -z "$REMOTE_FILE" ]]; then
                    echo "❌ 文件名不能为空。"
                    pause
                    continue
                fi

                if [[ -z "$REMOTE_DIR" ]]; then
                    echo "❌ 目录不能为空。"
                    pause
                    continue
                fi

                if [[ "$REMOTE_DIR" == "/" ]]; then
                    NORMALIZED_DIR=""
                    DISPLAY_PATH="/$REMOTE_FILE"
                else
                    NORMALIZED_DIR="${REMOTE_DIR%/}"
                    DISPLAY_PATH="$NORMALIZED_DIR/$REMOTE_FILE"
                fi

                read -rp "⚠️ 确认要删除文件 $DISPLAY_PATH 吗？(y/N)： " yn
                case "$yn" in
                    y|Y)
                        SSL_LINES="$(build_ssl_lines "$FTP_PROTO")"
                        SFTP_LINES="$(build_sftp_lines "$FTP_PROTO")"
                        LFTP_TARGET="$(get_lftp_target "$FTP_PROTO" "$FTP_HOST")"
                        SSL_VERIFY_LINE=""
                        if [[ "$FTP_PROTO" != "sftp" ]]; then
                            SSL_VERIFY_LINE="set ssl:verify-certificate no"
                        fi

                        if [[ -n "$NORMALIZED_DIR" ]]; then
                            CD_CMD="cd \"$NORMALIZED_DIR\" || exit 1"
                        else
                            CD_CMD=""
                        fi
lftp -u "$FTP_USER","$FTP_PASS" -p "$FTP_PORT" "$LFTP_TARGET" <<EOF
$SSL_VERIFY_LINE
$SSL_LINES
$SFTP_LINES
$CD_CMD
rm -r "$REMOTE_FILE"
bye
EOF
                        if [[ $? -eq 0 ]]; then
                            echo "✅ 已删除远程文件：$DISPLAY_PATH"
                        else
                            echo "❌ 删除失败，请检查路径和权限。"
                        fi
                        pause
                        ;;
                    *)
                        echo "ℹ️ 已取消删除。"
                        pause
                        ;;
                esac
                ;;
            5)
                read -rp "📂 请输入要删除的远程目录（例如 / 或 /backup/tmp）： " REMOTE_DIR
                if [[ -z "$REMOTE_DIR" ]]; then
                    echo "❌ 远程目录不能为空。"
                    pause
                    continue
                fi
                if [[ "$REMOTE_DIR" == "/" ]]; then
                    echo "❌ 出于安全考虑，不支持直接删除账号根目录，请指定子目录。"
                    pause
                    continue
                fi
                NORMALIZED_DIR="${REMOTE_DIR%/}"
                read -rp "⚠️ 确认删除整个目录 $NORMALIZED_DIR 吗？此操作不可恢复！(y/N)： " yn2
                case "$yn2" in
                    y|Y)
                        SSL_LINES="$(build_ssl_lines "$FTP_PROTO")"
                        SFTP_LINES="$(build_sftp_lines "$FTP_PROTO")"
                        LFTP_TARGET="$(get_lftp_target "$FTP_PROTO" "$FTP_HOST")"
                        SSL_VERIFY_LINE=""
                        if [[ "$FTP_PROTO" != "sftp" ]]; then
                            SSL_VERIFY_LINE="set ssl:verify-certificate no"
                        fi
lftp -u "$FTP_USER","$FTP_PASS" -p "$FTP_PORT" "$LFTP_TARGET" <<EOF
$SSL_VERIFY_LINE
$SSL_LINES
$SFTP_LINES
rm -r "$NORMALIZED_DIR"
bye
EOF
                        if [[ $? -eq 0 ]]; then
                            echo "✅ 已删除远程目录：$NORMALIZED_DIR"
                        else
                            echo "❌ 删除失败，请检查路径和权限。"
                        fi
                        pause
                        ;;
                    *)
                        echo "ℹ️ 已取消删除目录操作。"
                        pause
                        ;;
                esac
                ;;
            0)
                break
                ;;
            *)
                echo "❌ 无效选项。"
                pause
                ;;
        esac
    done
}

edit_ftp_account() {
    echo "────────────────────────────────"
    echo "✏️ 修改账号"
    echo "────────────────────────────────"

    CHOSEN_ACCOUNT_ID=""
    select_ftp_account || { pause; return; }
    local ACCOUNT_ID="$CHOSEN_ACCOUNT_ID"
    local file="$ACCOUNTS_DIR/$ACCOUNT_ID.conf"

    load_ftp_account "$ACCOUNT_ID" || { pause; return; }

    # 确保默认值
    FTP_PROTO="${FTP_PROTO:-ftp}"
    FTP_HOST="${FTP_HOST:-}"
    FTP_PORT="${FTP_PORT:-}"
    FTP_USER="${FTP_USER:-}"
    FTP_PASS="${FTP_PASS:-}"

    while true; do
        clear
        echo "======================================="
        echo "✏️ 正在修改账号：$ACCOUNT_ID"
        echo "======================================="
        echo "[1] 连接类型：$(proto_to_type "$FTP_PROTO")"
        echo "[2] 远程主机：$FTP_HOST"
        echo "[3] 远程端口：$FTP_PORT"
        echo "[4] 用户名  ：$FTP_USER"
        echo "[5] 密码    ：(已隐藏)"
        echo "[6] 保存并退出"
        echo "[0] 不保存退出"
        echo

        read -rp "👉 请选择要修改的项： " op
        case "$op" in
            1)
                echo "🔐 请选择连接类型："
                echo "  1) FTP"
                echo "  2) FTPS"
                echo "  3) SFTP"
                read -rp "👉 请输入选项编号（回车取消）： " p
                case "$p" in
                    1) FTP_PROTO="ftp" ;;
                    2) FTP_PROTO="ftps" ;;
                    3) FTP_PROTO="sftp" ;;
                    "") ;;
                    *) echo "❌ 无效选项"; sleep 1 ;;
                esac

                # 如果端口为空，按协议给个合理默认
                if [[ -z "$FTP_PORT" ]]; then
                    case "$FTP_PROTO" in
                        sftp) FTP_PORT=22 ;;
                        *)    FTP_PORT=21 ;;
                    esac
                fi
                ;;
            2)
                read -rp "🌐 输入新主机（回车取消）： " v
                [[ -n "$v" ]] && FTP_HOST="$v"
                ;;
            3)
                read -rp "🔢 输入新端口（回车取消）： " v
                if [[ -n "$v" ]]; then
                    if [[ "$v" =~ ^[0-9]+$ ]] && (( v >= 1 && v <= 65535 )); then
                        FTP_PORT="$v"
                    else
                        echo "❌ 端口必须是 1-65535 的数字"
                        sleep 1
                    fi
                fi
                ;;
            4)
                read -rp "👤 输入新用户名（回车取消）： " v
                [[ -n "$v" ]] && FTP_USER="$v"
                ;;
            5)
                read -rp "🔒 输入新密码（回车取消）： " v
                [[ -n "$v" ]] && FTP_PASS="$v"
                ;;
            6)
                # 保存：复用你原来的密码转义逻辑
                local ESCAPED_PASS
                ESCAPED_PASS=${FTP_PASS//\\/\\\\}
                ESCAPED_PASS=${ESCAPED_PASS//\"/\\\"}
                ESCAPED_PASS=${ESCAPED_PASS//$/\\$}

                cat > "$file" <<EOF
ACCOUNT_ID="$ACCOUNT_ID"
FTP_HOST="$FTP_HOST"
FTP_PORT="$FTP_PORT"
FTP_USER="$FTP_USER"
FTP_PASS="$ESCAPED_PASS"
FTP_PROTO="$FTP_PROTO"
EOF
                chmod 600 "$file"
                echo "✅ 已保存：$file"
                pause
                return
                ;;
            0)
                echo "ℹ️ 未保存，已退出。"
                pause
                return
                ;;
            *)
                echo "❌ 无效选项"
                sleep 1
                ;;
        esac
    done
}

ftp_account_menu() {
    while true; do
        clear
        echo "======================================="
        echo "📂 账号管理"
        echo "======================================="
        echo "当前账号数量：$(get_ftp_count)"
        echo
        echo "1) ➕ 新增账号"
        echo "2) ✏️ 修改账号"
        echo "3) 📋 查看账号列表"
        echo "4) 🗑 删除账号"
        echo "5) 🔍 使用账号浏览/下载/删除远程文件"
        echo "0) ⬅ 返回主菜单"

        echo
        read -rp "👉 请输入选项编号： " choice

        case "$choice" in
            1) add_ftp_account ;;
            2) edit_ftp_account ;;
            3) show_ftp_accounts ;;
            4) delete_ftp_account ;;
            5) browse_ftp_with_account ;;
            0) break ;;
            *) echo "❌ 无效选项。"; pause ;;
        esac
    done
}

run_backup() {
    local ACCOUNT_ID="$1"
    local LOCAL_PATH="$2"
    local REMOTE_DIR="$3"

    load_ftp_account "$ACCOUNT_ID" || return 1

    if [[ ! -e "$LOCAL_PATH" ]]; then
        echo "❌ 本地路径不存在：$LOCAL_PATH"
        return 1
    fi

    local type_label
    type_label="$(proto_to_type "${FTP_PROTO:-ftp}")"

    echo "🚀 开始备份："
    echo "  👤 账号：$ACCOUNT_ID ($type_label, $FTP_USER@$FTP_HOST:$FTP_PORT)"
    echo "  📁 本地路径：$LOCAL_PATH"
    echo "  📂 远程目标目录：$REMOTE_DIR"

    SSL_LINES="$(build_ssl_lines "$FTP_PROTO")"
    SFTP_LINES="$(build_sftp_lines "$FTP_PROTO")"
    LFTP_TARGET="$(get_lftp_target "$FTP_PROTO" "$FTP_HOST")"
    
    local SSL_VERIFY_LINE=""
    if [[ "$FTP_PROTO" != "sftp" ]]; then
        SSL_VERIFY_LINE="set ssl:verify-certificate no"
    fi

    # 【修复核心】注入全局防死锁、致命错误立即中断参数、以及覆写权限
    local GLOBAL_OPTS="
set cmd:fail-exit yes
set net:timeout 15
set net:max-retries 3
set net:persist-retries 0
set ftp:passive-mode auto
set xfer:clobber on"

    if [[ -d "$LOCAL_PATH" ]]; then
lftp -u "$FTP_USER","$FTP_PASS" -p "$FTP_PORT" "$LFTP_TARGET" <<EOF
$GLOBAL_OPTS
$SSL_VERIFY_LINE
$SSL_LINES
$SFTP_LINES
mkdir -p "$REMOTE_DIR"
mirror -R "$LOCAL_PATH" "$REMOTE_DIR"
bye
EOF
    else
        local filename
        filename="$(basename "$LOCAL_PATH")"
lftp -u "$FTP_USER","$FTP_PASS" -p "$FTP_PORT" "$LFTP_TARGET" <<EOF
$GLOBAL_OPTS
$SSL_VERIFY_LINE
$SSL_LINES
$SFTP_LINES
mkdir -p "$REMOTE_DIR"
cd "$REMOTE_DIR"
put "$LOCAL_PATH" -o "$filename"
bye
EOF
    fi

    # 现在的 $? 是真正准确的退出码了
    if [[ $? -eq 0 ]]; then
        echo "✅ 备份完成。"
    else
        echo "❌ 致命错误：备份中断。请检查："
        echo "   1. 远程目录是否具有读写权限（尝试将 /backup 改为相对路径 backup）。"
        echo "   2. 如果使用 FTP，请确保 VPS 安全组已放行被动模式随机高端口。"
        return 1
    fi
}

add_cron_job() {
    local CRON_EXPR="$1"
    local LOCAL_PATH="$2"
    local REMOTE_DIR="$3"
    local ACCOUNT_ID="$4"

    LOCAL_ESC=${LOCAL_PATH//\"/\\\"}
    REMOTE_ESC=${REMOTE_DIR//\"/\\\"}

    local CRON_LINE="$CRON_EXPR bash $SCRIPT_PATH run \"$ACCOUNT_ID\" \"$LOCAL_ESC\" \"$REMOTE_ESC\" $TAG[$ACCOUNT_ID]"

    (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -

    echo "✅ 定时任务已添加："
    echo "   $CRON_LINE"
}

list_cron_jobs() {
    echo "────────────────────────────────"
    echo "📋 当前备份任务"
    echo "────────────────────────────────"
    local lines
    lines=$(crontab -l 2>/dev/null | grep "$TAG" || true)

    if [[ -z "$lines" ]]; then
        echo "ℹ️  当前没有任何备份定时任务。"
        pause
        return
    fi

    local i=1
    declare -a JOBS
    while IFS= read -r line; do
        JOBS[$i]="$line"
        echo "[$i] $line"
        i=$((i+1))
    done <<< "$lines"

    echo
    read -rp "⚡ 是否选择其中一个任务立即执行一次？(y/N)： " run_now
    case "$run_now" in
        y|Y)
            read -rp "🔢 请输入任务编号： " choice
            if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ -z "${JOBS[$choice]}" ]]; then
                echo "❌ 输入编号无效。"
            else
                local target="${JOBS[$choice]}"
                local cmd_part
                cmd_part=$(echo "$target" | awk '{ $1=""; $2=""; $3=""; $4=""; $5=""; sub(/^ +/, ""); print }')
                echo "⚡ 正在立即执行：$cmd_part"
                eval "$cmd_part"
            fi
            ;;
        *)
            ;;
    esac

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
        i=$((i+1))
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

    while true; do
        read -rp "📁 请输入要备份的本地文件/目录路径： " LOCAL_PATH

        if [[ "$LOCAL_PATH" =~ \  ]]; then
            echo "❌ 路径中包含空格，请换一个路径（可用软链接）。"
            continue
        fi

        if [[ ! -e "$LOCAL_PATH" ]]; then
            echo "❌ 路径不存在，请重新输入！"
            continue
        fi

        break
    done

    read -rp "📂 请输入远程目标目录（例如 /backup/www 或 backup）： " REMOTE_DIR

    if [[ -z "$REMOTE_DIR" ]]; then
        echo "❌ 远程目标目录不能为空。"
        pause
        return
    fi

    CHOSEN_ACCOUNT_ID=""
    select_ftp_account || { pause; return; }
    local ACCOUNT_ID="$CHOSEN_ACCOUNT_ID"

    echo
    echo "⏱ 请选择定时架构："
    echo "  1) 🕒 每天单次固定时间 (如凌晨 03:30)"
    echo "  2) 🕐 每小时的第 N 分钟 (如写 30)"
    echo "  3) ⏳ 严格时间片间隔 (仅限：1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30)"
    read -rp "👉 请输入选项编号： " mode

    local CRON_EXPR=""

    case "$mode" in
        1)
            read -rp "🕒 每天几点执行（0-23）： " H
            read -rp "🕒 每天几分执行（0-59）： " M
            if ! [[ "$H" =~ ^[0-9]+$ ]] || ! [[ "$M" =~ ^[0-9]+$ ]] || ((H < 0 || H > 23)) || ((M < 0 || M > 59)); then
                echo "❌ 时间输入不合法，请遵循 24 小时制规范。"
                pause
                return
            fi
            CRON_EXPR="$M $H * * *"
            ;;
        2)
            read -rp "🕐 每小时的第几分钟准时触发（0-59）： " M
            if ! [[ "$M" =~ ^[0-9]+$ ]] || ((M < 0 || M > 59)); then
                echo "❌ 分钟输入不合法。"
                pause
                return
            fi
            CRON_EXPR="$M * * * *"
            ;;
        3)
            read -rp "⏳ 每隔多少分钟执行一次（必须输入上述提示的完美约数）： " N
            if ! [[ "$N" =~ ^[0-9]+$ ]] || [[ ! " 1 2 3 4 5 6 10 12 15 20 30 " =~ " $N " ]]; then
                echo "❌ 输入的数值存在重叠执行风险。为保证 I/O 安全，系统已拦截此配置。"
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

    add_cron_job "$CRON_EXPR" "$LOCAL_PATH" "$REMOTE_DIR" "$ACCOUNT_ID"

    echo
    read -rp "⚡ 是否立即执行一次此备份任务？(Y/n)： " run_now
    if [[ -z "$run_now" || "$run_now" =~ ^[Yy]$ ]]; then
        run_backup "$ACCOUNT_ID" "$LOCAL_PATH" "$REMOTE_DIR"
    fi

    pause
}

uninstall_all() {
    echo "────────────────────────────────"
    echo "🧹 卸载工具"
    echo "────────────────────────────────"
    read -rp "⚠️  确定要卸载吗？这会删除所有账号配置、备份任务和脚本本体。(y/N)： " ans
    case "$ans" in
        y|Y)
            if command_exists crontab; then
                local current
                current=$(crontab -l 2>/dev/null || true)
                if [[ -n "$current" ]]; then
                    echo "$current" | grep -v "$TAG" | crontab -
                fi
            fi

            rm -rf "$CONFIG_DIR"

            if [[ -f "$SCRIPT_PATH" ]]; then
                rm -f "$SCRIPT_PATH"
            fi

            echo "✅ 已卸载（已删除配置、任务和脚本本体）。"
            echo "👋 程序已退出。"
            exit 0
            ;;
        *)
            echo "ℹ️  已取消卸载。"
            ;;
    esac
    pause
}

show_menu() {
    clear
    echo "======================================="
    echo "🌐 FTP/SFTP 备份工具（多账号版）"
    echo "======================================="
    echo
    local count
    count=$(get_ftp_count)
    if (( count > 0 )); then
        echo "🔐 账号状态：已配置 $count 个 ✅"
    else
        echo "🔐 账号状态：未配置 ❌（请先添加账号）"
    fi
    echo
    echo "1) 📂 管理账号"
    echo "2) ➕ 新建备份任务"
    echo "3) 📋 查看/立即执行备份任务"
    echo "4) 🗑 删除备份任务"
    echo "5) 🧹 卸载"
    echo "0) ❎ 退出"
    echo
    read -rp "👉 请输入选项编号： " choice

    if ! is_ftp_configured && [[ "$choice" != "1" && "$choice" != "5" && "$choice" != "0" ]]; then
        echo
        echo "⚠️  当前尚未配置任何账号，请先进入“管理账号”添加。"
        pause
        return
    fi

    case "$choice" in
        1) ftp_account_menu ;;
        2) add_backup_job ;;
        3) list_cron_jobs ;;
        4) delete_cron_job ;;
        5) uninstall_all ;;
        0) exit 0 ;;
        *) echo "❌ 无效选项。"; pause ;;
    esac
}

if [[ "$1" == "run" ]]; then
    run_backup "$2" "$3" "$4"
    exit $?
fi

check_dependencies

while true; do
    show_menu
done
