#!/usr/bin/env bash
set -euo pipefail

# Leer variables de entorno
source .env.sh

# Confirmar que estás autenticado en Azure y mostrar la suscripción activa.
az account show --query '{subscription:id,name:name}' -o table

# Instalar la extensión de Container Apps en Azure CLI
az extension add --name containerapp --upgrade --yes

# Registrar proveedor de recursos para habilitar el uso y la creación de los servicios o tipos de recursos asociados a ese proveedor
az provider register --namespace Microsoft.App --wait
az provider register --namespace Microsoft.OperationalInsights --wait
az provider register --namespace Microsoft.Web --wait
az provider register --namespace Microsoft.ServiceBus --wait

# Crear el grupo de recursos (si ya existe no marca error)
az group create -n "$RG" -l "$LOCATION" -o table

# Crear el Azure Container Registry con SKU Básico y sin admin user
az acr create -g "$RG" -n "$ACR" --sku Basic --admin-enabled false -o table

# Crear una identidad administrada para que la app pueda autenticarse sin secretos.
az identity create -g "$RG" -n "$UAI" -o table

UAI_ID=$(az identity show -g "$RG" -n "$UAI" --query id -o tsv)
UAI_PRINCIPAL=$(az identity show -g "$RG" -n "$UAI" --query principalId -o tsv)
ACR_ID=$(az acr show -g "$RG" -n "$ACR" --query id -o tsv)

# Otorgar los permisos
# AcrPull al identity para descargar la imagen desde ACR
# Cognitive Services OpenAI User para usar el modelo de Foundry

az role assignment create --assignee-object-id "$UAI_PRINCIPAL" --assignee-principal-type ServicePrincipal --role AcrPull --scope "$ACR_ID" -o none
az role assignment create --assignee-object-id "$UAI_PRINCIPAL" --assignee-principal-type ServicePrincipal --role 'Cognitive Services OpenAI User' --scope "$FOUNDRY_RESOURCE_ID" -o none

# Construir la imagen del frontend/chat en ACR directamente desde el código del repo.
az acr build -r "$ACR" -t ai200-chat:v1 ./apps/chat

printf '\nBootstrap completado: %s.azurecr.io/ai200-chat:v1\n' "$ACR"
