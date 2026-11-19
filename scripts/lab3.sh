#!/usr/bin/env bash
set -euo pipefail

# Carga las variables de entorno
source .env.sh

# Obtiene la identidad gestionada del usuario (`UAI`) y su principal ID
UAI_ID=$(az identity show -g "$RG" -n "$UAI" --query id -o tsv)
UAI_PRINCIPAL=$(az identity show -g "$RG" -n "$UAI" --query principalId -o tsv)
UAI_CLIENT=$(az identity show -g "$RG" -n "$UAI" --query clientId -o tsv)

# Azure Service Bus Standard porque Basic no soporta todos los escenarios requeridos.
az servicebus namespace create -g "$RG" -n "$SB_NAMESPACE" -l "$LOCATION" --sku Standard -o table

# Crea dos queues (colas)
az servicebus queue create -g "$RG" --namespace-name "$SB_NAMESPACE" -n ai-requests --max-delivery-count 5 -o none
az servicebus queue create -g "$RG" --namespace-name "$SB_NAMESPACE" -n ai-results --max-delivery-count 5 -o none

# Otorga permisos de sender y receiver sobre el Service Bus a la identidad gestionada.
SB_ID=$(az servicebus namespace show -g "$RG" -n "$SB_NAMESPACE" --query id -o tsv)
az role assignment create --assignee-object-id "$UAI_PRINCIPAL" --assignee-principal-type ServicePrincipal --role 'Azure Service Bus Data Receiver' --scope "$SB_ID" -o none
az role assignment create --assignee-object-id "$UAI_PRINCIPAL" --assignee-principal-type ServicePrincipal --role 'Azure Service Bus Data Sender' --scope "$SB_ID" -o none

# Compila la imagen del worker en ACR: `ai200-worker:v1`.
az acr build -r "$ACR" -t ai200-worker:v1 ./apps/worker

# Crea un Container App para el worker sin ingress, con: 
# 0 réplicas mínimas y 5 réplicas máximas
# CPU y memoria
# Configura una regla de escalado basada en Service Bus:
# con nombre, tipo, cola y umbral
# El namespace se indica sin sufijo .servicebus.windows.net en la metadata.
# Define variables de entorno del worker
az containerapp create -g "$RG" -n "$ACA_WORKER" --environment "$ACA_ENV" \
  --image "$ACR.azurecr.io/ai200-worker:v1" --user-assigned "$UAI_ID" \
  --registry-server "$ACR.azurecr.io" --registry-identity "$UAI_ID" \
  --min-replicas 0 --max-replicas 5 --cpu 0.5 --memory 1.0Gi \
  --scale-rule-name pending-ai-jobs --scale-rule-type azure-servicebus \
  --scale-rule-metadata "queueName=ai-requests" "namespace=$SB_NAMESPACE" "messageCount=2" \
  --scale-rule-identity "$UAI_ID" \
  --env-vars "AZURE_CLIENT_ID=$UAI_CLIENT" "SERVICEBUS_NAMESPACE=$SB_NAMESPACE" \
    'REQUEST_QUEUE=ai-requests' 'RESULT_QUEUE=ai-results' \
    "FOUNDRY_OPENAI_BASE_URL=$FOUNDRY_OPENAI_BASE_URL" "FOUNDRY_MODEL_DEPLOYMENT=$FOUNDRY_MODEL_DEPLOYMENT" -o table

printf '\nCreado worker sin ingress. Espera propagación de RBAC antes de enviar el lote.\n'
