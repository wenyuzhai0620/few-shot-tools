#!/bin/bash

# 1、获取参数
if [ $# -lt 1 ] ; then
  read -p "Please input your service port:" service_port
else
  service_port=$1
fi

# 2、获取基础参数及资源配置文件路径
root_path=$(dirname "$PWD")
model_name=`ls ${root_path}/workspace|tail -1|awk -F 'train-' '{print $NF}'`
train_base_path="${root_path}/workspace/train-${model_name}"
trainer_name=`ls ${train_base_path}/data|tail -1|awk -F '_' '{print $1}'`
task_type=`ls ${train_base_path}/data|tail -1|awk -F '_' '{print $2}'`
source_file="${root_path}/workspace/train-${model_name}/source.ini"
config_file="${root_path}/workspace/train-${model_name}/${trainer_name}_${task_type}/config.ini"


# 3、获取基础参数
gpu_idx=$(grep "gpu_idx" $config_file | awk -F ":" '{print $2}')
idx=$(nvidia-smi | grep "MiB" | grep "Default" | awk -F " " '{split($9,arr1,"M");split($11, arr2, "M");line=line" "(arr2[1]-arr1[1])}END{print line}' | awk -F " " '{max_mem=0;max_idx=-1;for(i=1;i<=NF;i++){if($i>max_mem){max_idx=i;max_mem=$i}}}END{print max_idx}')
model_release_path=$(grep "model_release_path" $config_file | awk -F ":" '{print $2}')


# 4、启动推理镜像
if [ "${trainer_name}" == "uie" ]; then
  infer_image_name=$(grep "uie_infer_image_name" "$source_file" | awk -F ":" '{print $2}')
  infer_image_version=$(grep "uie_infer_image_version" "$source_file" | awk -F ":" '{print $2}')

  docker run --name "service-${model_name}-${trainer_name}" --entrypoint /bin/bash -itd --gpus "device=$(echo $idx | awk '{print($1-1)}')" -p ${service_port}:8998 -v "${model_release_path}":"/uie-model-server/routers/extractor/resources" ${infer_image_name}:${infer_image_version} start_new.sh 0 1 10
  # 输出推理接口
  infer_url="http://$(hostname):${service_port}/extractor/run"
  echo ${infer_url}
fi

if [ "${trainer_name}" == "doietk" ]; then
  infer_image_name=$(grep "doietk_infer_image_name" "$source_file" | awk -F ":" '{print $2}')
  infer_image_version=$(grep "doietk_infer_image_version" "$source_file" | awk -F ":" '{print $2}')

  # 启动推理镜像服务
  docker run --name "service-${model_name}-${trainer_name}-${service_port}" -itd  -p ${service_port}:8115 --gpus "device=$(echo $idx | awk '{print($1-1)}')" -v "${model_release_path}/${model_name}":/home/bml/model ${infer_image_name}:${infer_image_version} sh run_local.sh 10.232.43.25 1

  # 输出推理接口
  infer_base_url="http://$(hostname):${service_port}"
  # 基础模型链接
  if [ "${task_type}" == "cls" ]; then
    infer_url="${infer_base_url}/v1/classification"
  fi
  if [ "${task_type}" == "ext" ]; then
    infer_url="${infer_base_url}/v1/element"
  fi
  if [ "${task_type}" == "ocr" ]; then
    infer_url="${infer_base_url}/v3/element"
  fi
  echo ${infer_url}
fi
