#!/bin/bash

cd terraform
VAR_FILE=../ansible/terraform_vars
touch $VAR_FILE
JSON="{"
JSON=$JSON"\"kubernetes_route_table_id\":\"$(terraform output kubernetes_route_table_id)\","
JSON=$JSON"\"kubernetes_master_url\":\"$(terraform output kubernetes_master_url)\","
JSON=$JSON"\"kubernetes_etcd_url\":\"$(terraform output kubernetes_etcd_url)\""
JSON=$JSON"}"
echo $JSON > $VAR_FILE