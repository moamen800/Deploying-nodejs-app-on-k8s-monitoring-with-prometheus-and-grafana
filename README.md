# Deploying and Monitoring a NodeJS Application with Prometheus and Grafana  

## Overview  
This project demonstrates how to deploy a **NodeJS application** in a **Kubernetes cluster** and monitor it using **Prometheus and Grafana**. It includes setting up **Alertmanager** for notifications and defining custom alert rules for monitoring HTTP request rates.  

---

## Prerequisites  
Before starting, ensure you have the following installed and configured:  
- **Kubernetes Cluster** (Using kubeadm)  
- **Helm**  
- **kubectl** CLI  
- **Docker**  
- **Node.js**
- **Prometheus**
- **Grafana**
- **AWS Cloud Providor**  

---
<img width="1241" alt="1" src="https://github.com/user-attachments/assets/cc1b09f4-26d8-43f7-b8a4-0a0bedf330fa" />

<img width="1240" alt="2" src="https://github.com/user-attachments/assets/d8436c88-c148-46ed-9ac7-9a0eb1ec59d7" />

## Steps to Deploy and Monitor the Application  

### Apply Terraform Configuration
To apply the Terraform configuration, run:
```sh
terraform init
terraform apply -auto-approve
```

### 1. Initialize Kubernetes Cluster  

#### **On the Master Node**  
```sh
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 
mkdir -p $HOME/.kube 
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml 
```
To retrieve the **join command** for worker nodes:  
```sh
kubeadm token create --print-join-command
```

#### **On Worker Nodes**  
Run the join command from the output above:  
```sh
sudo kubeadm join <MASTER_IP>:<PORT> --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>
```

---

## Return to the Master Node  
### 2. Install Helm and Deploy Prometheus  

#### **Install Helm**  
```sh
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
sudo apt-get install apt-transport-https --yes
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm -y
```

#### **Deploy Prometheus & Grafana**  
```sh
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace
```

#### **Expose Services for External Access**  
```sh
kubectl expose svc prometheus-kube-prometheus-prometheus --type=NodePort --target-port=9090 --name=prometheus-kube-prometheus-prometheus-ext -n monitoring
kubectl expose svc prometheus-grafana --type=NodePort --target-port=3000 --name=prometheus-grafana-ext  -n monitoring
kubectl expose svc prometheus-kube-prometheus-alertmanager --type=NodePort --target-port=9093 --name=prometheus-kube-prometheus-alertmanager-ext -n monitoring
```

---

### 3. Deploy NodeJS Application  

#### **Create NodeJS App (`index.js`)**  
```javascript
const express = require('express');
const client = require('prom-client');

const app = express();
const port = 3000;

const register = new client.Registry();
register.setDefaultLabels({ app: 'nodejs_dolfined_app' });
client.collectDefaultMetrics({ register });

const rootHttpRequestCounter = new client.Counter({
  name: 'http_requests_root_total',
  help: 'Total number of HTTP requests to the root path',
});

register.registerMetric(rootHttpRequestCounter);

app.use((req, res, next) => {
  if (req.path === '/') rootHttpRequestCounter.inc();
  next();
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.get('/', (req, res) => {
  res.send('Hello From DolfinED');
});

app.listen(port, () => {
  console.log(`Example app listening at http://localhost:${port}`);
});
```

#### **Create a Dockerfile**  
```dockerfile
FROM node:lts
WORKDIR /usr/src/app
COPY . .
RUN npm install express prom-client
EXPOSE 3000
CMD ["node", "index.js"]
```

#### **Build and Push Docker Image**  
```sh
docker build -t nodejs-app .
docker tag nodejs-app:latest <docker-username>/nodejs-app:v1
docker login
docker push <docker-username>/nodejs-app:v1
```

#### **Deploy to Kubernetes (`nodejs-app.yaml`)**  
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-nodejs-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nodejs
  template:
    metadata:
      labels:
        app: nodejs
    spec:
      containers:
        - name: nodejs
          image: <docker-username>/nodejs-app:v1
          ports:
            - containerPort: 3000 
          resources:
            limits:
              cpu: "1"
              memory: "512Mi"
```
Apply the deployment:  
```sh
kubectl apply -f nodejs-app.yaml
kubectl get pods
kubectl get deploy
```

---

### 4. Expose the Application as a Service  

#### **Create a Kubernetes Service (`nodejs-svc.yaml`)**  
```yaml
apiVersion: v1
kind: Service
metadata:
  name: nodejs-svc
  labels:
    app: nodejs
  annotations:
    prometheus.io/scrape: 'true'
spec:
  type: NodePort
  selector:
    app: nodejs
  ports:
    - port: 3000
      targetPort: 3000
      name: nodejs
```
Apply the service:  
```sh
kubectl apply -f nodejs-svc.yaml
kubectl get svc
```

---

### 5. Configure Prometheus Monitoring  

#### **Create a ServiceMonitor (`nodejs-ServiceMonitor.yaml`)**  
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: nodejs-monitor1
  namespace: monitoring  
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: nodejs  
  namespaceSelector:
    matchNames:
      - default  
  endpoints:
    - port: nodejs
      path: /metrics
```
Apply the ServiceMonitor:  
```sh
kubectl apply -f nodejs-ServiceMonitor.yaml
```

---

### 6. Configure Alerts  

#### **Create an Alert Rule (`nodejs-rule.yaml`)**  
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: nodejs-alert
  namespace: monitoring
  labels:
    app: kube-prometheus-stack
    release: prometheus
spec:
  groups:
  - name: nodejs-alert
    rules:
    - alert: HighRequestRate_NodeJS
      expr: rate(http_requests_root_total[5m]) > 10
      for: 0m
      labels:
        app: nodejs
        namespace: monitoring
      annotations: 
        description: "The request rate to the root path has exceeded 10 requests."
        summary: "High request rate on root path"
```
Apply the alert rule:  
```sh
kubectl apply -f nodejs-rule.yaml
```

---

### 7. Configure Alertmanager for Slack  

#### **Create Slack Secret (`slack-secret.yaml`)**  
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: slack-secret
  namespace: monitoring
type: Opaque
stringData:
  webhook: 'https://hooks.slack.com/services/XXX/XXX/XXX'
```
Apply the secret:  
```sh
kubectl apply -f slack-secret.yaml
```

#### **Configure Alertmanager (`nodejs-alert-manager.yaml`)**  
```yaml
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata:
  name: nodejs-alert-manager
  namespace: monitoring
spec:
  route:
    receiver: 'nodejs-slack'
  receivers:
  - name: 'nodejs-slack'
    slackConfigs:
      - apiURL:
          key: webhook
          name: slack-secret
        channel: '#highcpu-app'
```
Apply Alertmanager Config:  
```sh
kubectl apply -f nodejs-alert-manager.yaml
```

---

## Conclusion  
This guide shows how to deploy a **NodeJS app** in Kubernetes, monitor it using **Prometheus & Grafana**, and set up **alert notifications with Alertmanager and Slack**. 🚀

