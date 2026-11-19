# Laboratorio 2 — Azure Container Apps: entorno, revisiones, tráfico y rollback

**Objetivo:** Desplegar el frontend de IA en Container Apps, conectar ACR y Foundry con identidad administrada y demostrar una actualización gradual entre dos revisiones (revisión múltiple). 

## Arquitectura

Internet → Container Apps Environment → `aca-ai200-chat` (revisiones v1 y v2) → Microsoft Foundry. 

- La imagen es privada en ACR. 

## Despliegue

```bash
source .env.sh
./scripts/lab2.sh
ACA_URL="https://$(az containerapp show -g "$RG" -n "$ACA_WEB" --query properties.configuration.ingress.fqdn -o tsv)"
echo "$ACA_URL"
curl -fsS "$ACA_URL/health"
```

El script crea el entorno, crea el contenedor con puerto interno 8000 e ingress público, conecta el registro mediante identidad administrada y asigna la configuración del modelo. La identidad compartida se preparó en `bootstrap.sh`.

## Hacer una pregunta al modelo de Microsoft Foundry

```bash
curl -sS -X POST "$ACA_URL/api/chat" \
  -H 'Content-Type: application/json' \
  -d '{"question":"Explica una ventaja de Azure Container Apps."}'
```

Abre `$ACA_URL` en un navegador y utiliza el formulario. Para el ensayo inicial usa `min-replicas=1` para simplificar la observación del tráfico.

## Desplegar una segunda revisión

La imagen puede ser la misma: cambiar `APP_EDITION` modifica la plantilla y **crea otra revisión** porque es un cambio a la plantilla de ejecución. Para una actualización de código auténtica, compila otra imagen `v2` y sustitúyela en `--image`.

```bash
az containerapp update -g "$RG" -n "$ACA_WEB" \
  --set-env-vars APP_EDITION=v2 \
  --revision-suffix v2 -o table

az containerapp revision list -g "$RG" -n "$ACA_WEB" \
  --query '[].{name:name,active:properties.active,created:properties.createdTime}' -o table
```

Las revisiones se llaman habitualmente `<nombre-app>--v1` y `<nombre-app>--v2`. Confirma los nombres reales con el comando anterior.

## División 90/10

```bash
REV_V1=$(az containerapp revision list -g "$RG" -n "$ACA_WEB" --query "[?ends_with(name, '--v1')].name | [0]" -o tsv)
REV_V2=$(az containerapp revision list -g "$RG" -n "$ACA_WEB" --query "[?ends_with(name, '--v2')].name | [0]" -o tsv)

az containerapp ingress traffic set -g "$RG" -n "$ACA_WEB" \
  --revision-weight "$REV_V1=90" "$REV_V2=10"
az containerapp ingress traffic show -g "$RG" -n "$ACA_WEB" -o jsonc
```

Repite varias veces `curl "$ACA_URL/health"` y verifica el campo `edition`: no debes esperar una proporción exacta en pocas solicitudes. Para demostrar el 10% necesitas una muestra suficientemente grande y tener en cuenta persistencia de conexiones.

## Rollback

```bash
az containerapp ingress traffic set -g "$RG" -n "$ACA_WEB" \
  --revision-weight "$REV_V1=100" "$REV_V2=0"
az containerapp ingress traffic show -g "$RG" -n "$ACA_WEB" -o jsonc
```

**Rollback aquí significa volver a enrutar todo el tráfico a v1**, no eliminar físicamente v2.

## Logs y portal (solo comprobación)

```bash
az containerapp logs show -g "$RG" -n "$ACA_WEB" --tail 50
az containerapp show -g "$RG" -n "$ACA_WEB" --query properties.template -o jsonc
```

En Portal → Container Apps → `$ACA_WEB` → **Revision management**: revisa las revisiones activas y el porcentaje de tráfico; en **Logs** revisa las solicitudes. No uses el portal para cambiar configuraciones.

## Preguntas y evidencia

<details>
<summary>1. Explica la diferencia entre Environment, Container App, Revision y Replica. </summary>

- **Environment:** es el "entorno de ejecución" de Azure Container Apps.
- **Container App:** es la aplicación en sí.
- **Revision:** es una versión concreta de esa Container App.
- **Réplica:** es una instancia ejecutándose de esa revisión.

</details>

<details>
<summary>2. ¿Por qué cambiar variables de plantilla puede crear nueva revisión? </summary>

Porque Azure Container Apps trata cada cambio de configuración como una nueva versión de la aplicación.

- Una revisión se crea cada vez que la app cambia de "estado deseado" en la configuración.
- No cambia solo el contenido de la imagen, sino cualquier ajuste que afecte el comportamiento o despliegue.

> Por eso en ACA: "cambio de configuración = nueva revisión".

</details>

<details>
<summary>3. ¿Qué significa rollback cuando hay múltiples revisiones? </summary>

Rollback significa volver la aplicación a una versión anterior que estaba funcionando bien.

- La revisión vieja no desaparece; sigue existiendo.
- Puedes revertir el tráfico o cambiar la revisión activa.
- Esto es útil para:
  - Recuperar estabilidad.
  - Probar nuevas versiones sin miedo.
  - Hacer despliegues controlados.

</details>