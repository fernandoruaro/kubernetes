#!/bin/bash

log_info () {
  echo "[$(date)] ${1}"
}

main () {
  set -e
  set -u

  enviroment=${1:-staging}
  secrets_bucket=${SECRETS_BUCKET:-secrets-kube-01}
  secrets_path="${HOME}/deploy/${enviroment}/secrets"
  github_org=${GITHUB_ORG:-meltwater}
  github_repo=${GITHUB_REPO:-executive_alerts_cluster_config}
  repo_path="${HOME}/deploy/${enviroment}/${github_repo}"
  repo_secrets_path="${repo_path}/secrets"

  log_info "Deploying ${enviroment}."
  clone_repo $enviroment $github_org $github_repo $repo_path
  fetch_secrets $enviroment $secrets_bucket $secrets_path
  check_secrets $secrets_path $repo_secrets_path
  create_namespace $enviroment
  apply_secrets $enviroment $secrets_path
  apply_config $enviroment $repo_path
  cleanup $repo_path $secrets_path
  log_info "Deployed ${enviroment}."
  get_status $enviroment
}


clone_repo () {
  enviroment=$1
  org=$2
  repo=$3
  repo_path=$4
  branch="deploy-${enviroment}"
  ssh_key="${HOME}/.ssh/github"
  repo_url="git@github.com:${org}/${repo}.git"
  travis_file="${repo_path}/.travis.yml"

  log_info "Adding ssh key ${ssh_key} to ssh-agent."
  eval "$(ssh-agent -s)"
  ssh-add $ssh_key

  log_info "Removing ${repo_path}"
  rm -rf $repo_path

  log_info "Cloning ${repo_url}#${branch} to ${repo_path}."
  echo
  git clone --branch $branch --depth 2 $repo_url $repo_path
  echo

  log_info "Deploying this commit:"
  echo
  (cd $repo_path && git --no-pager log -1)
  echo

  log_info "Removing ${travis_file}."
  rm -rf $travis_file
}

fetch_secrets () {
  enviroment=$1
  bucket=$2
  secrets_path=$3
  bucket_path="s3://${bucket}/${enviroment}"

  log_info "Removing ${secrets_path}."
  rm -rf $secrets_path

  log_info "Creating ${secrets_path}."
  mkdir -p $secrets_path

  log_info "Fetching secrets from ${bucket_path} to ${secrets_path}."
  echo
  aws s3 cp --recursive $bucket_path $secrets_path
  echo
}

check_secrets () {
  secrets_path=$1
  repo_secrets_path=$2
  secrets_list="${HOME}/deploy/${enviroment}-secrets.txt"
  repo_secrets_list="${HOME}/deploy/${enviroment}-repo-secrets.txt"

  log_info "Checking list of required secrets in ${repo_secrets_path} is identical to ${secrets_path}."
  (cd $secrets_path && find . -type f > $secrets_list)
  (cd $repo_secrets_path && find . -type f > $repo_secrets_list)
  echo
  diff $secrets_list $repo_secrets_list
  echo
  rm -rf $secrets_list $repo_secrets_list

  log_info "Removing ${repo_secrets_path}."
  rm -rf $repo_secrets_path
}

create_namespace () {
  enviroment=$1
  kubectl get namespace ${enviroment} || kubectl create namespace $enviroment
}

apply_secrets () {
  enviroment=$1
  secrets_path=$2

  log_info "Creating all Kubernetes secrets for namespace ${enviroment} from files in ${secrets_path}."

  (cd $secrets_path \
    && find * -type d -exec \
      kubectl --namespace=$enviroment get secret {} || \
      kubectl --namespace=$enviroment delete secret {} \; \
    && find * -type d -exec \
      kubectl --namespace=$enviroment create secret generic {} --from-file={} \;)
}

apply_config () {
  enviroment=$1
  repo_path=$2

  log_info "Applying Kubernetes configuration for namespace ${enviroment} in ${repo_path}."
  echo
  kubectl apply --namespace=$enviroment --recursive --filename $repo_path
  echo
}

cleanup () {
  repo_path=$1
  secrets_path=$2

  log_info "Removing ${repo_path}."
  rm -rf $repo_path

  log_info "Removing ${secrets_path}."
  rm -rf $secrets_path
}

get_status () {
  enviroment=$1

  log_info "Waiting two minutes and then getting pod status."
  sleep 60
  log_info "Waiting one minute and then getting pod status."
  sleep 50
  log_info "Waiting 10 seconds then getting pod status."
  sleep 10
  echo
  kubectl --namespace=$enviroment describe pods
  echo
  kubectl --namespace=$enviroment get pods
  echo
}

main ${1:-$DEPLOY_ENV}
