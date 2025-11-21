# Kubernetes VoIP Stack - Deployment Guide

Complete guide for deploying Kamailio + FreeSWITCH + RTPengine on Kubernetes.

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Node (hostNetwork)                   │
│  ┌──────────────┐              ┌──────────────┐        │
│  │  Kamailio    │◄────────────►│  RTPengine   │        │
│  │ (SIP Proxy)  │  localhost   │ (Media Proxy)│        │
│  │  :5060       │  :22222      │ :10000-20000 │        │
│  └──────┬───────┘              └──────────────┘        │
│         │                                               │
└─────────┼───────────────────────────────────────────────┘
          │
          ▼
   ┌──────────────┐         ┌─────────────────┐
   │ FreeSWITCH   │         │   PostgreSQL    │
   │ (Media GW)   │         │   (Databases)   │
   │  Pod Network │         │   Pod Network   │
   └──────────────┘         └─────────────────┘
```

---

## 📦 Components

### **1. Kamailio (SIP Proxy)**
- **Role**: SIP registration, authentication, call routing
- **Network**: `hostNetwork: true` (REQUIRED)
- **Ports**: 
  - 5060/UDP - SIP signaling
  - Exposed via NodePort 30060
- **Database**: PostgreSQL (kamailio DB)
- **Why hostNetwork?**: Must communicate with RTPengine on localhost (127.0.0.1:22222)

### **2. RTPengine (Media Proxy)**
- **Role**: RTP/RTCP media relay and transcoding
- **Network**: `hostNetwork: true` (REQUIRED)
- **Ports**:
  - 22222/UDP - Control interface (listens on 127.0.0.1)
  - 10000-20000/UDP - RTP media ports (listens on node IP)
- **Why hostNetwork?**: 
  - Needs to bind to node's external IP for RTP traffic
  - Must accept control commands from Kamailio on localhost
  - Kubernetes doesn't support port ranges in services

### **3. FreeSWITCH (Media Gateway)**
- **Role**: Media server, handles calls forwarded by Kamailio
- **Network**: Standard pod network (ClusterIP)
- **Ports**: 5060/UDP, 5061/TCP, 8021/TCP
- **Database**: PostgreSQL (freeswitch DB)

### **4. PostgreSQL Databases**
- **postgres-kamailio**: Stores SIP users, location, dispatcher
- **postgresql-freeswitch**: FreeSWITCH configuration database
- **Network**: Standard pod network (StatefulSet)

---

## ⚠️ Critical Requirements

### **🔴 MUST USE hostNetwork**

Both **Kamailio** and **RTPengine** MUST use `hostNetwork: true`. Here's why:

#### Without hostNetwork:
```
❌ Problem 1: Kamailio (pod IP) → RTPengine (host IP)
   - Kamailio sends control commands to RTPengine
   - RTPengine replies, but replies can't route back to pod network
   - Result: "timeout waiting reply" errors

❌ Problem 2: RTP port ranges (10000-20000)
   - Kubernetes Services don't support port ranges
   - Can't expose 10,000+ ports individually
   - Clients can't send RTP to correct ports

❌ Problem 3: NAT traversal
   - RTPengine needs real node IP in SDP for clients
   - Pod IP won't work for external clients
```

#### With hostNetwork:
```
✅ Solution: Both on same node, same network namespace
   - Kamailio → RTPengine via localhost (127.0.0.1:22222)
   - Bidirectional communication works perfectly
   - RTPengine binds to node IP for RTP (172.26.26.224:10000-20000)  # This is private ip of my laptop where i had deployed everything
   - Clients send RTP directly to node IP
```

### **🔴 MUST Schedule on Same Node**

Kamailio and RTPengine communicate via localhost, so they **MUST** be on the same node.

**Implemented via Pod Affinity:**
```yaml
# Kamailio: REQUIRED affinity to RTPengine
affinity:
  podAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchExpressions:
            - key: app
              operator: In
              values: [rtpengine]
        topologyKey: kubernetes.io/hostname
```

**What happens if they're on different nodes?**
- Kamailio tries to reach RTPengine at 127.0.0.1:22222
- RTPengine is on a different node
- Connection refused / timeout errors
- No audio in calls

---

## 🚀 Deployment

### **Prerequisites**

1. **Kubernetes cluster** (tested on v1.28+)
2. **Label nodes** that can run VoIP workloads:
   ```bash
   kubectl label nodes <node-name> voip-enabled=true
   ```

### **Deploy All Components**

```bash
# 1. Create namespace
kubectl apply -f k8s/namespace.yaml

# 2. Deploy databases
kubectl apply -f k8s/postgres-kamailio.yaml
kubectl apply -f k8s/postgres-freeswitch.yaml

# 3. Deploy FreeSWITCH
kubectl apply -f k8s/freeswitch.yaml

# 4. Deploy RTPengine (must be before Kamailio due to affinity)
kubectl apply -f k8s/rtpengine.yaml

# 5. Deploy Kamailio config and service
kubectl apply -f k8s/kamailio-configmap.yaml
kubectl apply -f k8s/kamailio.yaml

# 6. Verify deployment
kubectl get pods -n sip -o wide
```

### **Verify RTPengine Connection**

```bash
# Check if Kamailio detected RTPengine
kubectl logs -n sip -l app=kamailio --tail=20 | grep rtpengine

# Expected output:
# INFO: rtpengine instance <udp:127.0.0.1:22222> found, support for it enabled
```

---

## 🔧 Configuration

### **Node Selection**

Only nodes with label `voip-enabled=true` will host Kamailio and RTPengine:

```yaml
nodeSelector:
  voip-enabled: "true"
```

**Add more VoIP nodes:**
```bash
kubectl label nodes worker-node-2 voip-enabled=true
kubectl label nodes worker-node-3 voip-enabled=true
```

**Remove from VoIP pool:**
```bash
kubectl label nodes old-node voip-enabled-
```

### **Dynamic Node IP**

RTPengine automatically uses the node's IP:

```yaml
env:
  - name: NODE_IP
    valueFrom:
      fieldRef:
        fieldPath: status.hostIP

args:
  - /usr/sbin/rtpengine --interface=$NODE_IP --listen-ng=127.0.0.1:22222 ...
```

This makes the deployment portable across any node in your cluster.

---

## 🧪 Testing

### **1. Register SIP Clients**

Configure your SIP softphone (Zoiper, Linphone, etc.):

```
Server: <node-ip>:30060
Username: 1001 (or register via location table)
Password: 1234
Transport: UDP

Server: <node-ip>:30060
Username: 1002 (or register via location table)
Password: 1234
Transport: UDP
```

### **2. Make a Call**

Call between extensions (e.g., 1001 → 1002)

### **3. Verify RTP Processing**

```bash
# Check if RTPengine is processing media
kubectl logs -n sip -l app=rtpengine --tail=50 | grep -E "(offer|answer|packet)"

# Expected output:
# INFO: Received command 'offer' from 127.0.0.1:xxxxx
# INFO: Received command 'answer' from 127.0.0.1:xxxxx
# INFO: RTP packet received
```

### **4. Check Call Flow**

```bash
# Kamailio logs
kubectl logs -n sip -l app=kamailio --tail=50 | grep -E "(INVITE|200|Extension)"

# RTPengine stats after call
kubectl logs -n sip -l app=rtpengine --tail=50 | grep "Final packet stats"
```

---

## 🐛 Troubleshooting

### **No Audio**

**Symptom**: Call connects but no audio

**Diagnosis:**
```bash
# 1. Check if RTPengine is receiving commands
kubectl logs -n sip -l app=rtpengine --tail=50 | grep offer
# Should see: "Received command 'offer'"

# 2. Check if answer is being processed
kubectl logs -n sip -l app=rtpengine --tail=50 | grep answer
# Should see: "Received command 'answer'"

# 3. Check RTP packet flow
kubectl logs -n sip -l app=rtpengine --tail=100 | grep "packet stats"
# Should show packets in both directions, NOT "(null):0"
```

**Common Causes:**
1. **RTPengine not connected**: Check `kubectl logs -n sip -l app=kamailio | grep rtpengine`
2. **Firewall blocking UDP 10000-20000**: Open these ports on the node
3. **Pods on different nodes**: Check `kubectl get pods -n sip -o wide`
4. **Wrong RTPengine address in config**: Should be `127.0.0.1:22222`, not `172.x.x.x`

### **Kamailio Can't Reach RTPengine**

**Error**: `timeout waiting reply` or `Connection refused:111`

**Fix:**
```bash
# 1. Verify both pods are on same node
kubectl get pods -n sip -o wide | grep -E "(kamailio|rtpengine)"
# Both should show same NODE

# 2. Check Kamailio config uses localhost
kubectl get configmap -n sip kamailio-config -o yaml | grep rtpengine_sock
# Should be: udp:127.0.0.1:22222

# 3. Restart both pods
kubectl delete pod -n sip -l app=kamailio
kubectl delete pod -n sip -l app=rtpengine
```

### **Pods Stuck on Different Nodes**

**Symptom**: Kamailio and RTPengine on different nodes

**Fix:**
```bash
# Delete both and let affinity rules reschedule them together
kubectl delete pod -n sip -l app=kamailio
kubectl delete pod -n sip -l app=rtpengine

# Wait for them to come up
watch kubectl get pods -n sip -o wide
```

---

## 📊 Monitoring

### **Check Pod Status**
```bash
kubectl get pods -n sip -o wide
```

### **Check Resource Usage**
```bash
kubectl top pods -n sip
```

### **View Logs**
```bash
# Real-time Kamailio logs
kubectl logs -n sip -l app=kamailio -f

# Real-time RTPengine logs
kubectl logs -n sip -l app=rtpengine -f

# Recent call logs
kubectl logs -n sip -l app=kamailio --tail=100 | grep INVITE
```

### **Check RTPengine Health**
```bash
# See active calls
kubectl logs -n sip -l app=rtpengine | grep "Creating new call"

# Check for errors
kubectl logs -n sip -l app=rtpengine | grep -i error
```

---

## 🔒 Security Considerations

### **Current Setup (Development)**
- No SIP authentication (authentication disabled in Kamailio)
- Plaintext database passwords in ConfigMaps
- No TLS/SRTP encryption

### **Production Recommendations**

1. **Enable SIP Authentication**:
   - Uncomment auth blocks in kamailio.cfg
   - Use strong passwords stored in Kubernetes Secrets

2. **Secure Databases**:
   ```bash
   kubectl create secret generic db-credentials \
     --from-literal=kamailio-password=$(openssl rand -base64 32) \
     -n sip
   ```

3. **Network Policies**:
   - Restrict pod-to-pod communication
   - Only allow SIP clients to reach NodePort 30060

4. **Enable TLS**:
   - Configure TLS in Kamailio (port 5061)
   - Use cert-manager for certificates

---

## 📈 Scaling

### **Horizontal Scaling**

**Can Scale:**
- ✅ FreeSWITCH: Multiple replicas with dispatcher
- ✅ PostgreSQL: Read replicas for high availability

**Cannot Scale:**
- ❌ Kamailio: Limited by hostNetwork (1 per node)
- ❌ RTPengine: Limited by hostNetwork (1 per node)

**Multi-Node Setup:**

To handle more traffic, deploy on multiple nodes:

```bash
# Label more nodes
kubectl label nodes node-2 voip-enabled=true
kubectl label nodes node-3 voip-enabled=true

# Kamailio + RTPengine will schedule as pairs on each labeled node
# Use external load balancer to distribute traffic
```

---

## 🗂️ File Structure

```
k8s/
├── namespace.yaml                 # sip namespace
├── postgres-kamailio.yaml         # Kamailio database
├── postgres-freeswitch.yaml       # FreeSWITCH database
├── kamailio-configmap.yaml        # Kamailio SIP configuration
├── kamailio.yaml                  # Kamailio deployment + service
├── rtpengine.yaml                 # RTPengine deployment
└── freeswitch.yaml                # FreeSWITCH deployment + service
```

---

## 📝 Notes

1. **hostNetwork is REQUIRED** for Kamailio and RTPengine - don't try to remove it
2. **Pod affinity is CRITICAL** - they must be on the same node
3. **Node labeling controls scheduling** - only labeled nodes will host VoIP pods
4. **Dynamic node IP** makes deployment portable across nodes
5. **UDP port range 10000-20000** must be accessible from clients to node IP
6. **Localhost communication (127.0.0.1:22222)** is why they need same node + hostNetwork

---

## 🤝 Support

For issues:
1. Check troubleshooting section above
2. Verify RTPengine logs show both offer and answer commands
3. Ensure both Kamailio and RTPengine are on same node with hostNetwork
4. Verify firewall allows UDP 10000-20000 to node IP

---

## 📄 License

MIT License - Feel free to use and modify for your VoIP deployments.

---

## 👨‍💻 Author

**Vishal Kapadi**  
DevOps Engineer 

- 🐙 **GitHub:** [github.com/vishalk17](https://github.com/vishalk17)
- 🎥 **YouTube:** [youtube.com/@vishalk17](https://www.youtube.com/@vishalk17)
- 💼 **LinkedIn:** [linkedin.com/in/vishal-kapadi](https://www.linkedin.com/in/vishal-kapadi/)


---

**© 2025 Vishal Kapadi. All rights reserved.**
