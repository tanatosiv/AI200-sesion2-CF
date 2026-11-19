#!/usr/bin/env bash
set -euo pipefail

# Cargar las variables de entorno desde `.env.sh`.
source .env.sh

# Recupera la identidad gestionada del usuario (`UAI`) creada en el bootstrap.
UAI_ID=$(az identity show -g "$RG" -n "$UAI" --query id -o tsv)

# Crea un entorno de Azure Container Apps (`ACA_ENV`).
az containerapp env create -g "$RG" -n "$ACA_ENV" -l "$LOCATION" -o table

# Crea un contenedor de la app con: 
#   imagen, identidad administrada, acceso al ACR con la identidad, ingress externo, puerto 8000, modo de revisiones múltiple
# Además, configura variables de entorno para el contenedor:
az containerapp create -g "$RG" -n "$ACA_WEB" --environment "$ACA_ENV" \
  --image "$ACR.azurecr.io/ai200-chat:v1" --user-assigned "$UAI_ID" \
  --registry-server "$ACR.azurecr.io" --registry-identity "$UAI_ID" \
  --ingress external --target-port 8000 --min-replicas 1 --max-replicas 3 \
  --revisions-mode multiple --revision-suffix v1 \
  --env-vars "AZURE_CLIENT_ID=$(az identity show -g "$RG" -n "$UAI" --query clientId -o tsv)" \
     "FOUNDRY_OPENAI_BASE_URL=$FOUNDRY_OPENAI_BASE_URL" "FOUNDRY_MODEL_DEPLOYMENT=$FOUNDRY_MODEL_DEPLOYMENT" "APP_EDITION=v1" -o table

# Muestra la URL pública de la aplicación
az containerapp show -g "$RG" -n "$ACA_WEB" --query properties.configuration.ingress.fqdn -o tsv
