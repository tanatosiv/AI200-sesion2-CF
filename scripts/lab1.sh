#!/usr/bin/env bash
set -euo pipefail

# Carga las variables de entorno 
source .env.sh

# Crea un App Service Plan Linux con SKU `B1`.
az appservice plan create -g "$RG" -n "$PLAN" --is-linux --sku B1 -l "$LOCATION" -o table

# Crea una instancia de Azure Web App basada en una imagen de contenedor provisional: se cambiará por ACR tras configurar permisos.
az webapp create -g "$RG" -p "$PLAN" -n "$WEBAPP" --deployment-container-image-name 'mcr.microsoft.com/azuredocs/aci-helloworld:latest' -o table

# Asigna una identidad administrada al Web App.
WEB_PRINCIPAL=$(az webapp identity assign -g "$RG" -n "$WEBAPP" --query principalId -o tsv)

# Otorga permisos de lectura del ACR (`AcrPull`) y acceso al modelo de Azure OpenAI mediante RBAC.
ACR_ID=$(az acr show -n "$ACR" -g "$RG" --query id -o tsv)
az role assignment create --assignee-object-id "$WEB_PRINCIPAL" --assignee-principal-type ServicePrincipal --role AcrPull --scope "$ACR_ID" -o none
az role assignment create --assignee-object-id "$WEB_PRINCIPAL" --assignee-principal-type ServicePrincipal --role 'Cognitive Services OpenAI User' --scope "$FOUNDRY_RESOURCE_ID" -o none

# Configura el Web App para usar credenciales manejadas de ACR
az webapp config set -g "$RG" -n "$WEBAPP" --generic-configurations '{"acrUseManagedIdentityCreds": true}' -o none

# Define variables de entorno necesarias para la app
az webapp config appsettings set -g "$RG" -n "$WEBAPP" --settings "WEBSITES_PORT=8000" "APP_EDITION=appservice-v1" "FOUNDRY_OPENAI_BASE_URL=$FOUNDRY_OPENAI_BASE_URL" "FOUNDRY_MODEL_DEPLOYMENT=$FOUNDRY_MODEL_DEPLOYMENT" -o none

# Reemplaza la imagen del contenedor por la imagen compilada en ACR
az webapp config container set -g "$RG" -n "$WEBAPP" --container-image-name "$ACR.azurecr.io/ai200-chat:v1" --docker-registry-server-url "https://$ACR.azurecr.io" -o none

# Reinicia la app
az webapp restart -g "$RG" -n "$WEBAPP"

# Muestra la URL pública del servicio
echo "URL: https://$WEBAPP.azurewebsites.net"

echo "Verifica /health y /config antes de consultar el modelo. Los permisos RBAC pueden tardar en propagarse."
