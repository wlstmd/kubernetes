# Topology Aware Routing / Pod Topology Spread Constraints

해당 존에서 발생한 트래픽은 해당 존에서 유지되는 것을 목표로 한다.

비용적인 측면에서도 다른 AZ에 대해서 통신을 하지 않기 때문에 많이 절약할 수 있고 네트워크 홉도 줄 일 수 있게 됩니다. 아무래도 각 AZ 별로 엔드포인트가 많아야 효용이 높다.

만약 같은 AZ에 목적지 파드가 없는 경우 다른 AZ라도 요청을 보내게 된다. 다만 Topology Aware Routing를 사용하지 않기 때문에 endpointslices에서 hints 정보는 사라지게 된다.

`service.kubernetes.io/topology-mode=auto`라는 annotation을 service에 추가해주면 된다.

```bash
kubectl annotate service <SERVICE_NAME> "service.kubernetes.io/topology-mode=auto"
```

- endpointslices 를 조회해서 hints 정보를 확인할 수 있다.

```bash
kubectl get endpointslices -l kubernetes.io/service-name=<SERVICE_NAME> -o yaml
```

- **hints 정보 삭제**

```bash
kubectl annotate service <SERVICE_NAME> "service.kubernetes.io/topology-mode-"
```

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-svc
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "external"
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "instance"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "false"
    service.kubernetes.io/topology-mode: auto
spec:
  type: LoadBalancer
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
  selector:
    app: nginx
```

> **Pod Topology Spread Constraints**

Pod Topology Spread Constraints는 해당 pod가 어디에 스케쥴링 되어야 할지 결정하는 하나의 옵션으로 labelSelector에 적힌 pod끼리 topologyKey가 최대한 겹치지 않도록 분산하게 된다.

maxSkew는 민감도를 결정하며 labelSelector에 맞는 pod가 몇개나 한쪽에 쏠려있어도 되는가를 결정한다

nodeAffinity와 nodeSelector 가 이 pod topology spread constraints보다 우선순위가 높으며KubeSchedulerConfiguration을 통해 클러스터의 기본값을 설정할 수 있다 (EKS에선 불가)

```yaml
spec:
	topologySpreadConstraints:
	  - maxSkew: 1
			topologyKey: topology.kubernetes.io/zone
			whenUnsatisfiable: DoNotSchedule
			labelSelector:
				matchLabels:
					app: myapp
```

> maxSkew (가장 적은 pod가 배치된 zone과 가장 많은 pod가 배치된 zone 간의 **차이 개수 허용치)**

`maxSkew: 1`이면:

- `zone-a`에 3개, `zone-b`에 2개 → ✅ 허용
- `zone-a`에 3개, `zone-b`에 1개 → ❌ 허용 안 됨

> topologyKey (pod를 **어떤 토폴로지 기준으로 분산**할지를 지정)

- topology.kubernetes.io/zone (**Availability Zone** 기준으로 분산)
- topology.kubernetes.io/hostname (노드 단위 분산)

> whenUnsatisfiable

- DoNotSchedule (제약 조건을 만족하지 못할 경우 **Pod를 스케줄하지 않음)**
- ScheduleAnyway (무시하고 그냥 스케줄)
</content>
