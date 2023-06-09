#   OpenObservability Without Boundaries
This repository contains all the files used during the demo of the Observability clinic: OpenObservability without boundaries

This repository showcase the usage of several solutions with Dynatrace:
* Istio
* fluentbit v2
* The OpenTelemtry Operator
* THe OpenTelemetry Demo application



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
NAME=openobservability-clinic
gcloud container clusters create ${NAME} --zone=${ZONE} --machine-type=e2-standard-8 --num-nodes=2
```
### 3.Clone Github repo
```shell
git clone https://github.com/dynatrace-perfclinics/OpenObservability-clinic
cd OpenObservability-clinic
```
### 4. Deploy 

#### 1. Istio

1. Download Istioctl
```shell
curl -L https://istio.io/downloadIstio | sh -
```
This command download the latest version of istio ( in our case istio 1.17.2) compatible with our operating system.
2. Add istioctl to you PATH
```shell
cd istio-1.17.2
```
this directory contains samples with addons . We will refer to it later.
```shell
export PATH=$PWD/bin:$PATH
```

#### 1. Install Istio
To enable Istio and take advantage of the tracing capabilities of Istio, you need to install istio with the following settings
```shell
istioctl install  -f istio/istio-operator.yaml
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
./deployment.sh  --clustername "${NAME}" --dturl "${DT_TENANT_URL}" --dtingesttoken "${DATA_INGEST_TOKEN}" 
```

#### 4. DQL to report the Business KPI of the otel-demo:

##### 1. Product Search
```shell
fetch spans
| filter span.name == "oteldemo.ProductCatalogService/GetProduct"
| filter isNotNull(app.product.name)
| summarize count(), by:app.product.name
```
##### 2. Delivery per cities
```shell
fetch logs
| filter k8s.namespace.name == "otel-demo"
| filter k8s.container.name == "shippingservice"
| filter contains(content,"GetQuoteRequest")
| parse content , "LD SPACE 'stdout' SPACE 'F' SPACE TIME(format='HH:mm:ss'):time_ship SPACE '[' ALPHA:severe ']' SPACE LD ':' LD '{' LD:test"
| parse test, " LD ', message: GetQuoteRequest { address: Some(Address'  LD:rest EOS"
| filter isNotNull(rest)
| parse rest, "BOS SPACE+ '{' SPACE+ 'street_address:' SPACE+ DQS:street ',' SPACE+ 'city:' SPACE+ DQS:city ',' SPACE+ 'state:' SPACE+ DQS:state ',' SPACE+ 'country:' SPACE+ DQS:country  LD EOS "
| summarize count(), by:{city}
```
##### 3. Orders per Products
```shell
fetch logs
| filter k8s.namespace.name == "otel-demo"
| filter k8s.container.name == "cartservice"
| filter  contains(content,"AddItemAsync called with")
| parse content, "LD:text '=' UUIDSTRING:uuid  ',' LD '='  ALNUM:productId ',' LD '=' INT:quantity EOS"
| lookup [ 
    fetch spans
    | filter service.name == "productcatalogservice"
    | filter rpc.method == "GetProduct"
    ] , sourceField:productId, lookupField:app.product.id, fields:{app.product.id, app.product.name}
| summarize sum(quantity), by: {app.product.name }
```

##### 4. Number of Orders
```shell
fetch spans
| filter service.name=="checkoutservice"
| summarize count(), by:{ bin(timestamp, 30s)}
```

#### 5. DQL to the collector Health
##### 1. Collector memory Usage
```shell
timeseries avg(container_memory_usage_bytes), filter:{isTrueOrNull( container_label_io_kubernetes_container_name =="otc-container")}
```
##### 2. Collector queusize
```shell
timeseries avg(queueSize), by:{spanprocessortype}
```

##### 3.Number of Span Seen by exporter
```shell
timeseries avg(otlp.exporter.exported), by:{}
```
##### 4. Number of spans exported
```shell
timeseries avg(otlp.exporter.seen), by:{type}
```
##### 5. Http exporter queue capcity
```shell
timeseries avg(otelcol_exporter_queue_capacity), by:{exporter}
```

##### 6. Otlp http queue size
```shell
timeseries avg(otelcol_exporter_queue_size),by:{exporter}
```

##### 7. Spans Dropped
```shell
timeseries avg(processedSpans),by:{spanprocessortype}
```