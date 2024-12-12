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
  
  # 使用 scp 将文件上传到目标机器
  scp -r "$FILE" "$REMOTE_USER@$REMOTE_HOST:$FILE"
  
  # 检查上传是否成功
  if [ $? -eq 0 ]; then
    echo "文件 $FILE 上传成功"
  else
    echo "文件 $FILE 上传失败"
  fi
done

echo "上传任务完成"
