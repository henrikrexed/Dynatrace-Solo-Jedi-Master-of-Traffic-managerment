#  How to become the Jedi Master of Traffic management with Dynatrace and Solo.io
This repository contains the files required for the demo presented during the joint webinar organized by Dynatrace and Solo.io

This repository showcase the usage of several solutions :
* the HipsterShop
* Litmus Chaos
* OpenTelemetry Collector
* Istio



In this demo we will walk through the usage of Configuring istio with : 
- the hipster-shop


To reproduce well know production issue this workshop we will utilize :
- Litmus Chaos to generate disruption in the Cluster

## Prerequisite 
The following tools need to be install on your machine :
- jq
- kubectl
- git
- gcloud ( if you are using GKE)
- Helm

### 1.Create a Google Cloud Platform Project
```shell
PROJECT_ID="<your-project-id>"
gcloud services enable container.googleapis.com --project ${PROJECT_ID}
gcloud services enable monitoring.googleapis.com \
cloudtrace.googleapis.com \
clouddebugger.googleapis.com \
cloudprofiler.googleapis.com \
--project ${PROJECT_ID}
```
### 2.Create a GKE cluster
```shell
ZONE=europe-west3-a
NAME=dt-solo-jedimaster
gcloud container clusters create ${NAME} --zone=${ZONE} --machine-type=e2-standard-8 --num-nodes=3
```
### 3.Clone Github repo
```shell
git clone https://github.com/henrikrexed/Dynatrace-Solo-Jedi-Master-of-Traffic-managerment
cd Dynatrace-Solo-Jedi-Master-of-Traffic-managerment
```
### 4. Deploy 

#### 0. Label Nodes
kubectl get nodes -o wide
kubectl label <nodename1> node-type=observability
kubectl label <nodename2> node-type=worker
kubectl label <nodename3> node-type=worker

#### 1. Istio

1. Download Istioctl
```shell
curl -L https://istio.io/downloadIstio | sh -
```
This command download the latest version of istio ( in our case istio 1.17.2) compatible with our operating system.
2. Add istioctl to you PATH
```shell
cd istio-1.19.0
```
this directory contains samples with addons . We will refer to it later.
```shell
export PATH=$PWD/bin:$PATH
```

#### 1. Install Istio
To enable Istio and take advantage of the tracing capabilities of Istio, you need to install istio with the following settings
 ```shell
istioctl install -f istio/istio-operator.yaml
 ```


#### 2. Dynatrace 
##### 1. Dynatrace Tenant - start a trial
If you don't have any Dyntrace tenant , then i suggest to create a trial using the following link : [Dynatrace Trial](https://bit.ly/3KxWDvY)
Once you have your Tenant save the Dynatrace (including https) tenant URL in the variable `DT_TENANT_URL` (for example : https://dedededfrf.live.dynatrace.com)
```shell
DT_TENANT_URL=<YOUR TENANT URL>
```
##### 2. Create the Dynatrace API Tokens
The dynatrace operator will require to have several tokens:
* Token to deploy and configure the various components
* Token to ingest metrics and Traces


###### Operator Token
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
###### Ingest data token
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
#### 3. Run the deployment script
```shell
cd ..
chmod 777 deployment.sh
./deployment.sh  --clustername "${NAME}" --dturl "${DT_TENANT_URL}" --dtoperatortoken "${API_TOKEN}" --dtingesttoken "${DATA_INGEST_TOKEN}" 
```


### 6. ServiceMesh Features

#### 1. Request timeout
The productcatalog service is responding in around 1s, but with load the response time can heavily increase.
Let's protect all the other services relying on the product catalog by defining a request timeout rule.
```shell
kubectl apply -f istio/request_timeout.yaml -n hipster-shop
```
let's run a load test
```shell
kubectl apply -f k6/loadtest_job.yaml -n hipster-shop
```

now all the service relying on the productcalalog won't get the list of products.
so the impact is that the frontend should generate an error due to the missing product list:
<p align="center"><img src="/image/timeout.png" width="40%" alt="data token" /></p>

#### 2. Rate Limit
To illustrate the usage of the rate limit we won't apply it on the productcatalog service , because it receives a limited workload.
Therefore we would apply it on the frontend service taking in peak hours 550 requests.
The rate limit will only accept 400 requests.
```shell
kubectl apply -f istio/rate_limit.yaml
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

#### 3. Circuit Breaker
Let's create a circuit breaker rule on the productcatalog service.

```shell
kubectl apply -f istio/circuit_Break.yaml
```
To keep track on all the potential issues related to the circuit break rule created, we need to keep track on the following metric:
`upstream_rq_pending_overflow`

#### 4. Traffic Split
let's deploy the v1.1.0 resolving the latency issue on the productcatalog service
```shell
kubectl apply -f hipstershop/productcatalog_v2.yaml -n hipster-shop
```
Then we want to create the traffic split rule where 80% of the traffic will be sent to the v1.0 and 20% to v1.1
```shell
kubectl apply -f istio/traficsplit.yaml -n hipster-shop
```


#### 4.Chaos Experiments

##### 1. Kubernetes settings

The eviction process happens if one of the node is in any of the Pressure conditions :
- DiskPressure
- NodePressure
- NetworkUnavailable
-..
  
In our example we will try to simulate the NodePressure situation.
For this we will use 2 existent experiment available in the ChaosHub of Litmus :
- Node CPU hog
- Node Memory Hog
We will run in parallel on the same node ( having the label node-type=worker) both experiments.
- cpu hog usage : 70%
- memory hog usage : 70%

Let's select one Node from our cluster
```shell
kubectl get ndoes -l node-type=worker
```
Save one of the nodename if the following variable:
```shell
NODE_NAME=<YOUR NODE_NAME>
```
let's update our Chaos experiment with our node name:
```shell
sed -i "s,NODE_NAME_TO_REPLACE,$NODE_NAME,"  litmus chaos/chaos_schedule_nodememoryhog.yaml
```
now we can run the experiment :
```shell
kubectl apply -f litmus chaos/rbac.yaml -n hipster-shop
kubectl apply -f litmus chaos/chaos_schedule_nodememoryhog.yaml 
```

##### 2. Application experiments
To measure the impact of the failure of the important components of the Hipster-shope :
* Redis database
* Productcatalog
TO achieve this we will run first an experiment deleting Redis and then we will run the experiment deleting the product catalog.
```
kubectl apply -f litmus chaos/redis_product.yaml
```

#### 8. Report the Envoy metrics to Dynatrace using the OpenTelemetry Collector

