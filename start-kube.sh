#!/bin/bash
set -euxo pipefail
K8S_VERSION=1.3.6
PROXY_MODE="userspace"  #allowed values: userspace, iptables
ETH0=$(hostname -I | cut -d" " -f1)

if [ ! -f $(pwd)/kubectl ]; then
	wget https://storage.googleapis.com/kubernetes-release/release/v${K8S_VERSION}/bin/linux/amd64/kubectl
	chmod +x kubectl
fi

docker run --name k8s-etcd -d --net=host gcr.io/google_containers/etcd:2.2.1 /usr/local/bin/etcd --listen-client-urls=http://${ETH0}:4001 --advertise-client-urls=http://${ETH0}:4001 --data-dir=/var/etcd/data
docker run --name setup-files -d -v /etc/k8s/data:/data gcr.io/google_containers/hyperkube-amd64:v${K8S_VERSION} /setup-files.sh IP:${ETH0},DNS:kubernetes,DNS:kubernetes.default,DNS:kubernetes.default.svc,DNS:kubernetes.default.svc.cluster.local
sleep 10s
docker run --name k8s-api -d --net=host -v /etc/k8s/data:/srv/kubernetes gcr.io/google_containers/hyperkube-amd64:v${K8S_VERSION} /hyperkube apiserver --service-node-port-range=1-65535 --bind-address=0.0.0.0 --insecure-bind-address=0.0.0.0 --etcd_servers=http://${ETH0}:4001 --allow-privileged=true --secure_port=7443 --runtime-config=extensions/v1beta1/daemonsets=true --admission-control=NamespaceLifecycle,NamespaceExists,LimitRanger,SecurityContextDeny,ServiceAccount,ResourceQuota --client-ca-file=/srv/kubernetes/ca.crt --basic-auth-file=/srv/kubernetes/basic_auth.csv --min-request-timeout=300 --tls-cert-file=/srv/kubernetes/server.cert --tls-private-key-file=/srv/kubernetes/server.key --token-auth-file=/srv/kubernetes/known_tokens.csv --service-cluster-ip-range=10.3.0.0/24 --service-account-key-file=/srv/kubernetes/server.key
docker run --name k8s-controller -d --net=host -v /etc/k8s/data:/srv/kubernetes gcr.io/google_containers/hyperkube-amd64:v${K8S_VERSION} /hyperkube controller-manager --master=${ETH0}:8080 --service-account-private-key-file=/srv/kubernetes/server.key --root-ca-file=/srv/kubernetes/ca.crt --min-resync-period=3m
docker run --name k8s-scheduler -d --net=host gcr.io/google_containers/hyperkube-amd64:v${K8S_VERSION} /hyperkube scheduler --master=${ETH0}:8080
docker run --name k8s-proxy -d --net=host --privileged=true gcr.io/google_containers/hyperkube-amd64:v${K8S_VERSION} /hyperkube proxy --master=http://${ETH0}:8080 --proxy-mode=${PROXY_MODE}
docker run --name k8s-kubelet -d --net=host --pid=host  --privileged=true -v /:/rootfs:ro -v /sys:/sys:ro -v /var/lib/docker/:/var/lib/docker:rw -v /var/lib/kubelet/:/var/lib/kubelet:rw -v /var/run:/var/run:rw gcr.io/google_containers/hyperkube-amd64:v${K8S_VERSION} /hyperkube kubelet --containerized --hostname-override="${ETH0}" --address="0.0.0.0" --api-servers=http://${ETH0}:8080 --cluster-dns=${ETH0} --cluster-domain=cluster.local --allow-privileged=true --register-node=true
sleep 30s
curl -XPOST -H 'Content-Type: application/json; charset=UTF-8' -d'{"apiVersion":"v1","kind":"Namespace","metadata":{"name":"kube-system"}}' "http://${ETH0}:8080/api/v1/namespaces"
docker run --name k8s-kube2sky -d --net=host gcr.io/google_containers/kube2sky:1.11 -domain=cluster.local -kube_master_url=http://${ETH0}:8080 -etcd-server=http://${ETH0}:4001
docker run --name k8s-skydns -d --net=host gcr.io/google_containers/skydns:2015-03-11-001 -machines=http://${ETH0}:4001 -addr=0.0.0.0:53 -domain=cluster.local

curl -sS https://rawgit.com/kubernetes/dashboard/master/src/deploy/kubernetes-dashboard.yaml > kubernetes-dashboard.yaml
sed -i "s|#.*--apiserver-host.*$|- --apiserver-host=http://${ETH0}:8080|" kubernetes-dashboard.yaml
kubectl create -f kubernetes-dashboard.yaml
rm -f kubernetes-dashboard.yaml

docker run --volume=/:/rootfs:ro --volume=/var/run:/var/run:rw --volume=/sys:/sys:ro --volume=/var/lib/docker/:/var/lib/docker:ro --publish=8081:8080 --detach=true --name=cadvisor google/cadvisor:latest

cat <<- EOF > "heapster_hosts"
{
  "Items": [
    {
      "Name": "server-1",
      "IP": "${ETH0}"
    }
  ]
}
EOF

curl -s "https://s3.amazonaws.com/draios-testinfrastructure/kubernetes-demo/graphana-kube-dash.json" > kubernetes.json
docker run --name influxdb -d -p 8083:8083 -p 8086:8086 kubernetes/heapster_influxdb
docker run --name heapster -v $(pwd)/heapster_hosts:/var/run/heapster/hosts -d kubernetes/heapster:v0.14.2 --sink="influxdb:http://${ETH0}:8086" --source="cadvisor:external?cadvisorPort=8081" 
docker run --name grafana -d -p 8043:8080 -e INFLUXDB_HOST=${ETH0} -v $(pwd)/kubernetes.json:/opt/grafana/app/dashboards/kubernetes.json kubernetes/heapster_grafana:v0.7
