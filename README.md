# Spark Basic Homework

## 0. Prerequisites
- Docker
- Terraform
- Azure account
- Azure CLI

## 1. Setup infrastructure via Terraform:
```
az login
cd ./terraform

terraform init
terraform plan -out ./state/terraform.plan
terraform apply ./state/terraform.plan

cd ../

# Destroy all necessary infrastructure after completing the homework:
terraform destroy
```

## 2. Setup kubectl and helm
* Install and setup kubectl via Azure-CLI:
```
az aks install-cli
az aks get-credentials --resource-group rg-kkabanov-westeurope --name aks-kkabanov-westeurope
```
* Check that your local kubectl has been set up to interact with AKS:
```
kubectl get nodes
```
* Healthcheck: Your AKS cluster can pull images from your ACR:
```
az aks check-acr --name aks-kkabanov-westeurope --resource-group rg-kkabanov-westeurope --acr crkkabanovwesteurope.azurecr.io
```
* Install helm (for Ubuntu):
```
curl https://baltocdn.com/helm/signing.asc | sudo apt-key add -
sudo apt-get install apt-transport-https --yes
echo "deb https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm
```

## 3. Build the connector image and push it into ACR:
* Build:
```
docker build -f ./docker/connect-operator.Dockerfile -t crkkabanovwesteurope.azurecr.io/connect-operator .
```
* Push:
```
az login
az acr login --name crkkabanovwesteurope
docker push crkkabanovwesteurope.azurecr.io/connect-operator:latest

# Check that container has been pushed successfully:
az acr repository show-tags --name crkkabanovwesteurope --repository connect-operator --output table
```

## 4. Launch Confluent Platform inside AKS:
* Set the namespace to use:
```
kubectl create namespace confluent
kubectl config set-context --current --namespace confluent
```
* Install Confluent operator:
```
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update
helm upgrade --install confluent-operator confluentinc/confluent-for-kubernetes
```
* Install Confluent Platform:
```
kubectl apply -f ./k8s/confluent-platform.yaml
```

## 5. Be sure that everything works fine:
* Check that all pods are running:
```
kubectl get pods -o wide

# Sample output:
NAME                                 READY   STATUS    RESTARTS   AGE
confluent-operator-99f7f8dcb-8wsws   1/1     Running   0          44h
connect-0                            1/1     Running   2          18h
controlcenter-0                      1/1     Running   0          18h
kafka-0                              1/1     Running   0          18h
kafka-1                              1/1     Running   0          18h
kafka-2                              1/1     Running   0          18h
ksqldb-0                             1/1     Running   0          18h
schemaregistry-0                     1/1     Running   0          18h
zookeeper-0                          1/1     Running   0          18h
zookeeper-1                          1/1     Running   0          18h
zookeeper-2                          1/1     Running   0          18h
```
* Check that you have access to the control center:
```
kubectl port-forward --address 0.0.0.0 controlcenter-0 9021:9021
# Go to localhost:9021
```

* Try to interact with Kafka Connect REST API:
```
kubectl port-forward connect-0 8083:8083

curl -X GET http://localhost:8083/

# Be sure that your Kafka Connect has Azure connectors:
curl -s -X GET http://localhost:8083/connector-plugins/ | jq '.'

[
  {
      "class": "io.confluent.connect.azure.blob.AzureBlobStorageSinkConnector",
      "type": "sink",
      "version": "1.6.2"
  },
  {
      "class": "io.confluent.connect.azure.blob.storage.AzureBlobStorageSourceConnector",
      "type": "source",
      "version": "1.4.5"
  },
  ...
]
```

## 6. Create topic:
```
kubectl exec -ti kafka-0 -- bash
# Then inside the pod:
kafka-topics --create --topic expedia --bootstrap-server localhost:9092 --partitions 3 --replication-factor 3
```

## 7. Launch the connector:
```
curl -s -X POST -H 'Content-Type: application/json' --data @connectors/azure-source-cc-expedia.json http://localhost:8083/connectors/

# Check that connector has started:
curl -X GET http://localhost:8083/connectors/expedia/status/ | jq "."

{
  "name": "expedia",
  "connector": {
  "state": "RUNNING",
  "worker_id": "connect-0.connect.confluent.svc.cluster.local:8083"
  },
  "tasks": [
  {
    "id": 0,
    "state": "RUNNING",
    "worker_id": "connect-0.connect.confluent.svc.cluster.local:8083"
  },
  {
    "id": 1,
    "state": "RUNNING",
    "worker_id": "connect-0.connect.confluent.svc.cluster.local:8083"
  },
  {
    "id": 2,
    "state": "RUNNING",
    "worker_id": "connect-0.connect.confluent.svc.cluster.local:8083"
  }
    
  ],
  "type": "source"
}
```
