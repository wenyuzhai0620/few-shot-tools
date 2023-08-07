#!/bin/bash

# 1、获取基础参数及资源配置文件路径
root_path=$(dirname "$PWD")
if [ ! -d "${root_path}/workspace" ]; then
  echo "[clear workspace] cleared."
  exit
fi
model_name=`ls ${root_path}/workspace|tail -1|awk -F 'train-' '{print $NF}'`
train_base_path="${root_path}/workspace/train-${model_name}"
trainer_name=`ls ${train_base_path}/data|tail -1|awk -F '_' '{print $1}'`
task_type=`ls ${train_base_path}/data|tail -1|awk -F '_' '{print $2}'`
source_file="${root_path}/workspace/train-${model_name}/source.ini"

# 训练附属镜像名称
appendix_image_name=$(grep "appendix_image_name" "$source_file" | awk -F ":" '{print $2}')
# 训练附属镜像版本
appendix_image_version=$(grep "appendix_image_version" "$source_file" | awk -F ":" '{print $2}')


# 2、停止标注服务
doccano_dpid=$(docker ps -a | grep "doccano-${model_name}" | awk '{print $1}')
if [[ -n ${doccano_dpid} ]]; then
  docker stop ${doccano_dpid}
  docker rm ${doccano_dpid}
fi
echo "stop annotation success."
 
service_dpid=$(docker ps -a | grep "service-${model_name}-${trainer_name}" | awk '{print $1}')
if [[ -n ${service_dpid} ]]; then
  docker stop ${service_dpid}
  docker rm ${service_dpid}
fi
echo "stop service success."

# 3、删除项目环境
# 待完善
#if [ ${trainer_name} == "doietk" ]; then
#  docker run --rm -v "${root_path}/workspace":/workspace \ 
#    ${appendix_image_name}:${appendix_image_version} \ 
#    rm -rf /workspace/*
#  rm -rf "${root_path}/workspace/"
#fi
#echo "[clear workspace] model_name=${model_name} trainer_name=${trainer_name} task_type=${task_type}"

