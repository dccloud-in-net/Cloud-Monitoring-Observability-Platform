# Runbooks

Linked from `runbook_url` annotations on each alert.

## OTelCollectorDown

**Symptoms**
- `up{job="otel-collector"} == 0` for >5m.
- Grafana panels for spans/metrics/logs flatline.

**Diagnosis**
```bash
kubectl -n opentelemetry get pods -l app.kubernetes.io/name=opentelemetry-collector
kubectl -n opentelemetry describe pod -l app.kubernetes.io/name=opentelemetry-collector
kubectl -n opentelemetry logs deploy/otel-collector --tail=200
```

**Common causes**
1. Bad collector config — operator rejects the CR. `kubectl get
   opentelemetrycollector -A` shows status.
2. PVC pressure on the obs node pool.
3. Exporter endpoint unreachable (Tempo/Prometheus pod down).

**Mitigation**
- Roll back the OTel Collector CR: `kubectl rollout undo deploy/otel-collector -n opentelemetry`
- Scale up obs node pool: `az aks nodepool scale -g $RG --cluster-name $AKS --name obs --node-count 3`

---

## SLOErrorBudgetBurnFast

**What it means**
- The service is burning 2% of its 30-day error budget in 1 hour. At this
  rate the budget is gone in 2 days.

**Diagnosis**
1. Open the **Application Golden Signals** dashboard, filter by service.
2. Pivot from error-rate panel into Tempo via "Logs ⇄ Traces" link.
3. Check the **OTel Pipeline Health** dashboard — sometimes "errors" are
   the collector dropping spans, not a real app failure.

**Mitigation**
- If the cause is a bad deploy: `kubectl rollout undo deploy/<svc> -n demo-apps`
- If downstream dependency: open the trace, identify the slow/erroring span,
  page the owning team.

---

## KubeNodeNotReady

**Diagnosis**
```bash
kubectl get nodes
kubectl describe node <node>
az vmss list-instances -g MC_<rg>_<aks>_<region> --name <vmss> -o table
```

**Mitigation**
- Cordon and drain: `kubectl cordon <node> && kubectl drain <node> --ignore-daemonsets --delete-emptydir-data`
- Trigger reimage: `az vmss reimage --instance-ids <id> -g MC_... --name <vmss>`
- If pattern affects multiple nodes, escalate to Azure support — usually a
  region-level NIC or storage issue.

---

## Grafana dashboards missing

- The sidecar imports any ConfigMap labelled `grafana_dashboard=1`. Verify:
  `kubectl -n observability get cm -l grafana_dashboard=1`.
- Reload sidecar: `kubectl -n observability delete pod -l app.kubernetes.io/name=grafana`.
