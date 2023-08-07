#!/bin/bash

# 1、获取基础参数及资源配置文件路径
root_path=$(dirname "$PWD")
model_name=`ls ${root_path}/workspace|tail -1|awk -F 'train-' '{print $NF}'`
train_base_path="${root_path}/workspace/train-${model_name}"
trainer_name=`ls ${train_base_path}/data|tail -1|awk -F '_' '{print $1}'`
task_type=`ls ${train_base_path}/data|tail -1|awk -F '_' '{print $2}'`
source_file="${root_path}/workspace/train-${model_name}/source.ini"
config_file="${root_path}/workspace/train-${model_name}/${trainer_name}_${task_type}/config.ini"

model_name=$(grep "model_name" "$config_file" | awk -F ":" '{print $2}')
trainer_name=$(grep "trainer_name" "$config_file" | awk -F ":" '{print $2}')
train_path_model=$(grep "train_path_model" $config_file | awk -F ":" '{print $2}')
model_name=$(grep "model_name" $config_file | awk -F ":" '{print $2}')
model_release_path=$(grep "model_release_path" $config_file | awk -F ":" '{print $2}')
trainer_image_name=$(grep "trainer_image_name" $config_file | awk -F ":" '{print $2}')
image_version=$(grep "image_version" $config_file | awk -F ":" '{print $2}')
model_dict=$(grep "model_dict" $config_file | awk -F ":" '{print $2}')
gpu_idx=$(grep "gpu_idx" $config_file | awk -F ":" '{print $2}')
idx=$(nvidia-smi | grep "MiB" | grep "Default" | awk -F " " '{split($9,arr1,"M");split($11, arr2, "M");line=line" "(arr2[1]-arr1[1])}END{print line}' | awk -F " " '{max_mem=0;max_idx=-1;for(i=1;i<=NF;i++){if($i>max_mem){max_idx=i;max_mem=$i}}}END{print max_idx}')

echo "[Model optimize] start to optimize"
if [ "${trainer_name}" == "doietk" ]; then
  rm -rf "${model_release_path}/${model_name}"
  cp -rf "${train_path_model}" "${model_release_path}/${model_name}"
else
  docker run --rm \
    -v"${train_path_model}":/model \
    --gpus "device=$(echo $idx | awk '{print($1-1)}')" --rm \
    $trainer_image_name:"$image_version" \
    /usr/local/bin/python -m uie.to_static \
    --model_path /model/model_best
  cp -rf "${train_path_model}/model_best" "${model_release_path}/${model_name}"
  mkdir -p "${model_release_path}/${model_name}/dict"
  cp -rf "${model_dict}" "${model_release_path}/${model_name}/dict/"
fi
echo "[Model optimize] finished."
