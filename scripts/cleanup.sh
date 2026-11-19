#!/usr/bin/env bash
set -euo pipefail
source .env.sh
printf 'ATENCIÓN: se eliminará TODO el grupo de recursos %s (puede contener recursos de otros ejercicios).\n' "$RG"
read -r -p 'Escribe ELIMINAR para confirmar: ' confirmation
[[ "$confirmation" == 'ELIMINAR' ]] || { echo 'Cancelado'; exit 1; }
az group delete -n "$RG" --yes --no-wait
