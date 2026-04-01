# CloudMart Scaling Guide

## Auto-scaling Configuration

### GKE Horizontal Pod Autoscaler
- **Product Service**: 2-20 pods, scale at 70% CPU
- **Order Service**: 2-15 pods, scale at 70% CPU
- Scale-up: +4 pods/minute (fast)
- Scale-down: -1 pod/2 minutes (conservative)

### GKE Cluster Autoscaler
- Min: 1 node / Max: 5 nodes per zone
- Scale-up trigger: Pod unschedulable
- Scale-down: Node <50% utilized for 10 min

### Cloud Run
- API Gateway: min 1, max 20 instances
- User Service: min 1, max 10 instances
- CPU always-on for API Gateway (no cold starts)

## Manual Scaling

```bash
# Scale GKE deployment
kubectl scale deployment/product-service --replicas=10 -n cloudmart

# Update Cloud Run max instances
gcloud run services update cloudmart-api-gateway \
  --max-instances=50 --region=us-central1

# Scale Cloud SQL read replica
gcloud sql instances patch cloudmart-postgres-replica \
  --tier=db-n1-standard-4
```

## Load Testing

```bash
# Run k6 load test
k6 run --vus 100 --duration 5m scripts/load-test.js

# Monitor during test
watch -n 5 "kubectl top pods -n cloudmart"
```

## Cost Optimization

| Trigger | Action | Savings |
|---------|--------|---------|
| Traffic < 20% baseline | Scale GKE to min nodes | 60% compute cost |
| Off-hours (10pm-6am) | Cloud Run min=0 | 80% Cloud Run cost |
| Dev/test env | Use Cloud SQL db-g1-small | 70% DB cost |
| Images > 90 days old | Lifecycle to Nearline | 40% storage cost |
