# !/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
标注系统的sqlite文件转换为标注数据

Authors: zhaiwenyu
Date: 2022/08/19 00:00:00
"""

import os
import sys
import copy
import json
import logging
import argparse
import sqlite3


class DatabaseSample(object):
    """
    label studio平台的数据库提取，目前支持文本分类，文本抽取，OCR
    
    Attributes:
        label_data_path: 需要标注数据的位置
        templates_path: sql template的位置
        label_studio_sql_template: 从label studio提取数据的sql
        sql_conn: 数据库连接
        curse: 数据库连接
    """
    def __init__(self, label_data_path="./data"):
        self.label_data_path = label_data_path
        self.templates_path = os.path.dirname(os.path.abspath(__file__)) + "/examples_sql_templates"
        self.label_studio_sql_template = open(self.templates_path + "/label_studio_examples_sql.template", "r").read()
        self.sql_conn = sqlite3.connect(os.path.join(label_data_path, "label_studio.sqlite3"))
        self.curse = self.sql_conn.cursor()

    def load_samples_from_annotation_db(self, project_id, output_path):
        """
        获取数据
        :param project_id: 工程ID
        """
        label_studio_examples_sql = self.label_studio_sql_template.replace("{{project_id}}", str(project_id))

        self.curse.execute(label_studio_examples_sql)

        # 判断任务是OCR, 文本分类或者文本抽取
        mission_type = ''
        all_element = self.curse.fetchall()
        fetch_first = json.loads(all_element[0][2])[0]
        if "original_width" in fetch_first:
            mission_type = 'ocr'
            self.load_ocr_from_annotation_db(all_element, output_path)

        elif fetch_first["from_name"] == 'sentiment':
            mission_type = 'text_classification'
            self.load_classification_from_annotation_db(all_element, output_path)

        else:
            mission_type = 'text_extraction'
            self.load_extraction_from_annotation_db(all_element, output_path)


    def load_ocr_from_annotation_db(self, all_element, output_path):
        """
            OCR任务 获取数据
            Attributes:
                all_element: 从sql获取到的数据
                output_path: 输出路径

        """
        output = []
        for elem in all_element:
            temp_dict = {
                "id":elem[0],
                "data":json.loads(elem[1]),
                "result":json.loads(elem[2])
            }
        output.append(copy.deepcopy(temp_dict))

        # 保存标注的json数据
        result_json_path = os.path.join(output_path, "data.jsonl")
        with open(result_json_path, "w") as fp:
            fp.write("\n".join([json.dumps(elem, ensure_ascii=False) for elem in output]))

        # 保存标注对应的图像数据
        media_input_dir_path = os.path.join(self.label_data_path, "media/")
        media_output_dir_path = os.path.join(output_path, "images/")
        if not os.path.exists(media_output_dir_path):
            os.makedirs(media_output_dir_path)
        for item in output:
            media_image_list = list(item["data"].values())
            if len(media_image_list) > 0:
                media_image_path = media_image_list[0].replace("/data/", "")
                source_file = os.path.join(media_input_dir_path, media_image_path)
                target_file = os.path.join(media_output_dir_path, media_image_path.split("/")[-1])
                cmd_line = "cp %s %s" % (source_file, target_file)
                os.system(cmd_line)


    def load_classification_from_annotation_db(self, all_element, output_path):
        """
            文本分类任务 获取数据
            Attributes:
                all_element: 从sql获取到的数据
                output_path: 输出路径

        """
        dict_output = {}
        output = []
        for elem in all_element:
            # 文本分类的text
            context_data = json.loads(elem[1])['text']
            # 标注后的label
            context_result = json.loads(elem[2])[0]['value']['choices'][0]

            if context_data not in dict_output:
                dict_output[context_data] = []
            dict_output[context_data].append(context_result)

        output = [
            {
                "text": key,
                "label": copy.deepcopy(dict_output[key])
            } for key in dict_output
        ]

        # 保存标注的json数据
        result_json_path = os.path.join(output_path, "data.jsonl")
        with open(result_json_path, "w") as fp:
            fp.write("\n".join([json.dumps(elem, ensure_ascii=False) for elem in output]))


    def load_extraction_from_annotation_db(self, all_element, output_path):
        """
            文本抽取任务 获取数据
            Attributes:
                all_element: 从sql获取到的数据
                output_path: 输出路径

        """
        dict_output = {}
        output = []
        for elem in all_element:
            # 文本抽取的text
            context_data = json.loads(elem[1])['text']

            if context_data not in dict_output:
                dict_output[context_data] = {"entities": [], "relations": []}
            
            # 标注后的信息
            context_label = json.loads(elem[2])
            for i in range(len(context_label)):
                # 标注后的entity
                if context_label[i]['type'] == 'labels':
                    entity_dict = {}
                    entity_dict["id"] = context_label[i]['id']
                    entity_dict["start_offset"] = context_label[i]['value']['start']
                    entity_dict["end_offset"] = context_label[i]['value']['end']
                    entity_dict["label"] = context_label[i]['value']['labels'][0]

                    dict_output[context_data]["entities"].append(entity_dict)
                # 标注后的relation
                if context_label[i]['type'] == 'relation':
                    relation_dict = {}
                    # label studio 的relation标注没有id字段，取其在list中的位置作为id, 保持和原来格式一致
                    relation_dict["id"] = i
                    relation_dict["from_id"] = context_label[i]['from_id']
                    relation_dict["to_id"] = context_label[i]['to_id']
                    relation_dict["type"] = context_label[i]['labels'][0]

                    dict_output[context_data]["relations"].append(relation_dict)
            
        output = [
            {
                "text": key,
                "entities": copy.deepcopy(dict_output[key]["entities"]),
                "relations":copy.deepcopy(dict_output[key]["relations"])
            } for key in dict_output
        ]       
                
        # 保存标注的json数据
        result_json_path = os.path.join(output_path, "data.jsonl")
        with open(result_json_path, "w") as fp:
            fp.write("\n".join([json.dumps(elem, ensure_ascii=False) for elem in output]))


def main():
    """
        Attributes: 
        label_data_path: 需要标注数据的位置
        project_id: project id 
        output_path: 输出路径
    """
    log_format = "%(asctime)s %(filename)s[line:%(lineno)d] %(levelname)s %(message)s"
    logging.basicConfig(level=logging.INFO, format=log_format, stream=sys.stderr)
    parser = argparse.ArgumentParser()
    parser.add_argument("label_data_path", type=str, help="Annotation Label Studio Data path")
    parser.add_argument("project_id", type=int, help="Project ID")
    parser.add_argument("output_path", type=str, help="Output result path")
    args = parser.parse_args()
    DatabaseSample(
        label_data_path=args.label_data_path
    ).load_samples_from_annotation_db(
        project_id=args.project_id, output_path=args.output_path
    )


if __name__ == '__main__':
    main()
