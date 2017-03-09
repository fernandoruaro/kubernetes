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
echo public_key=\"$(cat "keys/${KEY_NAME}.pub")\" >> terraform/terraform.tfvars
```

### Running!


**Terraform**

```shell
export TF_VAR_control_cidr=$(wget -qO- http://ipecho.net/plain)/32
terraform get 
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"

```
**Moving Terraform variables to Ansible**

```shell
./pass_var_terraform_to_ansible.sh
```


 ansible-galaxy install -r requirements.yml

**01-basic-requirements**


```shell
ansible-playbook 01-basic-requirements.yaml --private-key=../keys/${KEY_NAME} --extra-vars "@terraform_vars"  --extra-vars "newrelic_license_key=INSERT_YOUR_KEY_HERE"

```

**02-etcd-cluster**

```shell
ansible-playbook 02-etcd-cluster.yaml --private-key=../keys/${KEY_NAME} --extra-vars "@terraform_vars"

```

**03-master-cluster**

```shell
ansible-playbook 03-master-cluster.yaml --private-key=../keys/${KEY_NAME} --extra-vars "@terraform_vars"

```

**04-minions-and-kube-services**

```shell
ansible-playbook 04-minions-and-kube-services.yaml --private-key=../keys/${KEY_NAME} --extra-vars "@terraform_vars"

```










------


Certificates


wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
chmod +x cfssl_linux-amd64
sudo mv cfssl_linux-amd64 /usr/local/bin/cfssl

wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
chmod +x cfssljson_linux-amd64
sudo mv cfssljson_linux-amd64 /usr/local/bin/cfssljson

cd keys

echo '{
  "signing": {
    "default": {
      "expiry": "8760h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "8760h"
      }
    }
  }
}' > ca-config.json


echo '{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "Kubernetes",
      "OU": "CA",
      "ST": "Oregon"
    }
  ]
}' > ca-csr.json


cfssl gencert -initca ca-csr.json | cfssljson -bare ca

cat > kubernetes-csr.json <<EOF
{
  "CN": "kubernetes",
  "hosts": [
    "127.0.0.1",
    "172.100.43.29",
    "ip-172-100-43-29",

    "172.100.3.225",
    "ip-172-100-3-225",
    
	"172.100.7.213",
    "ip-172-100-7-213",
    
    "172.100.25.53",
    "ip-172-100-25-53",
    
    "172.100.18.133",
    "ip-172-100-18-133",
    
    "172.100.36.187",
    "ip-172-100-36-187",
    
    "172.100.10.149",
    "ip-172-100-10-149",

    "172.100.9.73",
    "ip-172-100-9-73",

    "172.100.36.96",
    "ip-172-100-36-96",

    "172.100.19.14",
    "ip-172-100-19-14",

    "172.100.12.243",
    "ip-172-100-12-243",

    "*.ec2.internal",
    
    "internal-tf-master-kube-01-1131071443.us-east-1.elb.amazonaws.com"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "US",
      "L": "Portland",
      "O": "Kubernetes",
      "OU": "Cluster",
      "ST": "Oregon"
    }
  ]
}
EOF

cfssl gencert \
  -ca=ca.pem \
  -ca-key=ca-key.pem \
  -config=ca-config.json \
  -profile=kubernetes \
  kubernetes-csr.json | cfssljson -bare kubernetes






------------------------------------------------

GENERATE SECRETS


SECRETS_BUCKET=secrets-kube-01
SECRETS_FOLDER=secrets
ENV=staging


aws s3 cp s3://${SECRETS_BUCKET} ${SECRETS_FOLDER} --recursive

cd ${SECRETS_FOLDER}/${ENV}

for secret in `ls`; do 
	command="kubectl create secret generic ${secret} "$(for x in `ls $secret`; do echo -ne "--from-file=$x=$secret/$x "; done)
	kubectl delete secret ${secret} --ignore-not-found
	echo ${command}
	${command}
done

cd ../../



-----------------------------------------------

TODO

- Support EBS volumes