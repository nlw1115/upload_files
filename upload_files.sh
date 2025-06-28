#!/bin/bash

# X-UI文件上传脚本 - 增强版
# 版本: 2.0
# 作者: nlw1115
# 描述: 自动查找并上传x-ui相关文件到远程服务器

set -euo pipefail  # 严格模式：遇到错误立即退出，未定义变量报错，管道错误传播

# 配置变量
REMOTE_USER="root"
LOG_FILE="/tmp/upload_files_$(date +%Y%m%d_%H%M%S).log"
MAX_RETRIES=3
TIMEOUT=30
TEMP_DIR="/tmp"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
    log "INFO" "$*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
    log "WARN" "$*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
    log "ERROR" "$*"
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $*"
        log "DEBUG" "$*"
    fi
}

# 清理函数
cleanup() {
    log_info "清理临时文件..."
    # 这里可以添加清理逻辑
}

# 信号处理
trap cleanup EXIT
trap 'log_error "脚本被中断"; exit 130' INT TERM

# 显示帮助信息
show_help() {
    cat << EOF
用法: $0 [选项] <目标机器IP>

选项:
  -h, --help     显示此帮助信息
  -u, --user     指定远程用户名 (默认: root)
  -p, --port     指定SSH端口 (默认: 22)
  -d, --debug    启用调试模式
  -t, --timeout  设置连接超时时间 (默认: 30秒)
  -r, --retries  设置重试次数 (默认: 3次)

示例:
  $0 192.168.1.100
  $0 -u admin -p 2222 192.168.1.100
  $0 --debug --timeout 60 192.168.1.100

EOF
}

# 验证IP地址格式
validate_ip() {
    local ip="$1"
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    elif [[ $ip =~ ^[a-zA-Z0-9.-]+$ ]]; then
        # 域名格式
        return 0
    else
        return 1
    fi
}

# 解析命令行参数
SSH_PORT=22
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -u|--user)
            REMOTE_USER="$2"
            shift 2
            ;;
        -p|--port)
            SSH_PORT="$2"
            shift 2
            ;;
        -d|--debug)
            DEBUG=1
            shift
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -r|--retries)
            MAX_RETRIES="$2"
            shift 2
            ;;
        -*)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
        *)
            REMOTE_HOST="$1"
            shift
            ;;
    esac
done

# 检查是否提供了目标机器IP
if [[ -z "${REMOTE_HOST:-}" ]]; then
    log_error "未提供目标机器IP地址"
    show_help
    exit 1
fi

# 验证IP地址格式
if ! validate_ip "$REMOTE_HOST"; then
    log_error "无效的IP地址或域名格式: $REMOTE_HOST"
    exit 1
fi

log_info "开始X-UI文件上传任务"
log_info "目标服务器: $REMOTE_USER@$REMOTE_HOST:$SSH_PORT"
log_info "日志文件: $LOG_FILE"

# 安全的密码输入
while true; do
    read -s -p "请输入目标机器的密码: " REMOTE_PASS
    echo
    if [[ -n "$REMOTE_PASS" ]]; then
        break
    else
        log_warn "密码不能为空，请重新输入"
    fi
done

# 检查依赖工具
check_dependencies() {
    local missing_deps=()
    
    # 检查必需的命令
    local required_commands=("sshpass" "scp" "ssh" "find")
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "缺少必需的依赖工具: ${missing_deps[*]}"
        
        # 尝试自动安装sshpass
        if [[ " ${missing_deps[*]} " =~ " sshpass " ]]; then
            install_sshpass
        else
            log_error "请手动安装缺少的工具后重新运行脚本"
            exit 1
        fi
    fi
}

# 安装sshpass
install_sshpass() {
    log_info "sshpass 未安装，正在尝试自动安装..."
    
    # 获取操作系统信息
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
    else
        log_error "无法检测操作系统类型，请手动安装 sshpass"
        exit 1
    fi

    # 根据操作系统类型安装 sshpass
    case "$OS" in
        ubuntu|debian)
            if sudo apt update && sudo apt install -y sshpass; then
                log_info "sshpass 安装成功"
            else
                log_error "无法安装 sshpass，请检查网络或权限"
                exit 1
            fi
            ;;
        centos|rhel|fedora)
            if sudo yum install -y epel-release && sudo yum install -y sshpass; then
                log_info "sshpass 安装成功"
            else
                log_error "无法安装 sshpass，请检查网络或权限"
                exit 1
            fi
            ;;
        arch|manjaro)
            if sudo pacman -S --noconfirm sshpass; then
                log_info "sshpass 安装成功"
            else
                log_error "无法安装 sshpass，请检查网络或权限"
                exit 1
            fi
            ;;
        *)
            log_error "不支持的操作系统类型: $OS，请手动安装 sshpass"
            exit 1
            ;;
    esac
}

# 测试SSH连接
test_ssh_connection() {
    log_info "测试SSH连接..."
    
    local retry_count=0
    while [[ $retry_count -lt $MAX_RETRIES ]]; do
        log_debug "尝试连接 ($((retry_count + 1))/$MAX_RETRIES)"
        
        if timeout "$TIMEOUT" sshpass -p "$REMOTE_PASS" ssh \
            -o ConnectTimeout="$TIMEOUT" \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            -p "$SSH_PORT" \
            "$REMOTE_USER@$REMOTE_HOST" \
            "echo 'SSH连接测试成功'" &>/dev/null; then
            log_info "SSH连接测试成功"
            return 0
        else
            ((retry_count++))
            if [[ $retry_count -lt $MAX_RETRIES ]]; then
                log_warn "SSH连接失败，等待5秒后重试..."
                sleep 5
            fi
        fi
    done
    
    log_error "SSH连接测试失败，请检查:"
    log_error "1. 目标服务器是否可达"
    log_error "2. SSH服务是否运行在端口 $SSH_PORT"
    log_error "3. 用户名和密码是否正确"
    log_error "4. 防火墙设置是否允许SSH连接"
    return 1
}

# 检查依赖
check_dependencies

# 测试SSH连接
if ! test_ssh_connection; then
    exit 1
fi

# 查找x-ui相关文件
find_xui_files() {
    log_info "正在查找x-ui相关文件..."
    
    # 定义搜索路径，避免搜索整个根目录
    local search_paths=(
        "/etc"
        "/usr/local"
        "/usr/bin"
        "/usr/sbin"
        "/opt"
        "/var"
        "/home"
        "/root"
    )
    
    local found_files=()
    local search_patterns=("*x-ui*" "*xui*" "*X-UI*")
    
    for path in "${search_paths[@]}"; do
        if [[ -d "$path" ]]; then
            log_debug "搜索路径: $path"
            for pattern in "${search_patterns[@]}"; do
                while IFS= read -r -d '' file; do
                    if [[ -e "$file" ]]; then
                        found_files+=("$file")
                        log_debug "找到文件: $file"
                    fi
                done < <(find "$path" -name "$pattern" -print0 2>/dev/null)
            done
        fi
    done
    
    # 去重并排序
    if [[ ${#found_files[@]} -gt 0 ]]; then
        printf '%s\n' "${found_files[@]}" | sort -u
    fi
}

# 显示文件大小
get_file_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        du -h "$file" | cut -f1
    elif [[ -d "$file" ]]; then
        du -sh "$file" | cut -f1
    else
        echo "未知"
    fi
}

# 查找文件
log_info "开始查找x-ui相关文件..."
readarray -t FILES < <(find_xui_files)

# 检查是否找到文件
if [[ ${#FILES[@]} -eq 0 ]]; then
    log_error "没有找到包含 'x-ui' 的文件"
    log_info "请确保x-ui已正确安装"
    exit 1
fi

# 显示找到的文件
log_info "找到 ${#FILES[@]} 个x-ui相关文件:"
echo
printf "%-5s %-10s %s\n" "序号" "大小" "文件路径"
printf "%-5s %-10s %s\n" "----" "----" "--------"
for i in "${!FILES[@]}"; do
    local size=$(get_file_size "${FILES[$i]}")
    printf "%-5d %-10s %s\n" "$((i+1))" "$size" "${FILES[$i]}"
done
echo

# 用户确认
while true; do
    read -p "是否继续上传这些文件到 $REMOTE_HOST? [y/N]: " confirm
    case $confirm in
        [Yy]|[Yy][Ee][Ss])
            break
            ;;
        [Nn]|[Nn][Oo]|"")
            log_info "用户取消操作"
            exit 0
            ;;
        *)
            echo "请输入 y 或 n"
            ;;
    esac
done

# 安全上传单个文件
safe_upload_file() {
    local file="$1"
    local current_file="$2"
    local total_files="$3"
    
    log_info "[$current_file/$total_files] 正在处理: $file"
    
    # 获取文件信息
    local filename=$(basename "$file")
    local target_dir=$(dirname "$file")
    local temp_file="$TEMP_DIR/xui_upload_${filename}_$$"
    
    # 检查源文件是否存在
    if [[ ! -e "$file" ]]; then
        log_error "源文件不存在: $file"
        return 1
    fi
    
    local retry_count=0
    while [[ $retry_count -lt $MAX_RETRIES ]]; do
        log_debug "尝试上传 ($((retry_count + 1))/$MAX_RETRIES): $file"
        
        # 步骤1: 上传到临时目录
        if timeout "$TIMEOUT" sshpass -p "$REMOTE_PASS" scp \
            -o ConnectTimeout="$TIMEOUT" \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            -p "$SSH_PORT" \
            -r "$file" "$REMOTE_USER@$REMOTE_HOST:$temp_file" 2>/dev/null; then
            
            log_debug "文件已上传到临时位置: $temp_file"
            
            # 步骤2: 创建备份（如果目标文件已存在）
            local backup_cmd=""
            if [[ -n "${BACKUP:-}" ]]; then
                backup_cmd="if [[ -e '$file' ]]; then sudo cp -r '$file' '${file}.backup.$(date +%Y%m%d_%H%M%S)'; fi && "
            fi
            
            # 步骤3: 创建目标目录并移动文件
            local move_cmd="sudo mkdir -p '$target_dir' && ${backup_cmd}sudo mv '$temp_file' '$file'"
            
            # 步骤4: 设置权限
            local perm_cmd=""
            if [[ -d "$target_dir" ]]; then
                perm_cmd=" && (sudo chmod --reference='$target_dir' '$file' 2>/dev/null || sudo chown root:root '$file' 2>/dev/null || true)"
            else
                perm_cmd=" && sudo chown root:root '$file' 2>/dev/null || true"
            fi
            
            # 执行远程命令
            if timeout "$TIMEOUT" sshpass -p "$REMOTE_PASS" ssh \
                -o ConnectTimeout="$TIMEOUT" \
                -o StrictHostKeyChecking=no \
                -o UserKnownHostsFile=/dev/null \
                -o LogLevel=ERROR \
                -p "$SSH_PORT" \
                "$REMOTE_USER@$REMOTE_HOST" \
                "$move_cmd$perm_cmd" 2>/dev/null; then
                
                log_info "✓ 文件上传成功: $file"
                return 0
            else
                log_warn "移动文件到目标位置失败，清理临时文件"
                # 清理临时文件
                sshpass -p "$REMOTE_PASS" ssh \
                    -o ConnectTimeout="$TIMEOUT" \
                    -o StrictHostKeyChecking=no \
                    -o UserKnownHostsFile=/dev/null \
                    -o LogLevel=ERROR \
                    -p "$SSH_PORT" \
                    "$REMOTE_USER@$REMOTE_HOST" \
                    "rm -f '$temp_file'" 2>/dev/null || true
            fi
        else
            log_warn "上传到临时目录失败"
        fi
        
        ((retry_count++))
        if [[ $retry_count -lt $MAX_RETRIES ]]; then
            log_warn "等待3秒后重试..."
            sleep 3
        fi
    done
    
    log_error "✗ 文件上传失败: $file"
    return 1
}

# 主上传流程
log_info "开始上传文件..."
echo

# 统计变量
local success_count=0
local failed_count=0
local failed_files=()

# 上传每个文件
for i in "${!FILES[@]}"; do
    if safe_upload_file "${FILES[$i]}" "$((i+1))" "${#FILES[@]}"; then
        ((success_count++))
    else
        ((failed_count++))
        failed_files+=("${FILES[$i]}")
    fi
    echo
done

# 显示上传结果
echo "==================== 上传结果 ===================="
log_info "总文件数: ${#FILES[@]}"
log_info "成功上传: $success_count"
if [[ $failed_count -gt 0 ]]; then
    log_error "上传失败: $failed_count"
    echo
    log_error "失败的文件列表:"
    for file in "${failed_files[@]}"; do
        echo "  - $file"
    done
else
    log_info "所有文件上传成功！"
fi
echo "================================================="

# 生成上传报告
local report_file="/tmp/xui_upload_report_$(date +%Y%m%d_%H%M%S).txt"
{
    echo "X-UI文件上传报告"
    echo "生成时间: $(date)"
    echo "目标服务器: $REMOTE_USER@$REMOTE_HOST:$SSH_PORT"
    echo "总文件数: ${#FILES[@]}"
    echo "成功上传: $success_count"
    echo "上传失败: $failed_count"
    echo
    echo "文件列表:"
    for i in "${!FILES[@]}"; do
        local status="成功"
        for failed_file in "${failed_files[@]}"; do
            if [[ "$failed_file" == "${FILES[$i]}" ]]; then
                status="失败"
                break
            fi
        done
        echo "  [$status] ${FILES[$i]}"
    done
} > "$report_file"

log_info "详细报告已保存到: $report_file"

# 退出状态
if [[ $failed_count -gt 0 ]]; then
    exit 1
else
    log_info "所有任务完成！"
    exit 0
fi
