#!/bin/bash

# 1、获取参数
if [ $# -lt 1 ] ; then
  read -p "Please input your trainer name[uie/doietk]:" trainer_name
  read -p "Please input your task type[cls/ext/ocr]:" task_type
  read -p "Please input your annotation project id[1]:" annotation_project_id
  read -p "Please input your train ratio[0~1.0]:" train_ratio
  read -p "Please input your neg pos rate, only for doietk ext[0~10]:" neg_pos_rate
else
  trainer_name=$1
  task_type=$2
  annotation_project_id=$3
  train_ratio=$4
  neg_pos_rate=$5
fi



# 2、获取基础参数及资源配置文件路径
root_path=$(dirname "$PWD")
model_name=`ls ${root_path}/workspace|tail -1|awk -F 'train-' '{print $NF}'`
train_root_path="${root_path}/workspace/train-${model_name}"
source_file="${root_path}/workspace/train-${model_name}/source.ini"


# 3、检查训练算子名称是否正确
if [ "${trainer_name}" != "uie" ]; then
  if [ "${trainer_name}" != "doietk" ]; then
    echo "[Error] error trainer-name only [uie|doietk]"
    exit -1
  fi
fi


# 4、检查模型任务类型是否正确
if [ "${task_type}" != "cls" ]; then
  if [ "${task_type}" != "ext" ]; then
    if [ "${task_type}" != "ocr" ]; then
      echo "[Error] error task-type only [cls|ext|ocr]"
      exit -1
    fi
  fi
fi


# 5、基础配置
# 训练附属镜像名称
appendix_image_name=$(grep "appendix_image_name" "$source_file" | awk -F ":" '{print $2}')
# 训练附属镜像版本
appendix_image_version=$(grep "appendix_image_version" "$source_file" | awk -F ":" '{print $2}')
# 多模ocr解析服务
document_parser_url=$(grep "document_parser_url" "$source_file" | awk -F " " '{print $2}')

# 6、获取标注数据
# 基础数据路径
dataset_path="${train_root_path}/data"
# 标注数据路径
annotation_data_path="${dataset_path}/annotation"
# 训练集数据路径
train_data_path="${dataset_path}/${trainer_name}_${task_type}/train"
# 验证集数据路径
valid_data_path="${dataset_path}/${trainer_name}_${task_type}/valid"
# 创建路径
mkdir -p "${dataset_path}" "${annotation_data_path}" "${train_data_path}" "${valid_data_path}"


# 获取标注系统数据库文件
if [ "${task_type}" == "ocr" ]; then
  dpid=$(docker ps -a | grep "label_studio-${model_name}" | awk '{print $1}')
  docker cp ${dpid}:/label-studio/data  ${annotation_data_path}/
  # 从数据库文件中获取标注数据
  echo "[Data preprocess] load annotation data"
  docker run \
    --rm \
    -v ${annotation_data_path}:/annotation \
    -v ${annotation_data_path}/data:/data \
    $appendix_image_name:"$appendix_image_version" \
    /root/miniconda3/bin/python -m train_appendix.annotation.label_studio_dataset \
    /data ${annotation_project_id} /annotation
else
  dpid=$(docker ps -a | grep "doccano-${model_name}" | awk '{print $1}')
  docker cp ${dpid}:/data/doccano.db ${annotation_data_path}/
  # 从数据库文件中获取标注数据
  echo "[Data preprocess] load annotation data"
  docker run \
    --rm \
    -v ${annotation_data_path}:/data \
    $appendix_image_name:"$appendix_image_version" \
    /root/miniconda3/bin/python -m train_appendix.annotation.annotation_dataset \
    /data/doccano.db ${annotation_project_id} /data/data.jsonl
fi


# 切分数据
if [ "${task_type}" == "ocr" ]; then
  docker run --rm  \
      -v $annotation_data_path:/data/annotation \
      -v $train_data_path:/data/train \
      -v $valid_data_path:/data/valid \
      $appendix_image_name:"$appendix_image_version" \
      /root/miniconda3/bin/python -m train_appendix.doietk.ocr_dataset_trans \
      /data/annotation/data.jsonl /data/annotation/images /data/train /data/valid \
      ${document_parser_url} \
      --train_ratio $train_ratio
else
  if [ "${trainer_name}" == "doietk" ]; then
    docker run --rm  \
      -v $annotation_data_path/data.jsonl:/data/annotation/data.jsonl \
      -v $train_data_path:/data/train \
      -v $valid_data_path:/data/valid \
      $appendix_image_name:"$appendix_image_version" \
      /root/miniconda3/bin/python -m train_appendix.doietk.dataset_trans \
      /data/annotation/data.jsonl /data/train /data/valid \
      --train_ratio $train_ratio --neg_pos_rate $neg_pos_rate
  else
    mkdir -p "${train_root_path}/dict"
    model_dict=${train_root_path}/dict/schema.dic
    valid_ratio=$(echo "1-$train_ratio"|bc)
    ratio="$train_ratio 0$valid_ratio 0"
    cls_options='["根据label自动生成"]'
    cls_prompt_prefix="类别"

    docker run --rm \
      -v"${annotation_data_path}":/data \
      $appendix_image_name:"$appendix_image_version" \
      /root/miniconda3/bin/python -m train_appendix.uie.dataset_trans \
      --doccano_file "/data/data.jsonl" \
      --task_type "$task_type" \
      --options "${cls_options}" \
      --prompt_prefix "${cls_prompt_prefix}" \
      --save_dir /data \
      --splits $ratio
    mv "${annotation_data_path}/schema.dic" "${train_root_path}/dict/schema.dic"
    mv "${annotation_data_path}/train.txt" "${dataset_path}/${trainer_name}_${task_type}/train.jsonl"
    mv "${annotation_data_path}/dev.txt" "${dataset_path}/${trainer_name}_${task_type}/valid.jsonl"
  fi
fi