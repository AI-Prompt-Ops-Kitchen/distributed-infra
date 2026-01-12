#!/bin/bash
# test.sh - Kage Bunshin infrastructure test script
# Usage: ./test.sh [--scope=SCOPE] [--verbose]

# Don't exit on error - we handle failures in report()
set +e

SCOPE="all"
VERBOSE=""

# Parse arguments
for arg in "$@"; do
    case $arg in
        --scope=*)
            SCOPE="${arg#*=}"
            ;;
        --verbose)
            VERBOSE="1"
            ;;
    esac
done

PASS=0
FAIL=0
SKIP=0

report() {
    local status=$1
    local test=$2
    local detail=$3

    case $status in
        PASS)
            echo "   ✓ $test"
            [ -n "$VERBOSE" ] && [ -n "$detail" ] && echo "     $detail"
            ((PASS++))
            ;;
        FAIL)
            echo "   ✗ $test"
            [ -n "$detail" ] && echo "     $detail"
            ((FAIL++))
            ;;
        SKIP)
            echo "   ○ $test (skipped)"
            [ -n "$detail" ] && echo "     $detail"
            ((SKIP++))
            ;;
    esac
}

echo "╔════════════════════════════════════════╗"
echo "║   Kage Bunshin Infrastructure Test     ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "Scope: $SCOPE"
echo ""

# Get nodes from database
NODES=$(psql -d claude_memory -t -A -c "SELECT hostname FROM kage_bunshin.node_inventory WHERE is_active = true AND hostname != 'localhost'")

test_connectivity() {
    echo "🔗 Connectivity Tests"
    echo "─────────────────────"

    # Test SSH to each node
    for node in $NODES; do
        START=$(date +%s%N)
        if ssh -o ConnectTimeout=5 -o BatchMode=yes $node 'echo OK' > /dev/null 2>&1; then
            END=$(date +%s%N)
            MS=$(( (END - START) / 1000000 ))
            report PASS "SSH to $node" "${MS}ms"

            # Update last_seen
            psql -d claude_memory -q -c "UPDATE kage_bunshin.node_inventory SET last_seen = NOW() WHERE hostname = '$node'"
        else
            report FAIL "SSH to $node" "Connection failed"
        fi
    done

    # Test Tailscale
    for node in $NODES; do
        IP=$(psql -d claude_memory -t -A -c "SELECT tailscale_ip FROM kage_bunshin.node_inventory WHERE hostname = '$node'")
        if [ -n "$IP" ]; then
            if tailscale ping -c 1 $IP > /dev/null 2>&1; then
                report PASS "Tailscale to $node ($IP)"
            else
                report FAIL "Tailscale to $node ($IP)" "Ping failed"
            fi
        fi
    done

    echo ""
}

test_services() {
    echo "🔧 Service Tests"
    echo "────────────────"

    # Local services
    echo "   Local:"
    if curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; then
        report PASS "Ollama"
    else
        report FAIL "Ollama" "Not responding on port 11434"
    fi

    if pg_isready -q 2>/dev/null; then
        report PASS "PostgreSQL"
    else
        report FAIL "PostgreSQL" "Not ready"
    fi

    if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
        report PASS "KB API"
    else
        report SKIP "KB API" "Not running (optional)"
    fi

    # Remote services
    for node in $NODES; do
        echo "   $node:"

        if ssh -o ConnectTimeout=5 $node 'curl -sf http://localhost:11434/api/tags' > /dev/null 2>&1; then
            report PASS "Ollama"
        else
            report FAIL "Ollama" "Not responding"
        fi

        if ssh -o ConnectTimeout=5 $node 'pg_isready -q' 2>/dev/null; then
            report PASS "PostgreSQL"
        else
            report FAIL "PostgreSQL" "Not ready"
        fi
    done

    echo ""
}

test_models() {
    echo "🤖 Model Tests"
    echo "──────────────"

    LOCAL_MODELS=$(curl -s http://localhost:11434/api/tags | jq -r '.models[].name' | sort)
    echo "   Local models: $(echo "$LOCAL_MODELS" | wc -l)"

    for node in $NODES; do
        REMOTE_MODELS=$(ssh $node 'curl -s http://localhost:11434/api/tags' 2>/dev/null | jq -r '.models[].name' | sort)
        echo "   $node models: $(echo "$REMOTE_MODELS" | wc -l)"

        # Check parity
        MISSING=$(comm -23 <(echo "$LOCAL_MODELS") <(echo "$REMOTE_MODELS"))
        if [ -z "$MISSING" ]; then
            report PASS "Model parity with $node"
        else
            report FAIL "Model parity with $node" "Missing: $MISSING"
        fi
    done

    echo ""
}

test_parallel() {
    echo "⚡ Parallel Execution Tests"
    echo "───────────────────────────"

    # Simple parallel test
    echo "   Running parallel requests..."

    START=$(date +%s%N)

    # Run on local and all remote nodes in parallel
    curl -s http://localhost:11434/api/generate -d '{"model":"qwen2.5:3b","prompt":"Say hi","stream":false}' > /tmp/parallel_local.json 2>&1 &
    LOCAL_PID=$!

    PIDS=($LOCAL_PID)
    for node in $NODES; do
        ssh $node 'curl -s http://localhost:11434/api/generate -d '\''{"model":"qwen2.5:3b","prompt":"Say hi","stream":false}'\''' > /tmp/parallel_${node}.json 2>&1 &
        PIDS+=($!)
    done

    # Wait for all
    SUCCESS=0
    for pid in "${PIDS[@]}"; do
        if wait $pid; then
            ((SUCCESS++))
        fi
    done

    END=$(date +%s%N)
    MS=$(( (END - START) / 1000000 ))

    if [ $SUCCESS -eq ${#PIDS[@]} ]; then
        report PASS "Parallel execution" "${#PIDS[@]} nodes responded in ${MS}ms"
    else
        report FAIL "Parallel execution" "$SUCCESS/${#PIDS[@]} nodes responded"
    fi

    echo ""
}

# Run tests based on scope
case $SCOPE in
    connectivity)
        test_connectivity
        ;;
    services)
        test_services
        ;;
    models)
        test_models
        ;;
    parallel)
        test_parallel
        ;;
    all)
        test_connectivity
        test_services
        test_models
        test_parallel
        ;;
    *)
        echo "Unknown scope: $SCOPE"
        echo "Usage: $0 [--scope=connectivity|services|models|parallel|all]"
        exit 1
        ;;
esac

# Summary
echo "════════════════════════════════════════"
TOTAL=$((PASS + FAIL + SKIP))
echo "Summary: $PASS passed, $FAIL failed, $SKIP skipped (total: $TOTAL)"

if [ $FAIL -eq 0 ]; then
    echo "Status: ✓ HEALTHY"
    exit 0
else
    echo "Status: ✗ DEGRADED"
    exit 1
fi
