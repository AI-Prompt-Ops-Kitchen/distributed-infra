#!/bin/bash
# Kage Bunshin Cluster Status Check
# Usage: ./cluster-status.sh [--json]

set -o pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Nodes configuration - UPDATE THESE WITH YOUR IPs
declare -A NODES=(
    ["node-primary"]="127.0.0.1:11434"
    ["node-secondary"]="<SECONDARY_IP>:11434"
    ["node-gpu-mobile"]="<GPU_MOBILE_IP>:11434"
    ["node-gpu-primary"]="<GPU_PRIMARY_IP>:11434"
)

declare -A NODE_ROLES=(
    ["node-primary"]="primary"
    ["node-secondary"]="secondary"
    ["node-gpu-mobile"]="gpu-mobile"
    ["node-gpu-primary"]="gpu-primary"
)

declare -A NODE_72B=(
    ["node-primary"]="false"
    ["node-secondary"]="false"
    ["node-gpu-mobile"]="true"
    ["node-gpu-primary"]="true"
)

LB_ENDPOINT="http://localhost:11435"

JSON_OUTPUT=false
if [[ "$1" == "--json" ]]; then
    JSON_OUTPUT=true
fi

check_node() {
    local name=$1
    local endpoint=$2
    local timeout=5

    local response
    response=$(curl -s -m $timeout "http://${endpoint}/api/tags" 2>/dev/null)

    if [[ $? -eq 0 ]] && echo "$response" | jq -e '.models' > /dev/null 2>&1; then
        local model_count=$(echo "$response" | jq '.models | length')
        local models=$(echo "$response" | jq -r '.models[].name' | tr '\n' ',' | sed 's/,$//')
        echo "online|$model_count|$models"
    else
        echo "offline|0|"
    fi
}

check_lb() {
    local health=$(curl -s -m 3 "${LB_ENDPOINT}/health" 2>/dev/null)
    if [[ "$health" == "OK" ]]; then
        echo "online"
    else
        echo "offline"
    fi
}

quick_inference_test() {
    local endpoint=$1
    local start=$(date +%s%N)
    local response=$(curl -s -m 30 "http://${endpoint}/api/generate" \
        -d '{"model":"qwen2.5:3b","prompt":"hi","stream":false}' 2>/dev/null)
    local end=$(date +%s%N)

    if echo "$response" | jq -e '.response' > /dev/null 2>&1; then
        local ms=$(( (end - start) / 1000000 ))
        local tokens=$(echo "$response" | jq -r '.eval_count // 0')
        local tps=$(echo "$response" | jq -r '((.eval_count // 0) / ((.eval_duration // 1) / 1000000000)) | . * 10 | floor / 10')
        echo "ok|${ms}|${tokens}|${tps}"
    else
        echo "fail|0|0|0"
    fi
}

if $JSON_OUTPUT; then
    # JSON output mode
    echo "{"
    echo '  "timestamp": "'$(date -Iseconds)'",'
    echo '  "nodes": {'

    first=true
    for name in "${!NODES[@]}"; do
        endpoint=${NODES[$name]}
        result=$(check_node "$name" "$endpoint")
        IFS='|' read -r status model_count models <<< "$result"

        if ! $first; then echo ","; fi
        first=false

        echo -n "    \"$name\": {"
        echo -n "\"status\": \"$status\", "
        echo -n "\"endpoint\": \"$endpoint\", "
        echo -n "\"role\": \"${NODE_ROLES[$name]}\", "
        echo -n "\"72b_capable\": ${NODE_72B[$name]}, "
        echo -n "\"model_count\": $model_count, "
        echo -n "\"models\": \"$models\""
        echo -n "}"
    done

    echo ""
    echo "  },"
    echo '  "load_balancer": {"status": "'$(check_lb)'", "endpoint": "'$LB_ENDPOINT'"}'
    echo "}"
else
    # Human-readable output
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          KAGE BUNSHIN CLUSTER STATUS                         ║${NC}"
    echo -e "${BLUE}║          $(date '+%Y-%m-%d %H:%M:%S')                               ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Check load balancer first
    lb_status=$(check_lb)
    if [[ "$lb_status" == "online" ]]; then
        echo -e "Load Balancer (11435): ${GREEN}ONLINE${NC}"
    else
        echo -e "Load Balancer (11435): ${RED}OFFLINE${NC}"
    fi
    echo ""

    echo -e "${BLUE}┌─────────────────┬──────────┬────────────┬──────┬────────────────────────────┐${NC}"
    echo -e "${BLUE}│ Node            │ Status   │ Role       │ 72B  │ Models                     │${NC}"
    echo -e "${BLUE}├─────────────────┼──────────┼────────────┼──────┼────────────────────────────┤${NC}"

    online_count=0
    total_count=${#NODES[@]}

    for name in node-primary node-secondary node-gpu-mobile node-gpu-primary; do
        endpoint=${NODES[$name]}
        result=$(check_node "$name" "$endpoint")
        IFS='|' read -r status model_count models <<< "$result"

        if [[ "$status" == "online" ]]; then
            status_color="${GREEN}ONLINE${NC}  "
            ((online_count++))
        else
            status_color="${RED}OFFLINE${NC} "
        fi

        role=${NODE_ROLES[$name]}
        is_72b_raw=${NODE_72B[$name]}
        [[ "$is_72b_raw" == "true" ]] && is_72b="yes" || is_72b="no"

        # Truncate models list if too long
        if [[ ${#models} -gt 26 ]]; then
            models="${models:0:23}..."
        fi

        printf "${BLUE}│${NC} %-15s ${BLUE}│${NC} %b ${BLUE}│${NC} %-10s ${BLUE}│${NC} %-4s ${BLUE}│${NC} %-26s ${BLUE}│${NC}\n" \
            "$name" "$status_color" "$role" "$is_72b" "$models"
    done

    echo -e "${BLUE}└─────────────────┴──────────┴────────────┴──────┴────────────────────────────┘${NC}"
    echo ""

    # Summary
    if [[ $online_count -eq $total_count ]]; then
        echo -e "Cluster Health: ${GREEN}HEALTHY${NC} ($online_count/$total_count nodes online)"
    elif [[ $online_count -gt 0 ]]; then
        echo -e "Cluster Health: ${YELLOW}DEGRADED${NC} ($online_count/$total_count nodes online)"
    else
        echo -e "Cluster Health: ${RED}DOWN${NC} (0/$total_count nodes online)"
    fi

    # 72B capability
    gpu_mobile_result=$(check_node "node-gpu-mobile" "${NODES[node-gpu-mobile]}")
    gpu_primary_result=$(check_node "node-gpu-primary" "${NODES[node-gpu-primary]}")

    gpu_mobile_online=false
    gpu_primary_online=false
    [[ "$gpu_mobile_result" == online* ]] && gpu_mobile_online=true
    [[ "$gpu_primary_result" == online* ]] && gpu_primary_online=true

    if $gpu_mobile_online && $gpu_primary_online; then
        echo -e "72B Inference:  ${GREEN}AVAILABLE${NC} (both GPU nodes online)"
    elif $gpu_mobile_online || $gpu_primary_online; then
        echo -e "72B Inference:  ${YELLOW}PARTIAL${NC} (1 GPU node online)"
    else
        echo -e "72B Inference:  ${RED}UNAVAILABLE${NC} (no GPU nodes online)"
    fi

    echo ""
fi
