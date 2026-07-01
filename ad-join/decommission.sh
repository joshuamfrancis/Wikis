#!/usr/bin/env bash
# ============================================================
# decommission-ad-lab.sh
# Tears down every resource created by deploy-ad-lab.sh,
# in dependency-safe order, using IDs stored in variables.env.
#
# Usage:
#   ./decommission-ad-lab.sh [path/to/variables.env]
# ============================================================
set -uo pipefail   # no -e: continue best-effort even if a resource is already gone
export MSYS_NO_PATHCONV=1

ENV_FILE="${1:-$(dirname "$0")/variables.env}"
[[ -f "$ENV_FILE" ]] || { echo "ERROR: env file not found: $ENV_FILE"; exit 1; }

# shellcheck source=/dev/null
source "$ENV_FILE"

if [[ -z "${VPC_A:-}" ]]; then
  echo "ERROR: No deployed resource IDs found in $ENV_FILE. Nothing to decommission."
  exit 1
fi

log()  { echo -e "\n[$(date +%H:%M:%S)] $*"; }
try()  { "$@" >/dev/null 2>&1 && echo "  ok: $*" || echo "  skip (already gone/failed): $*"; }

echo "============================================================"
echo " This will DELETE the following resources:"
echo "   Instances : ${DC_INSTANCE:-n/a}, ${MEMBER_INSTANCE:-n/a}"
echo "   Resolver  : ${OUT_EP:-n/a} ${IN_EP:-}, rule ${RULE_ID:-n/a}"
echo "   Peering   : ${PEER_ID:-n/a}"
echo "   VPCs      : ${VPC_A:-n/a}, ${VPC_B:-n/a} (+ subnets, SGs, IGWs)"
echo "============================================================"
read -r -p "Type 'yes' to proceed: " CONFIRM
[[ "$CONFIRM" == "yes" ]] || { echo "Aborted."; exit 0; }

# ------------------------------------------------------------
log "1/7 Terminating EC2 instances"
# ------------------------------------------------------------
INSTANCES=""
[[ -n "${DC_INSTANCE:-}" ]]     && INSTANCES="$INSTANCES $DC_INSTANCE"
[[ -n "${MEMBER_INSTANCE:-}" ]] && INSTANCES="$INSTANCES $MEMBER_INSTANCE"
if [[ -n "$INSTANCES" ]]; then
  # shellcheck disable=SC2086
  try aws ec2 terminate-instances --instance-ids $INSTANCES
  log "Waiting for instances to terminate (frees ENIs/SGs)..."
  # shellcheck disable=SC2086
  aws ec2 wait instance-terminated --instance-ids $INSTANCES 2>/dev/null || true
fi

# ------------------------------------------------------------
log "2/7 Route 53 Resolver rule + endpoints"
# ------------------------------------------------------------
if [[ -n "${RULE_ID:-}" ]]; then
  try aws route53resolver disassociate-resolver-rule --vpc-id "$VPC_B" --resolver-rule-id "$RULE_ID"
  # wait for disassociation before delete
  for _ in {1..15}; do
    N=$(aws route53resolver list-resolver-rule-associations \
      --filters Name=ResolverRuleId,Values="$RULE_ID" \
      --query 'length(ResolverRuleAssociations)' --output text 2>/dev/null || echo 0)
    [[ "$N" == "0" ]] && break
    sleep 10
  done
  try aws route53resolver delete-resolver-rule --resolver-rule-id "$RULE_ID"
fi

for EP in "${OUT_EP:-}" "${IN_EP:-}"; do
  [[ -n "$EP" ]] && try aws route53resolver delete-resolver-endpoint --resolver-endpoint-id "$EP"
done

if [[ -n "${OUT_EP:-}" ]]; then
  log "Waiting for resolver endpoint deletion (frees ENIs)..."
  for _ in {1..20}; do
    aws route53resolver get-resolver-endpoint --resolver-endpoint-id "$OUT_EP" >/dev/null 2>&1 || break
    sleep 15
  done
fi

# ------------------------------------------------------------
log "3/7 VPC peering connection"
# ------------------------------------------------------------
[[ -n "${PEER_ID:-}" ]] && try aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id "$PEER_ID"

# ------------------------------------------------------------
log "4/7 Security groups"
# ------------------------------------------------------------
for SG in "${SG_DC:-}" "${SG_MEMBER:-}" "${SG_RESOLVER:-}"; do
  [[ -n "$SG" ]] && try aws ec2 delete-security-group --group-id "$SG"
done

# ------------------------------------------------------------
log "5/7 Subnets"
# ------------------------------------------------------------
for SN in "${SUBNET_A:-}" "${SUBNET_A2:-}" "${SUBNET_B1:-}" "${SUBNET_B2:-}"; do
  [[ -n "$SN" ]] && try aws ec2 delete-subnet --subnet-id "$SN"
done

# ------------------------------------------------------------
log "6/7 Internet gateways"
# ------------------------------------------------------------
if [[ -n "${IGW_A:-}" ]]; then
  try aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_A" --vpc-id "$VPC_A"
  try aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_A"
fi
if [[ -n "${IGW_B:-}" ]]; then
  try aws ec2 detach-internet-gateway --internet-gateway-id "$IGW_B" --vpc-id "$VPC_B"
  try aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_B"
fi

# ------------------------------------------------------------
log "7/7 VPCs (main route tables delete with the VPC)"
# ------------------------------------------------------------
for V in "${VPC_A:-}" "${VPC_B:-}"; do
  [[ -n "$V" ]] && try aws ec2 delete-vpc --vpc-id "$V"
done

# Key pair - only if this script's deploy created it
if [[ "${KEY_CREATED_BY_SCRIPT:-false}" == "true" ]]; then
  try aws ec2 delete-key-pair --key-name "$KEY_NAME"
  rm -f "$HOME/${KEY_NAME}.pem"
fi

# ------------------------------------------------------------
# Reset variables.env: strip runtime state, keep user config
# ------------------------------------------------------------
sed -i.bak '/^# === DEPLOYED_RESOURCES_BELOW ===$/q' "$ENV_FILE"
log "Runtime state cleared from $ENV_FILE (backup: ${ENV_FILE}.bak)"

echo ""
echo "============================================================"
echo " DECOMMISSION COMPLETE"
echo " Verify no leftovers with:"
echo "   aws resourcegroupstaggingapi get-resources --tag-filters Key=Lab,Values=ad-lab"
echo "============================================================"
