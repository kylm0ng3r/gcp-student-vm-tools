#!/usr/bin/env bash
set -euo pipefail

############################################
# CONFIG
############################################

PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT" ]]; then
  echo "❌ No active GCP project. Run: gcloud init"
  exit 1
fi

VM_PREFIX="student"
MAX_VCPUS=32
PARALLELISM=4

TYPE_2CPU="e2-standard-2"
TYPE_1CPU="custom-1-4096"

PREFERRED_REGIONS=(
  northamerica-northeast2
  northamerica-northeast1
  us-east5
  us-east4
  us-central1
  us-south1
  us-west3
  us-west4
  us-west1
  us-west2
  northamerica-south1
  europe-southwest1
  europe-west2
)

############################################
# SAFE INITIALIZATION (for set -u)
############################################

TWO_CPU_COUNT=0
ONE_CPU_COUNT=0
CREATED_COUNT=0

############################################
# FIND NEXT AVAILABLE INDEX (CORRECT)
############################################

# Extract numeric suffix ONLY (01, 02, ...)
EXISTING_MAX="$(
  gcloud compute instances list \
    --project="$PROJECT" \
    --format="value(name)" \
  | awk -F'-' -v p="$VM_PREFIX" '
      $1==p && $2 ~ /^[0-9]+$/ { print $2 }
    ' \
  | sort -n \
  | tail -1
)"

if [[ -z "$EXISTING_MAX" ]]; then
  INDEX=1
else
  INDEX=$((10#$EXISTING_MAX + 1))
fi

############################################
# MODE SELECTION
############################################

echo "Select VM creation mode:"
echo "1) Beast Mode (smart 2 vCPU / 1 vCPU allocation)"
echo "2) Lazy Mode  (all VMs = 1 vCPU)"
read -rp "Enter choice [1/2]: " MODE_CHOICE

case "$MODE_CHOICE" in
  1) MODE="BEAST" ;;
  2) MODE="LAZY" ;;
  *) echo "❌ Invalid choice"; exit 1 ;;
esac

############################################
# INPUT
############################################

read -rp "How many Student VMs do you want to create? " VM_COUNT
if ! [[ "$VM_COUNT" =~ ^[0-9]+$ ]] || (( VM_COUNT <= 0 )); then
  echo "❌ Invalid VM count"
  exit 1
fi

############################################
# PHASE 1 — PLANNING
############################################

VM_PLAN=()

if [[ "$MODE" == "LAZY" ]]; then
  ONE_CPU_COUNT="$VM_COUNT"
  TWO_CPU_COUNT=0
  for ((i=0; i<VM_COUNT; i++)); do VM_PLAN+=("1"); done
else
  if (( VM_COUNT * 2 <= MAX_VCPUS )); then
    TWO_CPU_COUNT="$VM_COUNT"
    ONE_CPU_COUNT=0
  else
    ONE_CPU_COUNT=$(( VM_COUNT * 2 - MAX_VCPUS ))
    TWO_CPU_COUNT=$(( VM_COUNT - ONE_CPU_COUNT ))
  fi

  for ((i=0; i<TWO_CPU_COUNT; i++)); do VM_PLAN+=("2"); done
  for ((i=0; i<ONE_CPU_COUNT; i++)); do VM_PLAN+=("1"); done
fi

echo
echo "Creation plan:"
echo "  Mode        : $MODE"
echo "  Total VMs   : ${#VM_PLAN[@]}"
echo "  2 vCPU VMs  : $TWO_CPU_COUNT"
echo "  1 vCPU VMs  : $ONE_CPU_COUNT"
echo "  Parallelism : $PARALLELISM"
echo

############################################
# BUILD ZONE LIST
############################################

ZONES=()

for REGION in "${PREFERRED_REGIONS[@]}"; do
  while IFS= read -r Z; do
    ZONES+=("$Z")
  done < <(
    gcloud compute zones list \
      --filter="region:${REGION}" \
      --format="value(name)"
  )
done

while IFS= read -r Z; do
  if [[ ! " ${ZONES[*]} " =~ " ${Z} " ]]; then
    ZONES+=("$Z")
  fi
done < <(gcloud compute zones list --format="value(name)")

ZONE_COUNT="${#ZONES[@]}"

############################################
# PHASE 2 — EXECUTION (PARALLEL)
############################################

create_vm() {
  local VM_NAME="$1"
  local MACHINE_TYPE="$2"
  local START_ZONE_INDEX="$3"

  for ((i=0; i<ZONE_COUNT; i++)); do
    local ZONE_INDEX=$(( (START_ZONE_INDEX + i) % ZONE_COUNT ))
    local ZONE="${ZONES[$ZONE_INDEX]}"

    echo "→ Trying $VM_NAME ($MACHINE_TYPE) in $ZONE"

    if gcloud compute instances create "$VM_NAME" \
      --project="$PROJECT" \
      --zone="$ZONE" \
      --machine-type="$MACHINE_TYPE" \
      --image-family=windows-2022 \
      --image-project=windows-cloud \
      --boot-disk-size=50GB \
      --quiet; then

      echo "✔ Created $VM_NAME in $ZONE"
      echo "$ZONE_INDEX" > "/tmp/${VM_NAME}.zone"
      return 0
    fi
  done

  echo "❌ Failed to create $VM_NAME in all zones"
  return 1
}

export -f create_vm
export PROJECT ZONES ZONE_COUNT

# Clean up any leftover .zone files from previous runs
rm -f /tmp/${VM_PREFIX}-*.zone

START_ZONE_INDEX=0
PIDS=()

for CPU in "${VM_PLAN[@]}"; do
  NUM="$(printf "%02d" "$INDEX")"
  VM_NAME="${VM_PREFIX}-${NUM}"

  if [[ "$CPU" == "2" ]]; then
    MACHINE_TYPE="$TYPE_2CPU"
  else
    MACHINE_TYPE="$TYPE_1CPU"
  fi

  create_vm "$VM_NAME" "$MACHINE_TYPE" "$START_ZONE_INDEX" &
  PIDS+=("$!")
  INDEX=$((INDEX + 1))

  if (( ${#PIDS[@]} >= PARALLELISM )); then
    wait "${PIDS[0]}"
    PIDS=("${PIDS[@]:1}")
  fi
done

wait

for FILE in /tmp/${VM_PREFIX}-*.zone; do
  [[ -f "$FILE" ]] || continue
  CREATED_COUNT=$((CREATED_COUNT + 1))
  START_ZONE_INDEX="$(cat "$FILE")"
  rm -f "$FILE"
done

############################################
# SUMMARY (ALWAYS PRINTED)
############################################

# Count vCPUs from ALL running student VMs
USED_VCPUS=0
while IFS= read -r MTYPE; do
  case "$MTYPE" in
    e2-standard-2) USED_VCPUS=$((USED_VCPUS + 2)) ;;
    custom-1-*|e2-micro|e2-small|f1-micro|g1-small) USED_VCPUS=$((USED_VCPUS + 1)) ;;
    *) USED_VCPUS=$((USED_VCPUS + 1)) ;;  # Default to 1 for unknown types
  esac
done < <(gcloud compute instances list --project="$PROJECT" --filter="name~^${VM_PREFIX}-" --format="value(machineType.basename())")

FREE_VCPUS=$((MAX_VCPUS - USED_VCPUS))

echo
echo "======================================"
echo "RDP CONNECTION DETAILS"
echo "======================================"
echo

gcloud compute instances list \
  --project="$PROJECT" \
  --filter="name~^${VM_PREFIX}-" \
  --format="table(name,zone.basename(),EXTERNAL_IP)"

echo
echo "✔ Student VMs created successfully."
echo "✔ VM deletion handled centrally at 02:15 UTC (Cloud Scheduler)."
echo
echo "Created VMs : $CREATED_COUNT"
echo "Used vCPUs  : $USED_VCPUS"
echo "Free vCPUs  : $FREE_VCPUS"

