#!/bin/bash
set -e

ENV=$1
echo "Deploying $ENV"


eval "$(ssh-agent -s)"
ssh-add ~/.ssh/github


rm -rf executive_alerts_cluster_config
git clone -b "deploy-$ENV" git@github.com:meltwater/executive_alerts_cluster_config.git

cd executive_alerts_cluster_config


SECRETS_BUCKET=secrets-kube-01
SECRETS_FOLDER=secrets


if [ ! $(kubectl get namespaces -o name | grep "namespace/staging") ]; then
  kubectl create namespace $ENV
fi



aws s3 cp s3://${SECRETS_BUCKET} ${SECRETS_FOLDER} --recursive

cd ${SECRETS_FOLDER}/${ENV}
for secret in `ls`; do 
  command="kubectl create secret generic ${secret} --namespace=$ENV "$(for x in `ls $secret`; do echo -ne "--from-file=$x=$secret/$x "; done)
  kubectl delete secret ${secret} --ignore-not-found --namespace=$ENV
  echo ${command}
  ${command}
done


cd ../../ 
rm -rf ${SECRETS_FOLDER}/${ENV}


kubectl apply -f config/ea-config.yaml -R --namespace=$ENV
kubectl apply -f ea -R --namespace=$ENV

cd ..

rm -rf executive_alerts_cluster_config/


kubectl get pods --namespace=$ENV