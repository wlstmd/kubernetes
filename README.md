# wlstmd/kubernetes

Useful script templates for Kubernetes related operations.

## this repo contains...

- Topic-organized EKS/K8s walkthroughs (each folder's README lists commands in order + explanations)
- K8s resource manifests (ACK, Karpenter, CSI drivers, Gatekeeper, etc.)
- Sample demo apps (Dockerfile + Go/Python)
- Core tooling install script (`scripts/`: kubectl, eksctl, helm, k9s)
- IAM policy JSON files for IRSA/ACK/CSI walkthroughs

## Table of contents

Each folder has its own README.md laid out in the order the steps are meant to be run (setup/config commands + explanation).

| Category                  | Topics                                                                                      |
| ------------------------- | ------------------------------------------------------------------------------------------- |
| **ACK**                   | apigateway, ec2_vpc, rds, s3                                                                |
| **Cluster / Autoscaling** | bottlerocket, ca, cpa, karpenter, ipv6, gatewayapi, ipvs                                    |
| **CI/CD & GitOps**        | argocd, codeseries, flux                                                                    |
| **Logging**               | cloudwatch+fluentbit, fargate, fluentd, efk, elk                                            |
| **Monitoring**            | grafana, loki, prometheus(+grafana), k8s_dashboard, k9s, jaeger, opentelemetry, x_ray       |
| **Security / Policy**     | apparmor, calico, networkpolicy, opa_gatekeeper, kyverno, pss_psa, ascp, sealed_secret, vso, kubearmor |
| **Service Mesh**          | app_mesh, istio, spire_spiffe_integration                                                   |
| **Storage**               | hostpath, shared, velero, volume_backup, statefulset_efs/local                              |
| **Networking**            | topology_aware_routing, pod_eip_controller, kongapigw                                       |
| **Other**                 | batch, emr_on_eks, keda, mwaa, nth, crossplane, kuberc, harbor, kafka_with_eks              |

- [batch](batch) — AWS Batch on EKS walkthrough
- [emr_on_eks](emr_on_eks) — Setting up EMR on EKS and running a Spark job
- [keda/basic](keda/basic) — Installing KEDA and configuring a cron-triggered ScaledObject
- [keda/etc](keda/etc) — KEDA AWS SQS TriggerAuthentication example
- [mwaa](mwaa) — Integrating MWAA (Managed Workflows for Apache Airflow)
- [nth](nth) — Installing the AWS Node Termination Handler (NTH)
- [crossplane](crossplane) — Provisioning AWS resources via Crossplane + provider-aws
- [kuberc](kuberc) — kubectl client-side preferences (`kuberc`): aliases + delete confirmation
- [harbor](harbor) — Installing Harbor as a self-hosted container registry
- [kafka_with_eks](kafka_with_eks) — Connecting EKS workloads to Amazon MSK (Kafka)

## licence

&copy; 2026. Jinseung Yu. <jinseung0327@gmail.com>.\
MIT Licensed. See [LICENSE](/LICENSE) file for more
