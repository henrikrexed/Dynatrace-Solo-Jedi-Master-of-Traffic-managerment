#!/usr/bin/env bash

export GLOO_MESH_VERSION=v2.4.1
export REVISION=1-19

export CLUSTER_CONTEXT=$(kubectl config current-context)

if [ -z "$GLOO_MESH_LICENSE_KEY" ]; then
  echo "Error: GLOO_MESH_LICENSE_KEY not set!"
  exit 1
fi


kubectl create ns istio-gateways
kubectl label namespace istio-gateways istio.io/rev=1-19

istioctl install -f ./gloo-mesh/istio-values.yaml -y

kubectl create ns gloo-mesh-addons
kubectl label namespace gloo-mesh-addons istio.io/rev=1-19

kubectl create ns gloo-mesh
kubectl delete dynatrace -n gloo-mesh

kubectl create secret generic dynatrace  --from-literal=dynatrace_oltp_url="$DTURL" --from-literal=dt_api_token="$DTTOKEN" -n gloo-mesh

meshctl install \
  --kubecontext $CLUSTER_CONTEXT \
  --license $GLOO_MESH_LICENSE_KEY \
  --set global.cluster=mgmt-cluster \
  --chart-values-file ./gloo-mesh/gloomesh-values.yaml

kubectl apply -f ./gloo-mesh/gloomesh-resources.yaml

export ENDPOINT_HTTP_GW_CLUSTER1=$(kubectl -n istio-gateways get svc -l istio=ingressgateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].*}'):80
echo "GLOO MESH UI: http://${ENDPOINT_HTTP_GW_CLUSTER1}/ui"