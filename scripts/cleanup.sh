#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Cleanly tear down the DevOps Agent Autonomous Investigation & Self-Healing Stack
# ==============================================================================

STACK_NAME="${STACK_NAME:-da-auto-investigation}"
REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo 'us-east-1')}"

echo "=================================================================="
echo " Deleting CloudFormation Stack : ${STACK_NAME} (${REGION})"
echo "=================================================================="

aws cloudformation delete-stack \
  --region "${REGION}" \
  --stack-name "${STACK_NAME}"

echo "[+] Waiting for stack deletion to complete..."
aws cloudformation wait stack-delete-complete \
  --region "${REGION}" \
  --stack-name "${STACK_NAME}"

echo "[+] Stack '${STACK_NAME}' deleted successfully."
