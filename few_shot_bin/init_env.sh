#!/bin/bash

# 1、获取参数
if [ $# -lt 1 ] ; then
  read -p "Please input your model name:" model_name
else
  model_name=$1
fi


# 2、检查基础依赖是否满足
echo "[Check the env]"


# 3、设置相关文件目录
# 操作根目录 参数1
root_path=$(dirname "$PWD")
# 项目基础路径
train_root_path="${root_path}/workspace/train-${model_name}"


# 4、清空之前的环境
if [ -d "${root_path}/workspace" ]; then
  read -p "Workspace existed,do you want to clear it? [Y/y]:" init_flag
  if [ "${init_flag}" == "Y" ] || [ "${init_flag}" == "y" ]; then
    rm -rf "${root_path}/workspace/"
    echo "Workspace is clear."
  fi
fi


# 5、创建基础环境
echo "[Create workspace] root_path=${root_path} model_name=${model_name}"
mkdir -p "${root_path}/workspace"
mkdir -p "${train_root_path}"


# 6、创建训练配置文件
cp ./source.ini ${train_root_path}/.

echo "[Initialize] env all ready."
