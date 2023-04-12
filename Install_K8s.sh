#!/bin/bash

# Disable swap 
sudo swapoff -a

# ----------   Configure prerequisites  ( kubernetes.io/docs/setup/production-environment/container-runtimes/ )
sudo cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

sudo cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system
 
lsmod | grep br_netfilter
lsmod | grep overlay

# Verify that is all outcomes are 1
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward

# ----------   Installation Of CRI -  CONTAINERD and Docker using Package ( https://docs.docker.com/engine/install/ubuntu/ )
#              using Binary - ( https://github.com/containerd/containerd/blob/main/docs/getting-started.md  )

sudo apt-get remove docker docker-engine docker.io containerd runc -y
sudo apt-get update
sudo apt-get install ca-certificates curl gnupg -y

sudo mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y

if docker ps | grep -q 'CONTAINER ID   IMAGE     COMMAND   CREATED   STATUS    PORTS     NAMES'; then
	    echo "Docker Installed successfully!"
    else echo  "Docker Installtion failed"
	            exit 1
fi

# ----------   Edit the Containerd Config file /etc/containerd/config.yaml
#              by default this config file conatains disable CRI so need to remove it and add required stuff suggested by K8s doc
if [ -f /etc/containerd/config.toml ]; then
	sudo rm -f /etc/containerd/config.toml
#	sudo dd of=/etc/containerd/config.toml << EOF
#[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
#  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
#    SystemdCgroup = true
#EOF  
        containerd config default > /etc/containerd/config.toml
        sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
fi
sudo systemctl restart containerd

# ----------  Installing kubeadm, kubelet and kubectl 
#             ( kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#installing-kubeadm-kubelet-and-kubectl  )
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl 
sudo curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg

#             should create keyrings dir if not present 
if [ ! -d /etc/apt/keyrings]; then
	mkdir /etc/apt/keyrings
fi

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

echo "Installing of k8s component is Successfull"

echo "\nversion of kubeadm - $(kubeadm version | cut -d " " -f 5 | tr -d 'GitVersion:",') "
echo "version of kubelet - $(kubelet --version | awk '{print $2}')"
echo "version of kubectl - $( kubectl version -o json 2>/dev/null | grep gitVersion | tr -d 'gitVersion:", ')\n"

sudo systemctl daemon-reload
sudo systemctl restart kubelet

# ---------- Common configuration for both worker and master node is DONE
# ---------- Below one is For Master Node ( control-plane )
echo "\n At this stage your node is ready to work as worker node by adding join-token of cluster node"
read -p "To make it Control-plane ( master-node ) Enter 0 ,For Exit Enter 1  : " user_input
if [ "$user_input" -eq 0 ];then
        user_ip = hostname -I | awk '{print $1}'
	echo "Initializing Kubeadm , may take some time"
	# --------------- if coredn or CNI fails then check is --pod-network-cidr are overlapping or not by kubectl describe pod weave_____ & is passing cidr is good practice
	if sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=$user_ip --ignore-preflight-errors=all | grep -q 'kubeadm join';then
		echo ""
		
	else 
		sudo kubeadm reset
		sudo systemctl daemon-reload
		sudo systemctl restart kubelet
		sudo systemctl status kubelet
		sudo kubeadm init --apiserver-advertise-address=$user_ip --ignore-preflight-errors=all -y
        fi
	sudo mkdir -p $HOME/.kube
	sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
	sudo chown $(id -u):$(id -g) $HOME/.kube/config
        sudo kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml 
	echo "\n Control-Plane is Ready \n"
	sudo kubectl get nodes
	echo "\n copy below one token to pass it to Worker Nodes\n"
	sudo kubeadm token create --print-join-command
	echo "\n----- complete -----\n"
	sudo systemctl daemon-reload
	sudo systemctl daemon-reload
	sudo kubectl get nodes
	echo "please restart daemon-reload once again [ systemctl daemon-reload ] then [ kubectl get nodes ]"
else
	echo "\nTo make this NODE as control plane, Refer - kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/\n"
	echo "\n----- complete -----\n"
	sudo systemctl daemon-reload
fi









