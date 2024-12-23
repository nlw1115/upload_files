#!/bin/bash

# 默认的用户名
REMOTE_USER="root"

# 检查是否通过命令行传递了目标机器的 IP 地址
if [ -z "$1" ]; then
  # 如果没有传递目标 IP 地址，提示用户输入
  read -p "请输入目标机器的IP地址: " REMOTE_HOST
else
  # 如果通过命令行传递了IP地址
  REMOTE_HOST="$1"
fi

# 如果目标机器 IP 地址为空，退出脚本
if [ -z "$REMOTE_HOST" ]; then
  echo "未提供目标机器 IP 地址，退出脚本"
  exit 1
fi

# 提示用户输入密码
read -s -p "请输入目标机器的密码: " REMOTE_PASS
echo

# 检查是否安装了 sshpass
if ! command -v sshpass &>/dev/null; then
  echo "sshpass 未安装，正在尝试自动安装..."
  
  # 获取操作系统信息
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
  else
    echo "无法检测操作系统类型，请手动安装 sshpass 后再运行脚本。"
    exit 1
  fi

  # 根据操作系统类型安装 sshpass
  case "$OS" in
    ubuntu|debian)
      sudo apt update && sudo apt install -y sshpass || {
        echo "无法安装 sshpass，请检查网络或权限。"; exit 1;
      }
      ;;
    centos|rhel|fedora)
      sudo yum install -y epel-release && sudo yum install -y sshpass || {
        echo "无法安装 sshpass，请检查网络或权限。"; exit 1;
      }
      ;;
    *)
      echo "不支持的操作系统类型，请手动安装 sshpass 后再运行脚本。"
      exit 1
      ;;
  esac
  echo "sshpass 安装成功。"
fi

# 查找本地包含 "x-ui" 的文件路径
FILES=$(find / -name "*x-ui*" 2>/dev/null)

# 如果没有找到任何文件
if [ -z "$FILES" ]; then
  echo "没有找到包含 'x-ui' 的文件"
  exit 1
fi

# 显示找到的文件路径并提示用户按回车确认
echo "找到以下文件路径："
echo "$FILES"
echo "按回车键继续上传这些文件到目标机器 $REMOTE_HOST"

# 等待用户按下回车键
read -p "按回车继续，或按 Ctrl+C 取消："

# 循环遍历查找到的文件并通过 scp 上传到目标机器
for FILE in $FILES; do
  echo "正在上传文件: $FILE"
  
  # 使用 sshpass 和 scp 将文件上传到目标机器
  sshpass -p "$REMOTE_PASS" scp -r "$FILE" "$REMOTE_USER@$REMOTE_HOST:$FILE"
  
  # 检查上传是否成功
  if [ $? -eq 0 ]; then
    echo "文件 $FILE 上传成功"
  else
    echo "文件 $FILE 上传失败"
  fi
done

echo "上传任务完成"
