#!/bin/bash

# 1、获取基础参数及资源配置文件路径
root_path=$(dirname "$PWD")
model_name=`ls ${root_path}/workspace|tail -1|awk -F 'train-' '{print $NF}'`
train_base_path="${root_path}/workspace/train-${model_name}"
trainer_name=`ls ${train_base_path}/data|tail -1|awk -F '_' '{print $1}'`
task_type=`ls ${train_base_path}/data|tail -1|awk -F '_' '{print $2}'`
source_file="${root_path}/workspace/train-${model_name}/source.ini"


# 2、获取基础镜像和存放路径
# 训练附属镜像名称
appendix_image_name=$(grep "appendix_image_name" "$source_file" | awk -F ":" '{print $2}')
# 训练附属镜像版本
appendix_image_version=$(grep "appendix_image_version" "$source_file" | awk -F ":" '{print $2}')

# 训练镜像名称和版本
if [ "${trainer_name}" == "uie" ]; then
  trainer_image_name=$(grep "uie_image_name" "$source_file" | awk -F ":" '{print $2}')
  trainer_image_version=$(grep "uie_image_version" "$source_file" | awk -F ":" '{print $2}')
fi

if [ "${trainer_name}" == "doietk" ]; then
  trainer_image_name=$(grep "doietk_image_name" "$source_file" | awk -F ":" '{print $2}')
  trainer_image_version=$(grep "doietk_image_version" "$source_file" | awk -F ":" '{print $2}')
fi

# 基础模型链接
if [ "${task_type}" == "ext" ]; then
  g_task_type="element"
  base_model_url=$(grep "doietk_ext_base_model_url" "$source_file" | awk -F " " '{print $2}')
fi
if [ "${task_type}" == "ocr" ]; then
  g_task_type="v3_element"
  base_model_url=$(grep "doietk_ocr_base_model_url" "$source_file" | awk -F " " '{print $2}')
fi
if [ "${task_type}" == "cls" ]; then
  g_task_type="cls"
  base_model_url=$(grep "doietk_cls_base_model_url" "$source_file" | awk -F " " '{print $2}')
fi

# 基础模型路径
base_model_root_path="${root_path}/workspace/train-${model_name}/base_model"
# 训练环境
train_root_path="${root_path}/workspace/train-${model_name}/${trainer_name}_${task_type}"
# 模型发布路径
model_release_path="$train_root_path/release"
# 训练产出环境
version_train_path="${train_root_path}/train/version_train"
# 训练产出日志
train_path_log="${version_train_path}/log"
# 训练路径/模型产出路径
train_path_model="${version_train_path}/model"
# 训练验证产出环境
train_eval_root_path="${train_root_path}/train_eval"
# 正则和关键词字典挂载路径"
train_root_patten="${train_root_path}/train_pattern"
# 训练验证产出日志
train_eval_path_log="${train_eval_root_path}/log"
# 训练验证路径/模型产出路径
train_eval_path_output="${train_eval_root_path}/output"
# 数据环境
dataset_path="${root_path}/workspace/train-${model_name}/data"
# 标注数据文件路径
annotation_data_path="${dataset_path}/annotation"
# 训练集数据路径
train_data_path="${dataset_path}/${trainer_name}_${task_type}/train"
# 验证集数据路径
valid_data_path="${dataset_path}/${trainer_name}_${task_type}/valid"


# 3、创建训练环境
echo "[Create workspace] model_name=${model_name} trainer_name=${trainer_name} task_type=${task_type}"
docker run --rm -v "${root_path}/workspace":/workspace \
  ${appendix_image_name}:${appendix_image_version} \
  rm -rf /workspace/train-${model_name}/${trainer_name}_${task_type}

mkdir -p "${base_model_root_path}"
mkdir -p "${train_root_path}"
mkdir -p "${model_release_path}"
mkdir -p "${version_train_path}" "${version_train_path}/log" "${version_train_path}/model"
mkdir -p "${train_eval_root_path}" "${train_eval_root_path}/log" "${train_eval_root_path}/output"
mkdir -p "${train_root_path}/train_pattern"
if [ "${trainer_name}" == "uie" ]; then
  mv "${train_base_path}/dict"  "${train_root_path}/dict"
fi


# 4、下载训练镜像
echo "[Pull trainer image] trainer image ${trainer_image_name}:${trainer_image_version}"
docker pull ${trainer_image_name}:${trainer_image_version}

echo "[Pull appendix trainer image] appendix trainer image ${appendix_image_name}:${appendix_image_version}"
docker pull ${appendix_image_name}:${appendix_image_version}


# 5、下载基础训练模型
if [ "${trainer_name}" == "doietk" ]; then
  # doietk镜像训练需要下载基础镜像
  base_model_tar_file=$(echo "${base_model_url}" | awk -F "/" '{print $NF}')
  base_model_path=$(echo "${base_model_tar_file}" | awk -F "." '{print $1}')
  base_model_name=$(echo "${base_model_url}" | awk -F "/" '{print $(NF-1)}')
  echo "base_model_name":${base_model_name} "base_model_path":${base_model_path}
  if [ ! -d "${base_model_root_path}/${base_model_path}" ] ; then
      echo "[Download base model] ${base_model_path}"
      docker run --rm \
      -v "${base_model_root_path}/":"/root/.model_hub/" \
      $appendix_image_name:"$appendix_image_version" \
      /root/miniconda3/bin/python -m model_manage.model_manage download ${base_model_name} --model_tag="${base_model_path}.tar"
  else
      echo "[Download base model] checked"
  fi
fi


# 6、创建训练配置文件
echo "[Initialize] config file"
config_file=${train_root_path}/config.ini
touch "$config_file"
{
    echo "[basic]"
    echo "# 模型名称"
    echo "model_name:${model_name}"
    echo "# 训练框架名"
    echo "trainer_name:${trainer_name}"
    echo "# 训练镜像名称"
    echo "trainer_image_name:${trainer_image_name}"
    echo "# 训练镜像版本"
    echo "trainer_image_version:${trainer_image_version}"
    echo "# 辅助训练镜像名称"
    echo "appendix_img_name:${appendix_image_name}"
    echo "# 辅助训练镜像版本"
    echo "appendix_img_version:${appendix_image_version}"
    echo ""

    echo "[data]"
    echo "# 标注数据文件路径"
    echo "annotation_data_path:${annotation_data_path}"
    echo "# 标注数据文件名"
    echo "annotation_data_file:data.jsonl"
    echo "# 数据集根路径"
    echo "dataset_path:${dataset_path}"
    echo "# 训练集路径"
    echo "train_data_path:${train_data_path}"
    echo "# 验证集路径"
    echo "valid_data_path:${valid_data_path}"
    echo "# 训练集数据比例(0.0 ~ 1.0)"
    echo "train_ratio:${train_ratio}"
    echo ""

    echo "[trainer]"
    echo "# 训练模型环境ID"
    echo "train_env_id:${train_env_id}"

    echo "# 基础模型"
    echo "base_model:${base_model_root_path}/${base_model_path}"

    echo "# 训练根路径"
    echo "train_root_path:${train_root_path}"

    echo "# 训练路径"
    echo "version_train_path:${version_train_path}"
    echo "# 训练路径/日志路径"
    echo "train_path_log:${train_path_log}"
    echo "# 训练路径/模型产出路径"
    echo "train_path_model:${train_path_model}"

    echo "# 训练验证产出环境"
    echo "train_eval_root_path:${train_eval_root_path}"
    echo "# 训练验证路径/日志路径"
    echo "train_eval_path_log:${train_eval_path_log}"
    echo "# 训练验证路径/模型产出路径"
    echo "train_eval_path_output:${train_eval_path_output}"

    echo "# 模型发布路径"
    echo "model_release_path:${model_release_path}"

    echo "# UIE模型schema文件"
    echo "model_dict:${train_root_path}/dict/schema.dic"
    echo "# UIE模型学习率"
    echo "learning_rate:1e-5"
    echo "# batch大小"
    echo "batch_size:4"
    echo "# UIE模型最大文本长度(上限1024)"
    echo "max_seq_len:512"
    echo "# UIE模型epoch数量"
    echo "num_epochs:3"
    echo "# UIE基础模型"
    echo "uie_b_model:uie-base"
    echo "# UIE模型random seed"
    echo "seed:1000"
    echo "# UIE模型日志记录的步数"
    echo "logging_steps:10"
    echo "# UIE模型验证的步数"
    echo "valid_steps:50"

    echo "# 正则和关键词字典挂载路径"
    echo "train_root_patten:${train_root_patten}"

    echo "# GPU index"
    echo "gpu_idx:0"
} > "$config_file"


# 7、开始训练
echo "[Train] start to train"
# UIE框架优化参数
learning_rate=$(grep "learning_rate" $config_file | awk -F ":" '{print $2}')
batch_size=$(grep "batch_size" $config_file | awk -F ":" '{print $2}')
max_seq_len=$(grep "max_seq_len" $config_file | awk -F ":" '{print $2}')
num_epochs=$(grep "num_epochs" $config_file | awk -F ":" '{print $2}')
uie_b_model=$(grep "uie_b_model" $config_file | awk -F ":" '{print $2}')
seed=$(grep "seed" $config_file | awk -F ":" '{print $2}')
logging_steps=$(grep "logging_steps" $config_file | awk -F ":" '{print $2}')
valid_steps=$(grep "valid_steps" $config_file | awk -F ":" '{print $2}')

gpu_idx=$(grep "gpu_idx" $config_file | awk -F ":" '{print $2}')
idx=$(nvidia-smi | grep "MiB" | grep "Default" | awk -F " " '{split($9,arr1,"M");split($11, arr2, "M");line=line" "(arr2[1]-arr1[1])}END{print line}' | awk -F " " '{max_mem=0;max_idx=-1;for(i=1;i<=NF;i++){if($i>max_mem){max_idx=i;max_mem=$i}}}END{print max_idx}')

if [ "${trainer_name}" == "doietk" ]; then
  docker run --rm --security-opt seccomp:unconfined --cap-add SYS_PTRACE --net=bridge \
    --gpus "device=$(echo $idx | awk '{print($1-1)}')" \
    -e USE_GPU=1 \
    -e EPOCH=$num_epochs \
    -e BATCH_SIZE=$batch_size \
    -e PET_IP_PORT="10.88.94.139:8679" \
    -e AIPE_SECURITY_SERVER_HOST=10.232.43.25 \
    -e PROCESS_TAG_NAME=tm_train \
    -e MODEL_TYPES="${g_task_type}_finetune" \
    -v "${base_model_root_path}/${base_model_path}":/home/bml/train_base_model -e TRAIN_BASE_MODEL=/home/bml/train_base_model \
    -v "${train_root_path}":/home/bml/train -e TRAIN_RES_HOME_FOLDER=/home/bml/train \
    -v "${version_train_path}":/home/bml/version_train -e TRAIN_RES_VTRAIN_FOLDER=/home/bml/version_train \
    -v "${train_path_log}":/home/bml/train_log -e TRAIN_RES_LOG_FOLDER=/home/bml/train_log \
    -v "${train_path_model}":/home/bml/train_model -e TRAIN_RES_MODEL_FOLDER=/home/bml/train_model \
    -v "${train_eval_root_path}":/home/bml/train_eval -e TRAIN_EVA_RES_HOME_FOLDER=/home/bml/train_eval \
    -v "${train_eval_path_log}":/home/bml/train_eval/log -e TRAIN_EVA_RES_LOG_FOLDER=/home/bml/train_eval/log \
    -v "${train_eval_path_output}":/home/bml/train_eval/output -e TRAIN_EVA_RES_OUTPUT_FOLDER=/home/bml/train_eval/output \
    -v "${train_data_path}":/home/bml/input_train_data -e TRAIN_DATA_INPUT_FOLDER=/home/bml/input_train_data \
    -v "${valid_data_path}":/home/bml/eva_train_data -e TRAIN_DATA_EVA_INPUT_FOLDER=/home/bml/eva_train_data \
    -v "${train_root_patten}":/home/bml/train_pattern -e TRAIN_PATTERN_INPUT_FOLDER=/home/bml/train_pattern \
    "${trainer_image_name}:${trainer_image_version}" sh run.sh
else
  docker run --rm \
    --gpus all \
    -v"${dataset_path}/${trainer_name}_${task_type}":/data \
    -v"${train_path_model}":/model \
    "${trainer_image_name}:${trainer_image_version}" \
    /usr/local/bin/python -m uie.train \
    --train_path "/data/train.jsonl" \
    --dev_path "/data/valid.jsonl" \
    --save_dir "/model" \
    --learning_rate ${learning_rate} \
    --batch_size ${batch_size} \
    --max_seq_len ${max_seq_len} \
    --num_epochs ${num_epochs} \
    --model "${uie_b_model}" \
    --seed ${seed} \
    --logging_steps ${logging_steps} \
    --valid_steps ${valid_steps} \
    --device "gpu:$(echo $idx | awk '{print($1-1)}')"
fi
