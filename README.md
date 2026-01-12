# Distributed Infrastructure for Kage Bunshin

Distributed AI infrastructure plugin for the [Kage Bunshin](https://github.com/AI-Prompt-Ops-Kitchen/kage-bunshin-plugin) distributed AI system. Provides load balancing, cluster management, and node orchestration for multi-node Ollama inference.

## Features

- **Load Balancer** - nginx-based distribution of 72B model queries across GPU nodes
- **Cluster Monitoring** - Real-time status of all nodes with health checks
- **Failover Support** - Automatic routing around failed nodes
- **Claude Code Integration** - Skills and commands for infrastructure management

## Architecture

```
                    ┌─────────────────┐
                    │  Load Balancer  │
                    │  (nginx:11435)  │
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
    ┌─────────▼─────────┐       ┌──────────▼──────────┐
    │  node-gpu-mobile  │       │   node-gpu-primary  │
    │     AMD GPU       │       │    NVIDIA RTX 4090  │
    │  64GB Unified     │       │    64GB DDR5        │
    │  2.9 tok/s (72B)  │       │    2.8 tok/s (72B)  │
    └───────────────────┘       └─────────────────────┘
```

## Node Inventory

| Node | Role | GPU | RAM | 72B Capable |
|------|------|-----|-----|-------------|
| node-primary | Primary/Orchestrator | CPU | 30GB | No |
| node-secondary | Secondary | CPU | 14GB | No |
| node-gpu-mobile | GPU Mobile | AMD Radeon | 64GB | Yes |
| node-gpu-primary | GPU Primary | RTX 4090 | 64GB | Yes |

## Quick Start

### 1. Install nginx (on orchestrator node)

```bash
sudo apt install nginx
```

### 2. Deploy load balancer config

```bash
# Update the IPs in config/ollama-lb.conf first!
sudo cp config/ollama-lb.conf /etc/nginx/sites-available/ollama-lb
sudo ln -s /etc/nginx/sites-available/ollama-lb /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

### 3. Verify cluster status

```bash
# Update the IPs in scripts/cluster-status.sh first!
./scripts/cluster-status.sh
```

## Configuration

Before using, update the placeholder IPs in these files:

| File | Placeholders to Replace |
|------|------------------------|
| `config/ollama-lb.conf` | `<GPU_MOBILE_IP>`, `<GPU_PRIMARY_IP>` |
| `scripts/cluster-status.sh` | `<SECONDARY_IP>`, `<GPU_MOBILE_IP>`, `<GPU_PRIMARY_IP>` |

## Load Balancer

The nginx load balancer runs on port `11435` and distributes requests across GPU-capable nodes.

### Endpoints

| Endpoint | Description |
|----------|-------------|
| `POST /api/generate` | Load-balanced inference (72B models) |
| `GET /health` | Load balancer health check |
| `GET /backends` | List backend nodes |
| `GET /health/gpu-mobile` | GPU mobile node health |
| `GET /health/gpu-primary` | GPU primary node health |

### Usage

```bash
# Use port 11435 for load-balanced 72B inference
curl http://localhost:11435/api/generate \
  -d '{"model":"qwen2.5:72b","prompt":"Hello","stream":false}'

# Check backend health
curl http://localhost:11435/health/gpu-mobile
curl http://localhost:11435/health/gpu-primary
```

### Strategy

- **Algorithm**: `least_conn` (routes to node with fewest active requests)
- **Health Checks**: Passive (max_fails=2, fail_timeout=30s)
- **Failover**: Automatic via `proxy_next_upstream`

## Cluster Status Script

Monitor all nodes with a single command:

```bash
# Human-readable output
./scripts/cluster-status.sh

# JSON output (for automation)
./scripts/cluster-status.sh --json
```

### Sample Output

```
=== Kage Bunshin Cluster Status ===

NODES:
  node-primary      ✓ ONLINE   (localhost)
  node-secondary    ✓ ONLINE   (CPU)
  node-gpu-mobile   ✓ ONLINE   (GPU: AMD Radeon)
  node-gpu-primary  ✓ ONLINE   (GPU: RTX 4090)

LOAD BALANCER:   ✓ ONLINE (port 11435)
72B INFERENCE:   ✓ AVAILABLE (2 GPU nodes)

CLUSTER STATUS:  HEALTHY (4/4 nodes online)
```

## Performance Benchmarks

### Single Node (72B)

| Node | Model | Speed |
|------|-------|-------|
| node-gpu-primary | qwen2.5:72b | 2.8 tok/s |
| node-gpu-mobile | qwen2.5:72b | 2.9 tok/s |

### Parallel Inference (72B)

Running qwen2.5:72b simultaneously on both GPU nodes:

| Metric | Value |
|--------|-------|
| Combined throughput | 3.4 tok/s |
| Improvement | ~20% over single node |

### 32B Models (node-gpu-primary - fits in VRAM)

| Model | Speed |
|-------|-------|
| qwen2.5:32b | 48.3 tok/s |
| deepseek-r1:32b | 49.0 tok/s |

## Node Configuration

### Enable Remote Ollama Access

Ollama binds to localhost by default. Enable network access:

**Linux (systemd):**
```bash
sudo mkdir -p /etc/systemd/system/ollama.service.d
echo '[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"' | sudo tee /etc/systemd/system/ollama.service.d/network.conf
sudo systemctl daemon-reload
sudo systemctl restart ollama
```

**Windows (PowerShell as Admin):**
```powershell
[Environment]::SetEnvironmentVariable("OLLAMA_HOST", "0.0.0.0:11434", "Machine")
# Restart Ollama
```

### ROCm for AMD GPUs

```bash
# Add systemd override for your GPU version
echo '[Service]
Environment="HSA_OVERRIDE_GFX_VERSION=11.5.1"' | sudo tee /etc/systemd/system/ollama.service.d/rocm.conf
sudo systemctl daemon-reload
sudo systemctl restart ollama
```

## Claude Code Plugin

This repository is a Claude Code plugin. Install it to get infrastructure management commands.

### Commands

- `/infra-nodes` - Display node inventory
- `/infra-sync` - Sync configuration across nodes
- `/infra-test` - Test cluster connectivity

### Skills

- `infra-overview` - Infrastructure documentation and status

## File Structure

```
distributed-infra/
├── config/
│   └── ollama-lb.conf      # nginx load balancer config
├── scripts/
│   ├── cluster-status.sh   # Cluster monitoring script
│   ├── sync.sh             # Configuration sync
│   └── test.sh             # Connectivity tests
├── docs/
│   └── nodes.md            # Detailed node documentation
├── commands/               # Claude Code commands
├── skills/                 # Claude Code skills
└── plugin.json             # Plugin manifest
```

## Related Projects

- [kage-bunshin-plugin](https://github.com/AI-Prompt-Ops-Kitchen/kage-bunshin-plugin) - LLM Council skills and AI logic
- [Ollama](https://ollama.ai) - Local LLM inference engine

## License

MIT

## Author

[AI-Prompt-Ops-Kitchen](https://github.com/AI-Prompt-Ops-Kitchen)
