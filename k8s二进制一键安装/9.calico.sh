
2.5.10.1 下载
 
wget https://docs.projectcalico.org/v3.19/manifests/calico.yaml

2.5.10.2 修改文件
 
3683             - name: CALICO_IPV4POOL_CIDR
3684               value: "10.244.0.0/16"

2.5.10.3 应用文件
 
kubectl apply -f calico.yaml

2.5.10.4 验证应用结果
 
# kubectl get pods -A
NAMESPACE     NAME                                       READY   STATUS    RESTARTS   AGE
kube-system   calico-kube-controllers-7cc8dd57d9-tf2m5   1/1     Running   0          72s
kube-system   calico-node-llw5w                          1/1     Running   0          72s
kube-system   calico-node-mhh6g                          1/1     Running   0          72s
kube-system   calico-node-twj99                          1/1     Running   0          72s
kube-system   calico-node-zh6xl                          1/1     Running   0          72s

# kubectl get nodes
NAME          STATUS   ROLES    AGE   VERSION
master1   Ready    <none>   55m   v1.21.10
node1   Ready    <none>   53m   v1.21.10
node2   Ready    <none>   53m   v1.21.10
k8s-worker1   Ready    <none>   57m   v1.21.10

2.5.10 部署CoreDNS
 
cat >  coredns.yaml << "EOF"
apiVersion: v1
kind: ServiceAccount
metadata:
  name: coredns
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:coredns
rules:
  - apiGroups:
    - ""
    resources:
    - endpoints
    - services
    - pods
    - namespaces
    verbs:
    - list
    - watch
  - apiGroups:
    - discovery.k8s.io
    resources:
    - endpointslices
    verbs:
    - list
    - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:coredns
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:coredns
subjects:
- kind: ServiceAccount
  name: coredns
  namespace: kube-system
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
          lameduck 5s
        }
        ready
        kubernetes cluster.local  in-addr.arpa ip6.arpa {
          fallthrough in-addr.arpa ip6.arpa
        }
        prometheus :9153
        forward . /etc/resolv.conf {
          max_concurrent 1000
        }
        cache 30
        loop
        reload
        loadbalance
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coredns
  namespace: kube-system
  labels:
    k8s-app: kube-dns
    kubernetes.io/name: "CoreDNS"
spec:
  # replicas: not specified here:
  # 1. Default is 1.
  # 2. Will be tuned in real time if DNS horizontal auto-scaling is turned on.
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  selector:
    matchLabels:
      k8s-app: kube-dns
  template:
    metadata:
      labels:
        k8s-app: kube-dns
    spec:
      priorityClassName: system-cluster-critical
      serviceAccountName: coredns
      tolerations:
        - key: "CriticalAddonsOnly"
          operator: "Exists"
      nodeSelector:
        kubernetes.io/os: linux
      affinity:
         podAntiAffinity:
           preferredDuringSchedulingIgnoredDuringExecution:
           - weight: 100
             podAffinityTerm:
               labelSelector:
                 matchExpressions:
                   - key: k8s-app
                     operator: In
                     values: ["kube-dns"]
               topologyKey: kubernetes.io/hostname
      containers:
      - name: coredns
        image: coredns/coredns:1.8.4
        imagePullPolicy: IfNotPresent
        resources:
          limits:
            memory: 170Mi
          requests:
            cpu: 100m
            memory: 70Mi
        args: [ "-conf", "/etc/coredns/Corefile" ]
        volumeMounts:
        - name: config-volume
          mountPath: /etc/coredns
          readOnly: true
        ports:
        - containerPort: 53
          name: dns
          protocol: UDP
        - containerPort: 53
          name: dns-tcp
          protocol: TCP
        - containerPort: 9153
          name: metrics
          protocol: TCP
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            add:
            - NET_BIND_SERVICE
            drop:
            - all
          readOnlyRootFilesystem: true
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
        readinessProbe:
          httpGet:
            path: /ready
            port: 8181
            scheme: HTTP
      dnsPolicy: Default
      volumes:
        - name: config-volume
          configMap:
            name: coredns
            items:
            - key: Corefile
              path: Corefile
---
apiVersion: v1
kind: Service
metadata:
  name: kube-dns
  namespace: kube-system
  annotations:
    prometheus.io/port: "9153"
    prometheus.io/scrape: "true"
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    kubernetes.io/name: "CoreDNS"
spec:
  selector:
    k8s-app: kube-dns
  clusterIP: 10.96.0.2
  ports:
  - name: dns
    port: 53
    protocol: UDP
  - name: dns-tcp
    port: 53
    protocol: TCP
  - name: metrics
    port: 9153
    protocol: TCP
 
EOF

kubectl apply -f coredns.yaml

# kubectl get pods -A
NAMESPACE     NAME                                       READY   STATUS    RESTARTS   AGE
kube-system   calico-kube-controllers-7cc8dd57d9-tf2m5   1/1     Running   0          4m7s
kube-system   calico-node-llw5w                          1/1     Running   0          4m7s
kube-system   calico-node-mhh6g                          1/1     Running   0          4m7s
kube-system   calico-node-twj99                          1/1     Running   0          4m7s
kube-system   calico-node-zh6xl                          1/1     Running   0          4m7s
kube-system   coredns-675db8b7cc-ncnf6                   1/1     Running   0          26s

2.5.11 部署应用验证
 
cat >  nginx.yaml  << "EOF"
---
apiVersion: v1
kind: ReplicationController
metadata:
  name: nginx-web
spec:
  replicas: 2
  selector:
    name: nginx
  template:
    metadata:
      labels:
        name: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.19.6
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service-nodeport
spec:
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30001
      protocol: TCP
  type: NodePort
  selector:
    name: nginx
EOF

kubectl apply -f nginx.yaml

# kubectl get pods -o wide
NAME                     READY   STATUS    RESTARTS   AGE   IP              NODE          NOMINATED NODE   READINESS GATES
nginx-web-qzvw4   1/1     Running   0          58s   10.244.194.65   k8s-worker1   <none>           <none>
nginx-web-spw5t   1/1     Running   0          58s   10.244.224.1    node1   <none>           <none>

# kubectl get all
NAME                         READY   STATUS    RESTARTS   AGE
pod/nginx-web-qzvw4   1/1     Running   0          2m2s
pod/nginx-web-spw5t   1/1     Running   0          2m2s

NAME                                     DESIRED   CURRENT   READY   AGE
replicationcontroller/nginx-web   2         2         2       2m2s

NAME                             TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
service/kubernetes               ClusterIP   10.96.0.1       <none>        443/TCP        3h37m
service/nginx-service-nodeport   NodePort    10.96.165.114   <none>        80:30001/TCP   2m2s

kube-dns
 namespace: kube-system
 annotations:
 prometheus.io/port: “9153”
 prometheus.io/scrape: “true”
 labels:
 k8s-app: kube-dns
 kubernetes.io/cluster-service: “true”
 kubernetes.io/name: “CoreDNS”
 spec:
 selector:
 k8s-app: kube-dns
 clusterIP: 10.96.0.2
 ports:

 
name: dns
 port: 53
 protocol: UDP
name: dns-tcp
 port: 53
 protocol: TCP
name: metrics
 port: 9153
 protocol: TCP
 
EOF

 



~~~powershell
kubectl apply -f coredns.yaml

# kubectl get pods -A
NAMESPACE     NAME                                       READY   STATUS    RESTARTS   AGE
kube-system   calico-kube-controllers-7cc8dd57d9-tf2m5   1/1     Running   0          4m7s
kube-system   calico-node-llw5w                          1/1     Running   0          4m7s
kube-system   calico-node-mhh6g                          1/1     Running   0          4m7s
kube-system   calico-node-twj99                          1/1     Running   0          4m7s
kube-system   calico-node-zh6xl                          1/1     Running   0          4m7s
kube-system   coredns-675db8b7cc-ncnf6                   1/1     Running   0          26s

2.5.11 部署应用验证
 
cat >  nginx.yaml  << "EOF"
---
apiVersion: v1
kind: ReplicationController
metadata:
  name: nginx-web
spec:
  replicas: 2
  selector:
    name: nginx
  template:
    metadata:
      labels:
        name: nginx
    spec:
      containers:
        - name: nginx
          image: nginx:1.19.6
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service-nodeport
spec:
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30001
      protocol: TCP
  type: NodePort
  selector:
    name: nginx
EOF

kubectl apply -f nginx.yaml

# kubectl get pods -o wide
NAME                     READY   STATUS    RESTARTS   AGE   IP              NODE          NOMINATED NODE   READINESS GATES
nginx-web-qzvw4   1/1     Running   0          58s   10.244.194.65   k8s-worker1   <none>           <none>
nginx-web-spw5t   1/1     Running   0          58s   10.244.224.1    node1   <none>           <none>

# kubectl get all
NAME                         READY   STATUS    RESTARTS   AGE
pod/nginx-web-qzvw4   1/1     Running   0          2m2s
pod/nginx-web-spw5t   1/1     Running   0          2m2s

NAME                                     DESIRED   CURRENT   READY   AGE
replicationcontroller/nginx-web   2         2         2       2m2s

NAME                             TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
service/kubernetes               ClusterIP   10.96.0.1       <none>        443/TCP        3h37m
service/nginx-service-nodeport   NodePort    10.96.165.114   <none>        80:30001/TCP   2m2s