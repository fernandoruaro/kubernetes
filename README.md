## HA Kubernetes from scratch on AWS using Terraform + Ansible

The main objectives of this project is to provide an easy way to deploy a HA Kubernetes cluster that you have full control of it. Different from commands like `kube-up.sh` that creates the whole infra and then makes it difficult for you to manage it later, the idea here is to use only Terraform and Ansible.


This project started using this project (https://github.com/nicusX/k8s-terraform-ansible-sample) as base. Some of the code you see here are copied from there.


### Overview

The cluster is separeted in 4 main roles:

- etcd
 - **What?** It's a key-value database used by Kubernetes master.
 - **Implementation:** A set of instances responsible for running etcd servers that peers with each other. These instances are distributed between different AZ's. 

- master
 - **What?** The services needed to manage the Kubernetes cluster: API server, controller manager and scheduler.
 - **Implementation:** Multiple instances distributed in differet AZ's that communicates with the etcd cluster.
 
- minion
 - **What?** Services needed to run pods on the host: Docker, Kube Proxy and Kubelet.
 - **Implementation:** Multiple instances able to communicate with the master and receive the scheduled pods.
 
- deployer
 - **What?** Way for executing `kubectl` commands in the cluster and setting AWS route table according to the minions ip.
 - **Implementation:** Machine that has credentials to access the master and AWS CLI.
 
### Prerequisites

First you will need an AWS instance or AWS credentials that has rights for managing the infrastructure.

In the host, you will have the following dependecies to install:

- **Ansible**

```shell
sudo easy_install pip
sudo pip install ansible
sudo mkdir /etc/ansible/
sudo chmod 757 -R /etc/ansible/
```




- **Terraform**


```shell
mkdir terraform
cd terraform/
wget https://releases.hashicorp.com/terraform/0.8.6/terraform_0.8.6_linux_amd64.zip
unzip terraform_0.8.6_linux_amd64.zip
echo "export PATH=$PWD:$PATH" >> ~/.bashrc
export PATH=$PWD:$PATH
cd ..

```

```shell
mkdir keys
export KEY_NAME=cluster_key #SET A NAME FOR YOUR KEY HERE
cd keys
ssh-keygen -t rsa -b 4096 -C "Kubernetes Cluster Key" -f "${KEY_NAME}" -N ""
cd ..
echo public_key=$(cat "keys/${KEY_NAME}.pub") >> terraform/terraform.tfvars
```

### Running!


**Terraform**

```shell
export TF_VAR_control_cidr=$(wget -qO- http://ipecho.net/plain)
terraform get -var-file="terraform.tfvars"
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"

```
**Moving Terraform variables to Ansible**

```shell
./pass_var_terraform_to_ansible.sh
```
ansible-galaxy install franklinkim.newrelic

**01-basic-requirements**


```shell
ansible-playbook 01-basic-requirements.yaml --private-key=../keys/${KEY_NAME} --extra-vars "@terraform_vars"  --extra-vars "newrelic_license_key=INSERT_YOUR_KEY_HERE"

```

**02-etcd-cluster**

```shell
ansible-playbook 02-etcd-cluster.yaml --private-key=../keys/${KEY_NAME} --extra-vars "@terraform_vars"  --extra-vars "newrelic_license_key=INSERT_YOUR_KEY_HERE"

```

**03-master-cluster**

```shell
ansible-playbook 03-master-cluster.yaml --private-key=../keys/${KEY_NAME} --extra-vars "@terraform_vars"  --extra-vars "newrelic_license_key=INSERT_YOUR_KEY_HERE"

```

**04-minions-and-kube-services**

```shell
ansible-playbook 04-minions-and-kube-services.yaml --private-key=../keys/${KEY_NAME} --extra-vars "@terraform_vars"  --extra-vars "newrelic_license_key=INSERT_YOUR_KEY_HERE"

```

