# Laboratorio 3 — KEDA: escalado real con Azure Service Bus y un worker de IA

**Objetivo:** ejecutar un worker sin HTTP ingress que procese solicitudes de IA desde Service Bus usando un modelo real de Microsoft Foundry. KEDA escala de 0 a 5 réplicas conforme a los mensajes pendientes. 

## Arquitectura

Cliente Python → cola `ai-requests` → **KEDA Azure Service Bus scaler** → réplicas del worker → Microsoft Foundry → cola `ai-results` → cliente Python.

El worker genera respuestas mediante la API real del modelo. La cantidad de mensajes impulsa la decisión de escalado. 

## Crear infraestructura y worker

Requiere `bootstrap.sh` y `lab2.sh` (para reutilizar Container Apps Environment). No requiere el frontend de lab2 funcionando en ese momento.

```bash
source .env.sh
./scripts/lab3.sh
az containerapp show -g "$RG" -n "$ACA_WORKER" --query properties.template.scale -o jsonc
az servicebus queue show -g "$RG" --namespace-name "$SB_NAMESPACE" -n ai-requests \
  --query '{active:countDetails.activeMessageCount,deadletter:countDetails.deadLetterMessageCount}' -o jsonc
```

La infraestructura incluye Service Bus Standard, dos colas, roles RBAC para la identidad de Container Apps, imagen worker en ACR y regla `azure-servicebus` con umbral `messageCount=2` y `min-replicas=0`.

## Otorgar acceso

Tu usuario de Azure CLI también necesita roles de datos para enviar y leer mensajes:

```bash
MY_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
SB_ID=$(az servicebus namespace show -g "$RG" -n "$SB_NAMESPACE" --query id -o tsv)
az role assignment create --assignee-object-id "$MY_OBJECT_ID" --assignee-principal-type User \
  --role 'Azure Service Bus Data Sender' --scope "$SB_ID"
az role assignment create --assignee-object-id "$MY_OBJECT_ID" --assignee-principal-type User \
  --role 'Azure Service Bus Data Receiver' --scope "$SB_ID"
```

Si tu cuenta no puede leer Microsoft Entra Directory, consulta el Object ID en Azure CLI/Portal con una cuenta autorizada. Espera la propagación de RBAC antes de enviar solicitudes.

## Enviar mensajes de IA

En una terminal con Python 3.10+ (y `az login`), desde la raíz:

**Advertencia de costo:** cada mensaje activa una llamada al modelo; 30 mensajes implican hasta 30 inferencias, y los reintentos podrían incrementar ese número. Para una primera prueba usa `--count 3`.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r apps/client/requirements.txt
python apps/client/send.py --namespace "$SB_NAMESPACE" --count 30 \
  --question '¿Cuándo es útil aplicar escalado por eventos en una API de IA?'
```

## Comprobar escalado, logs y salida

```bash
az containerapp replica list -g "$RG" -n "$ACA_WORKER" -o table
az containerapp logs show -g "$RG" -n "$ACA_WORKER" --tail 50
az servicebus queue show -g "$RG" --namespace-name "$SB_NAMESPACE" -n ai-requests \
  --query countDetails -o jsonc
python apps/client/receive.py --namespace "$SB_NAMESPACE" --limit 30
```

El worker confirma mensajes **después** de publicar el resultado. Si falla una inferencia, abandona el mensaje para reintento; después de repetidos fallos, Service Bus puede moverlo a la dead-letter queue. Los resultados incluyen `id`, pregunta, respuesta, marca temporal y nombre de la réplica.

Los cambios de réplicas no son instantáneos: observa durante varios intervalos. Si no aparecen réplicas, comprueba la regla de escala, roles y logs de sistema en Portal.

## Portal: Verificación

Portal → Container Apps → `$ACA_WORKER` → **Scale**, **Replicas**, **Log stream**. Portal → Service Bus → `$SB_NAMESPACE` → **Queues** → observa mensajes activos y dead-letter. No se requiere hacer cambios desde el portal.

## Preguntas

<details>
  <summary>1. ¿Qué mide realmente el scaler? ¿Qué significa `messageCount=2`?</summary>

El scaler de Azure Container Apps para Service Bus mide los mensajes pendientes en la cola `ai-requests`. `messageCount=2` indica el objetivo de carga de dos mensajes pendientes por réplica para calcular el escalado; no es estrictamente un umbral único de activación desde cero.

</details>

<details>
  <summary>2. ¿Por qué un worker no necesita ingress HTTP?</summary>
El worker no sirve páginas ni recibe tráfico web directo.

  Su función es:

  - escuchar mensajes de una cola
  - procesar trabajo
  - enviar resultados a otra cola
  - consumir eventos asincrónicos
  </details>

<details>
  <summary>3. ¿En qué condiciones podemos bajar a cero y cuándo podría no suceder inmediatamente?</summary>

`min-replicas = 0` permite escalar a cero. No siempre ocurre “al instante”, depende de la cola, del tiempo de verificación y del estado de las réplicas actuales

</details>
