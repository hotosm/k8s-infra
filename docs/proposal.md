# HOT’s Infrastructure Modernization: Kubernetes

## Requirement

- HOT is quite reliant on vendor-specific cloud services for various tools.
- We rely heavily on donated credits from cloud providers (today, we fully rely on AWS) and have minimal internal funding for infrastructure. This source comes with few guarantees! 
- Ideally we would have a cloud-agnostic approach to deployment, giving the flexibility to deploy anywhere if the case arises (AWS, Azure, Hetzner, on-prem).
- This is not a small task, and also won’t solve all of our problems, but it would be a great start to migrate as many services as possible to cloud-agnostic approaches, via open tools such as Kubernetes, KEDA (scaling), ArgoCD (GitOps), etc.

## Challenges

- Lack of time and resources to dedicate to this as a project - it’s difficult to justify addressing tech debt, when there is the allure of new features and updating software.
- Lack of expertise in the tech team 
  - Tech lead has previous k8s experience, but little time. 
  - Some devs at our partner NAXA have also dabbled with k8s.
- Heavy reliance of some tools on vendor-specific services.

In order of most difficult → least difficult for migration in our 2024 assessment:
  - OpenAerialMap (many AWS services / lambda etc).
  - fAIr (GPU reliant ML workflows, task scheduling, autoscaling).
  - Tasking Manager (autoscaling requirement, large user base).
  - Export tool / raw-data-api (task scheduling, redis queue based autoscaling)
  - FieldTM & DroneTM

## Benefits

- We would like to slowly start to become more cloud-agnostic in our deployment approach, making us more resilient to changes in the future.
- Reduced costs 🤞, with resource utilization spread across a smaller cluster of VMs, instead of many under-utilized standalone VMs, but still able to handle load spikes.

## Proposal

- The core of this requirement is to configure a Kubernetes cluster, and start to migrate services into it.
- This will involve two steps:
  - Setup of the Kubernetes control plane. Likely EKS, but also open to managing this ourselves with an OS like Talos.
  - Slow migration of services into the cluster, packaging them tools up as Helm charts, and deploying with all additional required components (autoscaling, job queue, etc).

### Step 1: Control Plane & OSM Sandbox

#### OSM Sandbox (Preamble)

- A while ago we made https://github.com/hotosm/osm-sandbox, in an effort to have a ‘sandboxed’ OSM backend that could be attached to other services like TM (for private data, demo projects, various use cases).
- Since then, we have decided to collaborate further with the developmentseed and osmus effort to create a deployment API for temporary osmseed instances.
- This osm-sandbox-dashboard API allows for osmseed instances to be provisioned on demand, by calling an API, and starting the services within a linked Kubernetes cluster.

#### Control Plane Setup

- We can either use EKS, or a custom control plane based on EC2 instances.
- Storage and networking must be configured.
- We can set up Gateway API or Ingress, plus certificate management of some sort.
- We need at least one attached worker node to deploy services onto.

#### End Goals

- A working Kubernetes cluster that we can deploy services into.
- A configured Helm chart (already exists) for the osm-sandbox-dashboard.
- Accessible via a URL - perhaps we have a DNS zone specifically for this, plus CNAME aliases to specific services.
- Also nice to have: ArgoCD with the config for osm-sandbox-dashboard pulled from a repo, plus an easy visualisation dashboard of running services in the cluster.

### Step 2: Deployment of Easier HOTOSM Apps

These apps have fewer moving parts, or are easier to package up and deploy (FieldTM has a partial helm chart already).

- FieldTM
- DroneTM
- Export Tool / Raw-Data-API
(in order)

#### FieldTM

- Some of the requirements for FieldTM are already captured in issues here: https://github.com/hotosm/field-tm/issues?q=is%3Aissue%20state%3Aopen%20label%3Adevops
- FieldTM requires a deployment of ODK alongside it, meaning we also need to make a helm chart for that (it would be great to contribute to the community, but first we should discuss with the ODK team).

#### DroneTM

- The deployment of DroneTM will be quite similar to FieldTM, but instead of a requirement for ODK, we also need to deploy OpenDroneMap, with NodeODM being scalable via CPU utilisation or queue length with a tool like KEDA.

#### Export Tool / Raw-Data-API

- Includes a Celery task queue.
- More notes to come.

### Step 3: Deployment of More Difficult HOTOSM Apps

These apps have many moving parts that must be replaced from their AWS specific service to a more vendor-neutral alternative.

- Tasking Manager
- fAIr
- OpenAerialMap
(in order)
