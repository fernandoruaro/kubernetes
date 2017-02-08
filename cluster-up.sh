#!/bin/bash

##Create infrastructure and inventory file
echo "Creating infrastructure"
cd tf
terraform apply

##Run Ansible playbooks
echo "Quick sleep while instances spin up"
sleep 120
echo "Ansible provisioning"
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i ../kargo/inventory/inventory -u ubuntu -b ../kargo/cluster.yml
