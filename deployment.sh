#!/usr/bin/env bash

################################################################################
### Script deploying the Observ-K8s environment
### Parameters:
### Clustern name: name of your k8s cluster
### dttoken: Dynatrace api token with ingest metrics and otlp ingest scope
### dturl : url of your DT tenant wihtout any / at the end for example: https://dedede.live.dynatrace.com
################################################################################


### Pre-flight checks for dependencies
if ! command -v jq >/dev/null 2>&1; then
    echo "Please install jq before continuing"
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    echo "Please install git before continuing"
    exit 1
fi


if ! command -v helm >/dev/null 2>&1; then
    echo "Please install helm before continuing"
    exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "Please install kubectl before continuing"
    exit 1
fi
echo "parsing arguments"
while [ $# -gt 0 ]; do
  case "$1" in

  --dtingesttoken)
    DTTOKEN="$2"
   shift 2
    ;;
  --dturl)
    DTURL="$2"
   shift 2
    ;;
  --clustername)
    CLUSTERNAME="$2"
   shift 2
    ;;
  *)
    echo "Warning: skipping unsupported option: $1"
    shift
    ;;
  esac
done
echo "Checking arguments"
if [ -z "$CLUSTERNAME" ]; then
  echo "Error: clustername not set!"
  exit 1
fi
if [ -z "$DTURL" ]; then
  echo "Error: Dt url not set!"
  exit 1
fi

if [ -z "$DTTOKEN" ]; then
  echo "Error: Data ingest api-token not set!"
  exit 1
fi





### get the ip adress of ingress ####
IP=""
while [ -z $IP ]; do
  echo "Waiting for external IP"
  IP=$(kubectl get svc istio-ingressgateway -n istio-system -ojson | jq -j '.status.loadBalancer.ingress[].ip')
  [ -z "$IP" ] && sleep 10
done
echo 'Found external IP: '$IP

### Update the ip of the ip adress for the ingres
#TODO to update this part to create the various Gateway rules
sed -i "s,IP_TO_REPLACE,$IP," istio/istio_gateway.yaml


### Depploy Prometheus

#### Deploy the cert-manager & the openTelemetry Operator
echo "Deploying Cert Manager ( for OpenTelemetry Operator)"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.10.0/cert-manager.yaml
# Wait for pod webhook started
kubectl wait pod -l app.kubernetes.io/component=webhook -n cert-manager --for=condition=Ready --timeout=2m
# Deploy the opentelemetry operator
sleep 10
echo "Deploying the OpenTelemetry Operator"
kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml
#### Deploy Prometheus operator
#install prometheus operator
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack  --set grafana.sidecar.dashboards.enabled=true
kubectl wait pod --namespace default -l "release=prometheus" --for=condition=Ready --timeout=2m
#install cadvisor
kubectl create ns cadvisor
kubectl apply -f cadvisor/service.yaml -n cadvisor
kubectl apply -f cadvisor/daemonset.yaml -n cadvisor
kubectl apply -f cadvisor/serviceaccount.yaml -n cadvisor

DT_HOST=$(echo $DTURL | grep -oP 'https://\K\S+')
#Install fluenbit
helm repo add fluent https://fluent.github.io/helm-charts
helm upgrade --install fluent-bit fluent/fluent-bit --namespace fluentbit --create-namespace
sed -i "s,DT_URL_TO_REPLACE,$DT_HOST," fluentbit/fluent-bit_cm.yaml
sed -i "s,DT_TOKEN_TO_REPLACE,$DTTOKEN," fluentbit/fluent-bit_cm.yaml
sed -i "s,CLUSTER_NAME_TO_REPLACE,$CLUSTERNAME," fluentbit/fluent-bit_cm.yaml
kubectl apply -f fluentbit/fluent-bit_cm.yaml -n fluentbit
#kubectl rollout restart ds fluent-bit -n fluentbit

# Deploy collector
kubectl create secret generic dynatrace  --from-literal=dynatrace_oltp_url="$DTURL" --from-literal=dt_api_token="$DTTOKEN"
kubectl apply -f openTelemetry-demo/rbac.yaml
kubectl apply -f openTelemetry-demo/openTelemetry-manifest_debut.yaml



## Deploy the otel demo
kubectl create ns otel-demo
kubectl create secret generic dynatrace  --from-literal=dynatrace_oltp_url="$DTURL" --from-literal=dt_api_token="$DTTOKEN" -n otel-demo
kubectl label namespace otel-demo istio-injection=enabled
kubectl apply -f openTelemetry-demo/openTelemetry-sidecar.yaml -n otel-demo
kubectl apply -f openTelemetry-demo/deployment.yaml -n otel-demo


#Deploy the ingress rules
kubectl apply -f istio/istio_gateway.yaml
echo "--------------Demo--------------------"
echo "url of the demo: "
echo "Otel demo url: http://oteldemo.$IP.nip.io"
echo "========================================================"


