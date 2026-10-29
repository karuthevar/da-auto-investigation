#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Deploy AWS DevOps Agent Autonomous Investigation & Self-Healing EC2 Stack
# Auto-discovers Default VPC/Subnet and existing AWS_DevOps_Agent_Role
# ==============================================================================

STACK_NAME="${STACK_NAME:-da-auto-investigation}"
REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo 'us-east-1')}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.medium}"
WEBHOOK_URL="${DEVOPS_AGENT_WEBHOOK_URL:-https://placeholder.aidevops.amazonaws.com/webhook/v1/incident}"
WEBHOOK_SECRET="${DEVOPS_AGENT_WEBHOOK_SECRET:-PLACEHOLDER_WEBHOOK_SECRET_CHANGE_ME}"
AGENT_ROLE_NAME="${DEVOPS_AGENT_ROLE_NAME:-AWS_DevOps_Agent_Role}"
ENABLE_SELF_HEALING="${ENABLE_SELF_HEALING:-true}"
ANOMALY_BAND_WIDTH="${ANOMALY_BAND_WIDTH:-2}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/../cloudformation/da-auto-investigation-stack.yaml"

echo "=================================================================="
echo " Deploying Stack : ${STACK_NAME}"
echo " Region          : ${REGION}"
echo " Instance Type   : ${INSTANCE_TYPE}"
echo " Anomaly Band    : ${ANOMALY_BAND_WIDTH} std devs"
echo "=================================================================="

# 1. Auto-discover VPC if VPC_ID not provided
if [ -z "${VPC_ID:-}" ]; then
  VPC_ID=$(aws ec2 describe-vpcs \
    --region "${REGION}" \
    --filters "Name=is-default,Values=true" \
    --query "Vpcs[0].VpcId" \
    --output text 2>/dev/null || true)

  if [ -z "${VPC_ID}" ] || [ "${VPC_ID}" = "None" ]; then
    VPC_ID=$(aws ec2 describe-vpcs \
      --region "${REGION}" \
      --query "Vpcs[0].VpcId" \
      --output text)
  fi
fi
echo "[+] Using VPC ID    : ${VPC_ID}"

# 2. Auto-discover Subnet in the selected VPC if SUBNET_ID not provided
if [ -z "${SUBNET_ID:-}" ]; then
  SUBNET_ID=$(aws ec2 describe-subnets \
    --region "${REGION}" \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "Subnets[?MapPublicIpOnLaunch==\`true\`]|[0].SubnetId" \
    --output text 2>/dev/null || true)

  if [ -z "${SUBNET_ID}" ] || [ "${SUBNET_ID}" = "None" ]; then
    SUBNET_ID=$(aws ec2 describe-subnets \
      --region "${REGION}" \
      --filters "Name=vpc-id,Values=${VPC_ID}" \
      --query "Subnets[0].SubnetId" \
      --output text)
  fi
fi
echo "[+] Using Subnet ID : ${SUBNET_ID}"

# 3. Check if AWS_DevOps_Agent_Role exists in this account
ATTACH_AGENT_POLICY="false"
if aws iam get-role --role-name "${AGENT_ROLE_NAME}" >/dev/null 2>&1; then
  echo "[+] Found existing DevOps Agent Role '${AGENT_ROLE_NAME}' -> attaching SSM Runbook execution permissions."
  ATTACH_AGENT_POLICY="true"
else
  echo "[i] Role '${AGENT_ROLE_NAME}' not found -> skipping direct role attachment (Bridge Lambda will still trigger SSM Runbook)."
fi

# 4. Deploy CloudFormation stack
aws cloudformation deploy \
  --region "${REGION}" \
  --stack-name "${STACK_NAME}" \
  --template-file "${TEMPLATE_FILE}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    VpcId="${VPC_ID}" \
    SubnetId="${SUBNET_ID}" \
    InstanceType="${INSTANCE_TYPE}" \
    DevOpsAgentWebhookUrl="${WEBHOOK_URL}" \
    DevOpsAgentWebhookSecret="${WEBHOOK_SECRET}" \
    DevOpsAgentRoleName="${AGENT_ROLE_NAME}" \
    AttachRunbookPolicyToAgentRole="${ATTACH_AGENT_POLICY}" \
    EnableAutoSelfHealing="${ENABLE_SELF_HEALING}" \
    AnomalyDetectionBandWidth="${ANOMALY_BAND_WIDTH}"

echo ""
echo "=================================================================="
echo " Deployment Complete! Stack Outputs:"
echo "=================================================================="
aws cloudformation describe-stacks \
  --region "${REGION}" \
  --stack-name "${STACK_NAME}" \
  --query "Stacks[0].Outputs[*].[OutputKey,OutputValue]" \
  --output table
