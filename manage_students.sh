#!/usr/bin/env bash
set -e

############################################
# CONFIG — stable version (NO Zoom hacks)
############################################
PROJECT="zoom-lab-001"
IMAGE_FAMILY="zoom-student"
IMAGE_PROJECT="zoom-lab-001"

MACHINE_TYPE="e2-standard-2"
BOOT_DISK_SIZE="20GB"
BOOT_DISK_TYPE="pd-balanced"

LINUX_USER="student"
PASSWORD="student123"
TAG="rdp"

ZONES=(
  us-central1-a
  us-central1-b
  us-central1-c
  europe-west1-b
  europe-west1-c
)

############################################
# Ask number of VMs
############################################
echo
read -p "How many Student VMs do you want to create? " COUNT
echo

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [[ "$COUNT" -le 0 ]]; then
  echo "❌ Invalid number."
  exit 1
fi

############################################
# Find next available student index
############################################
EXISTING_MAX=$(gcloud compute instances list \
  --project="$PROJECT" \
  --format="value(name)" \
  | grep '^student-' \
  | sed 's/student-//' \
  | sort -n \
  | tail -1)

if [[ -z "$EXISTING_MAX" ]]; then
  INDEX=1
else
  INDEX=$((EXISTING_MAX + 1))
fi

############################################
# Create VMs
############################################
echo "Creating $COUNT Student VMs using $MACHINE_TYPE..."
echo

CREATED=0

while [[ "$CREATED" -lt "$COUNT" ]]; do
  VM_NUM=$(printf "%02d" "$INDEX")
  VM_NAME="student-$VM_NUM"

  ZONE_INDEX=$((CREATED % ${#ZONES[@]}))
  ZONE="${ZONES[$ZONE_INDEX]}"

  echo "→ Creating $VM_NAME in $ZONE"

  gcloud compute instances create "$VM_NAME" \
    --project="$PROJECT" \
    --zone="$ZONE" \
    --machine-type="$MACHINE_TYPE" \
    --image-family="$IMAGE_FAMILY" \
    --image-project="$IMAGE_PROJECT" \
    --boot-disk-size="$BOOT_DISK_SIZE" \
    --boot-disk-type="$BOOT_DISK_TYPE" \
    --tags="$TAG" \
    --quiet

  gcloud compute instances list \
    --project="$PROJECT" \
    --filter="name=$VM_NAME" \
    --zones="$ZONE"

  INDEX=$((INDEX + 1))
  CREATED=$((CREATED + 1))
done

############################################
# Summary
############################################
echo
echo "======================================"
echo "RDP CONNECTION DETAILS"
echo "======================================"
echo "Login: $LINUX_USER / $PASSWORD"
echo

gcloud compute instances list \
  --project="$PROJECT" \
  --filter="name~^student-" \
  --format="table(name,zone.basename(),EXTERNAL_IP)"

echo
echo "✔ Student VMs created successfully."
echo "✔ Cleanup handled server-side (Cloud Scheduler)."

