# How to become the Jedi Master of Traffic management with Dynatrace and Solo.io

This repository contains the files required for the demo presented during the joint webinar organized by Dynatrace and Solo.io

This repository showcase the usage of several solutions:

* Gloo Platform
* The HipsterShop
* Litmus Chaos
* OpenTelemetry Collector

In this demo we will walk through the usage of Configuring Gloo Platform with:

* The hipster-shop

To reproduce well know production issue this workshop we will utilize:

* Litmus Chaos to generate disruption in the Cluster

## Prerequisite

The following tools need to be install on your machine:

* jq
* kubectl
* git
* gcloud ( if you are using GKE)
* Helm

### 1. Create a Google Cloud Platform Project

```shell
PROJECT_ID="<your-project-id>"
gcloud services enable container.googleapis.com --project ${PROJECT_ID}
gcloud services enable monitoring.googleapis.com \
cloudtrace.googleapis.com \
clouddebugger.googleapis.com \
cloudprofiler.googleapis.com \
--project ${PROJECT_ID}
```

### 2. Create a GKE cluster

```shell
ZONE=europe-west3-a
NAME=dt-solo-jedimaster
gcloud container clusters create ${NAME} --zone=${ZONE} --machine-type=e2-standard-8 --num-nodes=3
```

### 3. Clone Github repo

```shell
git clone https://github.com/henrikrexed/Dynatrace-Solo-Jedi-Master-of-Traffic-managerment
cd Dynatrace-Solo-Jedi-Master-of-Traffic-managerment
```

## Deploy


#### 1.1. Dynatrace

##### 1.1.1. Dynatrace Tenant - start a trial

If you don't have any Dyntrace tenant , then i suggest to create a trial using the following link : [Dynatrace Trial](https://bit.ly/3KxWDvY)
Once you have your Tenant save the Dynatrace (including https) tenant URL in the variable `DT_TENANT_URL` (for example : https://dedededfrf.live.dynatrace.com)

```shell
DT_TENANT_URL=<YOUR TENANT URL>
```

##### 1.1.2. Create the Dynatrace API Tokens

The dynatrace operator will require to have several tokens:

* Token to deploy and configure the various components
* Token to ingest metrics and Traces

###### 1.1.2.1 Operator Token

One for the operator having the following scope:

* Create ActiveGate tokens
* Read entities
* Read Settings
* Write Settings
* Access problem and event feed, metrics and topology
* Read configuration
* Write configuration
* Paas integration - installer downloader

<p align="center"><img src="/image/operator_token.png" width="40%" alt="operator token" /></p>

Save the value of the token . We will use it later to store in a k8S secret

```shell
API_TOKEN=<YOUR TOKEN VALUE>
```

###### 1.1.2.2 Ingest data token

Create a Dynatrace token with the following scope:

* Ingest metrics (metrics.ingest)
* Ingest logs (logs.ingest)
* Ingest events (events.ingest)
* Ingest OpenTelemtry
* Read metrics

<p align="center"><img src="/image/data_ingest_token.png" width="40%" alt="data token" /></p>

Save the value of the token . We will use it later to store in a k8S secret

```shell
DATA_INGEST_TOKEN=<YOUR TOKEN VALUE>
```

#### 1.2. Deploy Gloo Platform

1. Download Istioctl

```shell
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.19.0 sh -
```

This command download the latest version of istio ( in our case istio 1.19.0) compatible with our operating system.

1. Add istioctl to you PATH

```shell
cd istio-1.19.0
```

this directory contains samples with addons . We will refer to it later.

```shell
export PATH=$PWD/bin:$PATH
```

1. Intall Istio

Istio can be fully managed by Gloo Platform. However, this demo refers the possibility that Istio is already installed on the cluster.

```shell
kubectl create ns istio-gateways
kubectl label namespace istio-gateways istio.io/rev=1-19

istioctl install -f ./gloo-mesh/istio-values.yaml -y
```

1. Download meshctl

Meshctl is the CLI to manage Gloo Platform

```shell
curl -sL https://run.solo.io/meshctl/install | GLOO_MESH_VERSION=v2.4.2 sh -
export PATH=$HOME/.gloo-mesh/bin:$PATH
```

1. Install Gloo Platform

```shell
export GLOO_MESH_LICENSE_KEY=< your license key: https://www.solo.io/free-trial/ >
export GLOO_MESH_VERSION=v2.4.2
export REVISION=1-19

export CLUSTER_CONTEXT=$(kubectl config current-context)

kubectl create ns gloo-mesh-addons
kubectl label namespace gloo-mesh-addons istio.io/rev=1-19

kubectl create ns gloo-mesh
kubectl create secret generic dynatrace  --from-literal=dynatrace_oltp_url="${DT_TENANT_URL}" --from-literal=dt_api_token="${DATA_INGEST_TOKEN}"  -n gloo-mesh

meshctl install \
  --kubecontext $CLUSTER_CONTEXT \
  --license $GLOO_MESH_LICENSE_KEY \
  --set global.cluster=mgmt-cluster \
  --chart-values-file ./gloo-mesh/gloomesh-values.yaml
```

Apply gloo mesh resources to create a multi-tenant environment:

```shell
kubectl create ns hipster-shop
kubectl apply -f ./gloo-mesh/gloomesh-resources.yaml
```

Now you can access the Gloo Mesh UI using the following command where you will the find workspaces, services and policies:

```shell
UI=$(kubectl --context "${CLUSTER_CONTEXT}" get svc -n gloo-mesh gloo-mesh-ui -ojsonpath='{.status.loadBalancer.ingress[0].*}')
echo "http://$UI"
```

#### 1.3. Run the deployment script

```shell
cd ..
chmod 777 deployment.sh
./deployment.sh  --clustername "${NAME}" --dturl "${DT_TENANT_URL}" --dtoperatortoken "${API_TOKEN}" --dtingesttoken "${DATA_INGEST_TOKEN}" 
```

## Gloo Platform Features for this demo

With the help of OpenTelemetry, Gloo Platform can generate a Service Map of the HipsterShop application. As well, it can export telemetry to a Dynatrace.

<p align="center"><img src="/image/full-observability.png" width="40%" alt="full observability" /></p>

Other policies:
Access
Connection pool settings for HTTP
CORS
External authentication and authorization
Failover
Fault injection
Header manipulation
Load balancer and consistent hash
Mirroring
Outlier detection
Rate limit
Retry and timeout
TCP connection
Transformation
Trim proxy config
Wasm
Graphql
Internal Developer Portal
External API Management

### 1. Request timeout

Gloo Platform offers a real-life API. The service mesh capabilities have been renamed as polcies.

The productcatalog service is responding in around 1s, but with load the response time can heavily increase.
Let's protect all the other services relying on the product catalog by defining a request timeout rule.

```shell
kubectl apply -f ./gloo-mesh/retrytimeoutpolicy.yaml -n hipster-shop
```

let's run a load test

```shell
kubectl apply -f k6/loadtest_job.yaml -n hipster-shop
```

Now all the services relying on the productcalalog won't get the list of products.
so the impact is that the frontend should generate an error due to the missing product list:
<p align="center"><img src="/image/timeout.png" width="40%" alt="data token" /></p>

### 2. Rate Limit

To illustrate the usage of the rate limit we won't apply it on the productcatalog service, because it receives a limited workload.
Therefore we would apply it on the frontend service taking in peak hours 550 requests.
The rate limit will only accept 400 requests.

```shell
kubectl apply -f ./gloo-mesh/ratelimitpolicy.yaml
```

Once applied , we shoud get the following page , once the frontend gets heavy traffic:
<p align="center"><img src="/image/ratelimit_front.png" width="40%" alt="data token" /></p>

To keep track on the rate limit we need to enable the envoy metrics produced for rate limit feature.
to enable it we need to annotate the workload that has a rate limit rule with the following annotation:

```yaml
annotations:
    proxy.istio.io/config: |-
      proxyStatsMatcher:
        inclusionRegexps:
        - ".*http_local_rate_limit.*"
```

As a consequence we could Graph the number request that has been rate limit
<p align="center"><img src="/image/rate_limit_metric.png" width="40%" alt="data token" /></p>

With the metric `istio_rate_http_local_rate_limit_rate_limited.count` you can then imagine to create alerts once the value is above A or 10.

### 3. Circuit Breaker

Let's create a circuit breaker rule on the productcatalog service. This pattern is based on two implementations: a connection handlers and a outlier detection.

```shell
kubectl apply -f ./gloo-mesh/connectionpolicy.yaml
kubectl apply -f ./gloo-mesh/outlierdetectionpolicy.yaml
```

To keep track on all the potential issues related to the circuit break rule created, we need to keep track on the following metric:
`upstream_rq_pending_overflow`

### 4. Traffic Split

let's deploy the v1.1.0 resolving the latency issue on the productcatalog service

```shell
kubectl apply -f hipstershop/productcatalog_v2.yaml -n hipster-shop
```

Then we want to create the traffic split rule where 80% of the traffic will be sent to the v1.0 and 20% to v1.1

```shell
kubectl apply -f ./gloo-mesh/trafficsplit.yaml -n hipster-shop
```

