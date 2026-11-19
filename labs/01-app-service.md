# Laboratorio 1 — Azure App Service: frontend + modelo real de Microsoft Foundry

**Objetivo:** desplegar una API FastAPI con frontend HTML desde ACR en App Service, configurar variables, acceder a Foundry con identidad administrada y examinar logs. 

## Arquitectura

Navegador → App Service (contenedor FastAPI) → Microsoft Foundry (Responses API). 

- El contenedor se descarga desde ACR mediante la identidad de App Service. 
- Las respuestas provienen del deployment de modelo que configuraste.

## Preparación

Ejecuta desde la **raíz** del repositorio (Bash o Azure Cloud Shell), después de configurar `.env.sh` y ejecutar `./scripts/bootstrap.sh`:

```bash
source .env.sh
./scripts/lab1.sh
```

Este script crea App Service Plan Linux B1; instancia Web App; identidad administrada; roles `AcrPull` y `Cognitive Services OpenAI User`; variables `WEBSITES_PORT`, `FOUNDRY_OPENAI_BASE_URL`, `FOUNDRY_MODEL_DEPLOYMENT`; y selecciona la imagen de ACR.

## Verificación desde Azure CLI

```bash
curl -fsS "https://$WEBAPP.azurewebsites.net/health"
curl -fsS "https://$WEBAPP.azurewebsites.net/config"
curl -sS -X POST "https://$WEBAPP.azurewebsites.net/api/chat" \
  -H 'Content-Type: application/json' \
  -d '{"question":"Explica qué es Azure App Service en dos frases."}'

az webapp config container show -g "$RG" -n "$WEBAPP" -o jsonc
az webapp config appsettings list -g "$RG" -n "$WEBAPP" \
  --query '[].name' -o table
az webapp log config -g "$RG" -n "$WEBAPP" --docker-container-logging filesystem
az webapp log tail -g "$RG" -n "$WEBAPP"
```

- `/health` debe devolver `status: ok`. 
- La API de chat solo funciona si el modelo y su autenticación están configurados.
  - Si recibes HTTP 502, consulta los logs y permisos. 
- El endpoint `/config` nunca muestra valores de configuración ni secretos.

## Variables y secretos: demostración sin exponer contenido

```bash
az webapp config appsettings set -g "$RG" -n "$WEBAPP" \
  --settings 'LAB_DEMO_SECRET=demostracion-no-es-una-clave-real'
curl -fsS "https://$WEBAPP.azurewebsites.net/config"
```

Para secretos **reales** en producción, utiliza Azure Key Vault references en App Settings junto a la identidad administrada. No pegues claves en repositorios ni capturas. La llamada al modelo de esta práctica **no necesita API key**: usa Microsoft Entra ID.

### Comprobación opcional en Portal

Azure Portal → App Services → `$WEBAPP` → **Deployment Center / Container settings** para observar la imagen, **Environment variables** para revisar nombres (no mostrar secretos en clase) y **Log stream** para visualizar logs. Todas las configuraciones se hacen por CLI.

## Preguntas

<details>
<summary>1. ¿Qué diferencia existe entre `WEBSITES_PORT` y el puerto expuesto por la aplicación?</summary>

- `WEBSITES_PORT` = "puerto que App Service debe usar para llegar al contenedor".
- Puerto de la app = "puerto donde la app escucha dentro del contenedor".

Ambos deben coincidir para que funcione.

</details>

<details>
<summary>2. ¿Qué rol permite descargar imágenes de ACR? ¿Qué rol permite invocar el modelo?</summary>

- `AcrPull` permite descargar imágenes de ACR.
- `Cognitive Services OpenAI User` permite invocar el modelo.

</details>

<details>
<summary>3. ¿Por qué es más seguro usar identidad administrada que copiar una API key?</summary>

Una API key es como una contraseña compartida en texto plano. Una identidad administrada es como un pase temporal emitido por Azure, solo para ese servicio y con permisos limitados.

</details>

## Ejercicio adicional: un secreto real con Azure Key Vault

Este ejercicio es independiente del acceso a Foundry (que sigue usando identidad administrada). Sirve para demostrar la **inyección segura** de un secreto mediante una referencia de Key Vault sin copiar el valor a la configuración de App Service. Necesitas permisos para crear un vault y asignar roles.

```bash
source .env.sh
KV="kv-ai200-${SUFFIX}"
az keyvault create -g "$RG" -n "$KV" -l "$LOCATION" --enable-rbac-authorization true
VAULT_ID=$(az keyvault show -n "$KV" --query id -o tsv)
MY_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
WEB_PRINCIPAL=$(az webapp identity show -g "$RG" -n "$WEBAPP" --query principalId -o tsv)

# Escribir secretos en el vault.
az role assignment create --assignee-object-id "$MY_OBJECT_ID" --assignee-principal-type User \
  --role 'Key Vault Secrets Officer' --scope "$VAULT_ID"
# App Service solo puede LEER los secretos.
az role assignment create --assignee-object-id "$WEB_PRINCIPAL" --assignee-principal-type ServicePrincipal \
  --role 'Key Vault Secrets User' --scope "$VAULT_ID"

# Tras la propagación de RBAC, escribe un valor demostrativo.
az keyvault secret set --vault-name "$KV" --name classroom-greeting \
  --value 'Hola desde Key Vault' --output none
SECRET_URI=$(az keyvault secret show --vault-name "$KV" --name classroom-greeting --query id -o tsv)

az webapp config appsettings set -g "$RG" -n "$WEBAPP" \
  --settings "LAB_DEMO_SECRET=@Microsoft.KeyVault(SecretUri=$SECRET_URI)" --output none

# Comprueba únicamente que el valor fue resuelto, sin exponer el contenido:
curl -fsS "https://$WEBAPP.azurewebsites.net/config"
```

**Resultado esperado:** `secret_configured: true`. El código jamás devuelve el secreto. La propagación de RBAC y la resolución de Key Vault References pueden demorar. En Azure Portal → App Service → **Environment variables**, comprueba el indicador de referencia a Key Vault. No abras ni proyectes el valor secreto.
