---
name: infra-test
description: Run distributed infrastructure tests
args: ["[--scope=SCOPE]", "[--verbose]"]
---

# Infrastructure Test

Run distributed infrastructure tests across Kage Bunshin nodes.

## Usage

```bash
/infra-test                           # Run all tests
/infra-test --scope=connectivity      # Test node connectivity only
/infra-test --scope=services          # Test service health only
/infra-test --scope=models            # Test model availability
/infra-test --scope=parallel          # Test parallel execution
/infra-test --verbose                 # Detailed output
```

## Test Scopes

### connectivity

Tests network connectivity between nodes:

```bash
# Test SSH connectivity
for node in ndnlinuxsrv2; do
    echo -n "$node: "
    ssh -o ConnectTimeout=5 $node 'echo OK' 2>/dev/null || echo "FAIL"
done

# Test Tailscale connectivity
tailscale ping 100.95.177.124
```

### services

Tests service health on each node:

```bash
# Local services
curl -sf http://localhost:11434/api/tags && echo "Ollama: OK"
pg_isready && echo "PostgreSQL: OK"

# Remote services
ssh ndnlinuxsrv2 'curl -sf http://localhost:11434/api/tags' && echo "Remote Ollama: OK"
ssh ndnlinuxsrv2 'pg_isready' && echo "Remote PostgreSQL: OK"
```

### models

Tests model availability across nodes:

```bash
# Get models from each node
echo "Local models:"
curl -s http://localhost:11434/api/tags | jq -r '.models[].name'

echo "Remote models (ndnlinuxsrv2):"
ssh ndnlinuxsrv2 'curl -s http://localhost:11434/api/tags' | jq -r '.models[].name'

# Check for model parity
LOCAL=$(curl -s localhost:11434/api/tags | jq -r '.models[].name' | sort)
REMOTE=$(ssh ndnlinuxsrv2 'curl -s localhost:11434/api/tags' | jq -r '.models[].name' | sort)

if [ "$LOCAL" = "$REMOTE" ]; then
    echo "Model parity: OK"
else
    echo "Model parity: MISMATCH"
    diff <(echo "$LOCAL") <(echo "$REMOTE")
fi
```

### parallel

Tests parallel execution capability:

```bash
# Run simple prompt on multiple nodes simultaneously
echo "Testing parallel execution..."

# Start parallel requests
(curl -s http://localhost:11434/api/generate -d '{"model":"qwen2.5:3b","prompt":"Say hello","stream":false}' | jq -r '.response' > /tmp/local_result.txt) &
(ssh ndnlinuxsrv2 'curl -s http://localhost:11434/api/generate -d '\''{"model":"qwen2.5:3b","prompt":"Say hello","stream":false}'\''' | jq -r '.response' > /tmp/remote_result.txt) &

wait

echo "Local result: $(cat /tmp/local_result.txt | head -1)"
echo "Remote result: $(cat /tmp/remote_result.txt | head -1)"
```

## Expected Output

```
Infrastructure Test Report
==========================

Connectivity Tests
------------------
  ndnlinuxsrv2 SSH:      OK (45ms)
  Tailscale ping:        OK (12ms)

Service Tests
-------------
  Local:
    Ollama:              OK
    PostgreSQL:          OK
    KB API:              OK

  ndnlinuxsrv2:
    Ollama:              OK
    PostgreSQL:          OK

Model Tests
-----------
  qwen2.5-coder:32b:     local, ndnlinuxsrv2
  qwen2.5:3b:            local, ndnlinuxsrv2
  deepseek-r1:8b:        local only

  Model parity:          PARTIAL (1 model missing on ndnlinuxsrv2)

Parallel Execution
------------------
  Nodes responding:      2/2
  Parallel speedup:      1.8x

Overall: HEALTHY (12/14 tests passed)
```

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| SSH timeout | Node unreachable | Check Tailscale: `tailscale status` |
| Service not responding | Service down | Restart: `systemctl restart <service>` |
| Model missing | Not pulled | Pull on target: `ssh node 'ollama pull model'` |
| Parallel slow | Resource contention | Check GPU/CPU usage |
