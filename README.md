# Airbyte Accelerator

This is an accelerator that can be used to generate a Kubernetes deployment for [Airbyte] Data Integration (https://airbyte.com/).

* Install App Accelerator: (see https://docs.vmware.com/en/Tanzu-Application-Platform/1.0/tap/GUID-cert-mgr-contour-fcd-install-cert-mgr.html)
```
tanzu package available list accelerator.apps.tanzu.vmware.com --namespace tap-install
tanzu package install accelerator -p accelerator.apps.tanzu.vmware.com -v 1.0.1 -n tap-install -f resources/app-accelerator-values.yaml
Verify that package is running: tanzu package installed get accelerator -n tap-install
Get the IP address for the App Accelerator API: kubectl get service -n accelerator-system
```

Publish Accelerators:
```
tanzu plugin install --local <path-to-tanzu-cli> all
tanzu acc create airbyte --git-repository https://github.com/agapebondservant/airbyte-accelerator.git --git-branch main
```

Publish Fragments:
```
tanzu acc fragment create airbyte-fragment --git-repository https://github.com/agapebondservant/airbyte-accelerator.git --git-branch main
```

## Contents
1. [Install Airbyte via vanilla Kubernetes/helm chart](#k8s)
2. [Integrate with dbt](#dbtintegrate)
3. [Integrate with TAP](#tapintegrate)

### Install Airflow via vanilla Kubernetes/helm chart<a name="k8s"/> 

#### Before you begin (one time setup):
1. Create an environment file `.env` (use `.env-sample` as a template), then run:
```
source .env
```

2. Set up helm repo (one-time op - skip if this has already been done):
```
helm repo add airbyte https://airbytehq.github.io/helm-charts
```

3. Create airbyte namespace and import TLS secret (secret should be predefined):
```
kubectl create ns airbyte
kubectl apply -f resources/secretimport.yaml -nairbyte
```

4. Install helm chart:
```
helm install ${DATA_E2E_AIRBYTE_HELM_RELEASE_NAME} airbyte/airbyte \
--version ${DATA_E2E_AIRBYTE_HELM_RELEASE_VERSION} \
--namespace ${DATA_E2E_AIRBYTE_HELM_RELEASE_NAMESPACE} \
--set webapp.ingress.enabled=true \
--set webapp.ingress.hosts[0].host=airbyte.${DATA_E2E_AIRBYTE_HELM_RELEASE_DOMAIN} \
--set webapp.ingress.hosts[0].paths[0].path=/ \
--set webapp.ingress.hosts[0].paths[0].pathType=ImplementationSpecific \
--set webapp.ingress.tls[0].hosts[0]=airbyte.${DATA_E2E_AIRBYTE_HELM_RELEASE_DOMAIN} \
--set webapp.ingress.tls[0].secretName=${DATA_E2E_AIRBYTE_HELM_RELEASE_TLS_SECRET} \
--create-namespace
```

4. To delete the Airbyte installation:
```
helm uninstall ${DATA_E2E_AIRBYTE_HELM_RELEASE_NAME} --namespace ${DATA_E2E_AIRBYTE_HELM_RELEASE_NAMESPACE}
kubectl delete ns ${DATA_E2E_AIRBYTE_HELM_RELEASE_NAMESPACE}
```

### Integrate with dbt <a name="dbtintegrate"/>
1. Install dbt on local workstation:
```

```
2. 

### Integrate with TAP <a name="tapintegrate"/> (Work in progress)
```