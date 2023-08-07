#!/bin/bash

# 1、获取参数
if [ $# -lt 2 ] ; then
  read -p "Please input annotation tool(0:doccano,1:label_studio)[0|1]:" annotation_type
  read -p "Please input your annotation port:" annotation_port
else
  annotation_type=1
  export annotation_port=$1
fi



# 2、获取基础参数及资源配置文件路径
root_path=$(dirname "$PWD")
model_name=`ls ${root_path}/workspace|tail -1|awk -F 'train-' '{print $NF}'`
train_root_path="${root_path}/workspace/train-${model_name}"
# 资源配置文件路径
source_file="${root_path}/workspace/train-${model_name}/source.ini"

# 3、根据选择类型启动标注系统
if [ ${annotation_type} == 0 ]; then
  # 下载doccano标注系统
  doccano_image_name=$(grep "doccano_image_name" "$source_file" | awk -F ":" '{print $2}')
  doccano_image_version=$(grep "doccano_image_version" "$source_file" | awk -F ":" '{print $2}')
  annotation_image=${doccano_image_name}:${doccano_image_version}
  echo "[Pulling] doccano image ${annotation_image}"
  docker pull ${annotation_image}

  # 启动服务
  docker run -itd \
      --name "doccano-${model_name}-$annotation_port" \
      -e "ADMIN_USERNAME=admin" \
      -e "ADMIN_EMAIL=admin@example.com" \
      -e "ADMIN_PASSWORD=admin" \
      -p ${annotation_port}:8000 \
      ${annotation_image}

  sleep 10
  annotation_url="http://$(hostname):${annotation_port}"
  echo "http://$(hostname):${annotation_port}"
  echo "username: admin"
  echo "password: admin"
  echo "You can start annotate use the account."
else
  # 下载label_studio_image_name标注系统
  label_studio_image_name=$(grep "label_studio_image_name" "$source_file" | awk -F ":" '{print $2}')
  label_studio_image_version=$(grep "label_studio_image_version" "$source_file" | awk -F ":" '{print $2}')
  annotation_image=${label_studio_image_name}:${label_studio_image_version}
  echo "[Pulling] label-studio image ${annotation_image}"
  docker pull ${annotation_image}

  # 启动服务
  docker run -itd \
      --name "label_studio-${model_name}-$annotation_port" \
      -p ${annotation_port}:8080 \
      ${annotation_image} \
      label-studio

  sleep 20
  annotation_url="http://$(hostname):${annotation_port}"
  echo "http://$(hostname):${annotation_port}"
  echo "username: default_user@localhost"
  echo "password: default_user"
  echo "You can start annotate use the account."
fi