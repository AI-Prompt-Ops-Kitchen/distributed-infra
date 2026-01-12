# Kage Bunshin Node Documentation

## 72B Model Capability

The qwen2.5:72b model requires ~45GB RAM. Only nodes with 64GB+ memory can run it:

| Node | RAM | 72B Capable | Speed |
|------|-----|-------------|-------|
| vengeance | 64GB | Yes | 2.8 tok/s |
| rog-flow-z13 | 64GB unified | Yes | 2.9 tok/s |
| ndnlinuxsrv1 | 30GB | No | OOM |
| ndnlinuxsrv2 | 14GB | No | OOM |

### Parallel 72B Inference (Benchmarked 2026-01-11)

Running qwen2.5:72b simultaneously on both 64GB nodes:

| Node | Tokens | Duration | Speed |
|------|--------|----------|-------|
| ROG Flow Z13 | 253 | 90.2s | 2.8 tok/s |
| Vengeance | 259 | 104.7s | 2.4 tok/s |
| **Combined** | **512** | **150s** | **3.4 tok/s** |

Parallel execution yields ~20% better effective throughput than single-node inference.

**Use case**: Distribute 72B queries across both nodes for load balancing and fault tolerance.

### Load Balancer (nginx)

A load balancer runs on ndnlinuxsrv1 to distribute 72B queries:

```
Endpoint: http://localhost:11435/api/generate
Strategy: least_conn (routes to node with fewest active requests)
Backends: ROG Flow Z13, Vengeance
```

**Usage:**
```bash
# Use port 11435 instead of 11434 for load-balanced 72B inference
curl http://localhost:11435/api/generate -d '{"model":"qwen2.5:72b","prompt":"...","stream":false}'
```

**Config:** `/home/ndninja/.claude/plugins/local/distributed-infra/config/ollama-lb.conf`

## Node Inventory

| Node | IP | Role | SSH Port | GPU |
|------|-----|------|----------|-----|
| ndnlinuxsrv1 | 100.77.248.9 | primary | 22 | CPU |
| ndnlinuxsrv2 | 100.113.166.1 | secondary | 22 | CPU |
| rog-flow-z13 | 100.93.122.109 | mobile | 2222 | Radeon 8060S |
| vengeance | 100.98.226.75 | gpu-primary | 22 | RTX 4090 24GB |

---

## ROG Flow Z13 (Mobile Workstation)

- **Hostname**: rog-flow-z13
- **Tailscale IP**: 100.93.122.109
- **SSH Port**: 2222
- **Role**: GPU-accelerated mobile node

### Hardware
- CPU: AMD Ryzen AI MAX+ 395
- GPU: Radeon 8060S (gfx1151)
- Memory: 64GB unified (configurable OS/GPU split)

### ROCm Configuration
GPU acceleration and remote access enabled via systemd overrides:
```
/etc/systemd/system/ollama.service.d/rocm.conf
[Service]
Environment="HSA_OVERRIDE_GFX_VERSION=11.5.1"

/etc/systemd/system/ollama.service.d/network.conf
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
```

### Performance
| Model | Speed | Notes |
|-------|-------|-------|
| qwen2.5:3b | 73 tok/s | GPU accelerated |
| qwen2.5-coder:32b | 10 tok/s | GPU + unified memory |
| qwen2.5:72b | 2.9 tok/s | Unified memory offload |

### Models
- qwen2.5:3b
- qwen2.5-coder:32b
- qwen2.5:72b

### Setup Commands
```bash
# Add user to render group
sudo usermod -aG render,video ndninja

# Install ROCm
sudo apt install rocm-smi-lib rocminfo

# Configure Ollama for ROCm
sudo mkdir -p /etc/systemd/system/ollama.service.d
echo '[Service]
Environment="HSA_OVERRIDE_GFX_VERSION=11.5.1"' | sudo tee /etc/systemd/system/ollama.service.d/rocm.conf
sudo systemctl daemon-reload
sudo systemctl restart ollama
```

---

## ndnlinuxsrv2 (Secondary Server)

- **Hostname**: ndnlinuxsrv2
- **Tailscale IP**: 100.113.166.1
- **SSH Port**: 22
- **Role**: CPU-only secondary node

### Services
- PostgreSQL (synced from primary)
- Ollama (CPU inference)

### Configuration
Remote access enabled via systemd override:
```
/etc/systemd/system/ollama.service.d/network.conf
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
```

### Models
- qwen2.5:3b
- qwen2.5-coder:1.5b

---

## ndnlinuxsrv1 (Primary Server)

- **Hostname**: localhost / ndnlinuxsrv1
- **Tailscale IP**: 100.77.248.9
- **SSH Port**: 22
- **Role**: Primary orchestration node

### Services
- PostgreSQL (primary)
- Ollama
- KB API (optional)

### Models
- qwen2.5:3b
- qwen2.5-coder:32b
- deepseek-coder:33b
- deepseek-r1:14b
- mistral:latest
- qwen2.5:72b (pulled but OOM - needs 45GB, only 30GB available)

---

## Vengeance (Gaming Rig / GPU Primary)

- **Hostname**: vengeance
- **Tailscale IP**: 100.98.226.75
- **SSH Port**: 22
- **OS**: Windows 10
- **Role**: High-performance GPU inference node

### Hardware
- CPU: AMD Ryzen (Gaming)
- GPU: NVIDIA RTX 4090 24GB VRAM
- Memory: 64GB DDR5

### Models
- qwen2.5:3b
- qwen2.5:32b
- deepseek-r1:32b
- deepseek-coder:33b
- qwen2.5:72b

### Configuration Required
Ollama binds to localhost by default. To enable remote access:

**PowerShell (as Administrator):**
```powershell
# Set Ollama to listen on all interfaces
[Environment]::SetEnvironmentVariable("OLLAMA_HOST", "0.0.0.0:11434", "Machine")

# Restart Ollama service
Stop-Process -Name "ollama" -Force
Start-Process "ollama" -ArgumentList "serve"
```

**Or via Windows Services:**
1. Open Services (services.msc)
2. Find "Ollama" service
3. Stop, then Start

### SSH Access (Optional)
To enable SSH management from Linux nodes:
1. Enable OpenSSH Server in Windows Settings → Apps → Optional Features
2. Copy public key to `C:\Users\ndninja\.ssh\authorized_keys`

### Performance (Benchmarked 2026-01-11)
| Model | Speed | Notes |
|-------|-------|-------|
| qwen2.5:32b | 48.3 tok/s | Fits in 24GB VRAM |
| deepseek-r1:32b | 49.0 tok/s | Fits in 24GB VRAM |
| qwen2.5:72b | 2.8 tok/s | Requires RAM offload (45GB model) |

**Note**: 32B models are the sweet spot for RTX 4090 - they fit entirely in VRAM and deliver ~50 tok/s.
