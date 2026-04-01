# CloudMart — GCP-Native E-Commerce Platform

A production-grade, cloud-native e-commerce application built entirely on Google Cloud Platform. This repository serves as the **source application** for demonstrating GCP → AWS cloud migration using the [MigrAIne](../MigrAI/) migration tool.

## Architecture Overview

```
                          ┌─────────────────────────────────────────┐
                          │           Google Cloud Platform          │
                          │                                          │
  Users ──► Cloud DNS ──► │  Cloud Armor ──► Cloud Load Balancer    │
                          │                        │                 │
                          │              ┌─────────▼──────────┐     │
                          │              │   Cloud Run         │     │
                          │              │   API Gateway       │     │
                          │              │   (Node.js/Express) │     │
                          │              └──┬──────┬──────┬───┘     │
                          │                 │      │      │         │
                    ┌─────┼─────────────────▼─┐  ┌▼──────▼──┐     │
                    │     │    GKE Cluster      │  │Cloud Run  │     │
                    │     │  ┌──────────────┐  │  │User Svc   │     │
                    │     │  │Product Svc   │  │  │(Node.js)  │     │
                    │     │  │(FastAPI/Py)  │  │  └─────┬─────┘     │
                    │     │  ├──────────────┤  │        │           │
                    │     │  │Order Svc     │  │  ┌─────▼──────┐   │
                    │     │  │(FastAPI/Py)  │  │  │Memorystore │   │
                    │     │  └──────┬───────┘  │  │  (Redis)   │   │
                    │     │         │          │  └────────────┘   │
                    │     └─────────┼──────────┘                   │
                    │               │                              │
                    │    ┌──────────▼──────┐  ┌────────────────┐  │
                    │    │   Cloud Pub/Sub  │  │  Cloud SQL     │  │
                    │    │  (Order Events)  │  │ (PostgreSQL)   │  │
                    │    └──────┬──────────┘  └────────────────┘  │
                    │           │                                   │
                    │    ┌──────▼─────────────────────────┐       │
                    │    │       Cloud Functions            │       │
                    │    │  ┌────────────┐ ┌────────────┐  │       │
                    │    │  │Image Proc  │ │Order Notif │  │       │
                    │    │  │(GCS trig)  │ │(PS trigger)│  │       │
                    │    │  └────────────┘ └────────────┘  │       │
                    │    └────────────────────────────────-┘       │
                    │                                               │
                    │    ┌──────────┐  ┌──────────┐  ┌─────────┐  │
                    │    │Firestore │  │  Cloud   │  │BigQuery │  │
                    │    │(Catalog) │  │ Storage  │  │(Analytics│  │
                    │    └──────────┘  │ (Assets) │  └─────────┘  │
                    │                  └──────────┘               │
                    │                                             │
                    │    ┌────────────────────────────────┐      │
                    │    │  Compute Engine (Inventory Wkr) │      │
                    │    │         (Go / gRPC)             │      │
                    │    └────────────────────────────────┘      │
                    └─────────────────────────────────────────────┘
```

## GCP Services Used

### Compute Plane
| Service | Purpose |
|---------|---------|
| **Google Kubernetes Engine (GKE)** | Hosts Product Service and Order Service microservices |
| **Cloud Run** | Hosts API Gateway and User Service (serverless containers) |
| **Compute Engine** | Runs the Inventory Worker (long-running background process) |
| **Cloud Functions** | Image Processor (GCS trigger), Order Notifier (Pub/Sub trigger), Analytics Ingester (scheduled) |

### Control Plane
| Service | Purpose |
|---------|---------|
| **VPC + Subnets** | Isolated network with private GKE nodes |
| **Cloud Load Balancing** | HTTPS load balancer with SSL termination |
| **Cloud Armor** | WAF rules, DDoS protection |
| **Cloud DNS** | Manages `cloudmart.demo` domain records |
| **IAM + Service Accounts** | Least-privilege service identities |
| **Secret Manager** | DB passwords, API keys, JWT secrets |
| **Cloud KMS** | Encryption keys for sensitive data |
| **Artifact Registry** | Private Docker image registry |
| **Cloud Build** | CI/CD pipeline |

### Data Plane
| Service | Purpose |
|---------|---------|
| **Cloud SQL (PostgreSQL)** | Users, orders, inventory tables |
| **Firestore** | Product catalog (document store, real-time) |
| **Cloud Storage (GCS)** | Product images, static frontend assets |
| **Pub/Sub** | Order lifecycle events (placed, shipped, delivered) |
| **Memorystore (Redis)** | Session cache, shopping cart, rate limiting |
| **BigQuery** | Analytics — sales reports, user behavior |

## Repository Structure

```
cloudmart-gcp/
├── terraform/              # Infrastructure as Code (all GCP resources)
│   └── modules/            # Reusable Terraform modules
├── kubernetes/             # GKE manifests (deployments, services, ingress, HPA)
├── frontend/               # Next.js 14 storefront (deployed to Cloud Run / GCS)
├── services/
│   ├── api-gateway/        # Express.js API Gateway (Cloud Run)
│   ├── product-service/    # FastAPI Product catalog (GKE)
│   ├── order-service/      # FastAPI Order management (GKE)
│   └── user-service/       # Express.js User/Auth service (Cloud Run)
├── functions/
│   ├── image-processor/    # Resize images on GCS upload (Cloud Functions)
│   ├── order-notifier/     # Send emails on order events (Cloud Functions)
│   └── analytics-ingester/ # Nightly BigQuery sync (Cloud Scheduler + Functions)
├── workers/
│   └── inventory-worker/   # Go worker for inventory sync (Compute Engine)
├── playbooks/              # Operational runbooks
├── scripts/                # Setup, deploy, teardown scripts
└── .github/workflows/      # CI/CD (also see cloudbuild.yaml)
```

## Quick Start

### Prerequisites
- GCP project with billing enabled
- `gcloud` CLI authenticated
- `terraform` >= 1.6
- `kubectl`, `docker`

### 1. Set up infrastructure
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project ID
terraform init && terraform apply
```

### 2. Build and push images
```bash
./scripts/build-images.sh
```

### 3. Deploy services
```bash
./scripts/deploy.sh
```

### 4. Seed demo data
```bash
./scripts/seed-data.sh
```

### 5. Access the app
```bash
terraform output cloudmart_url
```

## Migration to AWS

This application is designed to be migrated to AWS using [MigrAIne](../MigrAI/). See [playbooks/gcp-to-aws-migration.md](playbooks/gcp-to-aws-migration.md) for the complete migration runbook.

### Service Equivalency Map
| GCP Service | AWS Equivalent |
|-------------|---------------|
| GKE | EKS |
| Cloud Run | ECS Fargate / App Runner |
| Cloud Functions | Lambda |
| Compute Engine | EC2 |
| Cloud SQL | RDS PostgreSQL |
| Firestore | DynamoDB |
| Cloud Storage | S3 |
| Pub/Sub | SNS + SQS |
| Memorystore | ElastiCache |
| BigQuery | Redshift / Athena |
| Cloud Load Balancing | ALB |
| Cloud Armor | WAF + Shield |
| Cloud DNS | Route 53 |
| Secret Manager | Secrets Manager |
| Cloud KMS | KMS |
| Artifact Registry | ECR |
| Cloud Build | CodePipeline + CodeBuild |
| IAM | IAM |
| VPC | VPC |
