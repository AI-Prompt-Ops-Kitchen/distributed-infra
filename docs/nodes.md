# Kage Bunshin Node Documentation

## 72B Model Capability

The qwen2.5:72b model requires ~45GB RAM. Only nodes with 64GB+ memory can run it:

| Node | RAM | 72B Capable | Speed |
|------|-----|-------------|-------|
| node-gpu-primary | 64GB | Yes | 2.8 tok/s |
| node-gpu-mobile | 64GB unified | Yes | 2.9 tok/s |
| node-primary | 30GB | No | OOM |
| node-secondary | 14GB | No | OOM |

### Parallel 72B Inference

Running qwen2.5:72b simultaneously on both 64GB nodes:

| Node | Tokens | Duration | Speed |
|------|--------|----------|-------|
| node-gpu-mobile | 253 | 90.2s | 2.8 tok/s |
| node-gpu-primary | 259 | 104.7s | 2.4 tok/s |
| **Combined** | **512** | **150s** | **3.4 tok/s** |

Parallel execution yields ~20% better effective throughput than single-node inference.

**Use case**: Distribute 72B queries across both nodes for load balancing and fault tolerance.

### Load Balancer (nginx)

A load balancer runs on node-primary to distribute 72B queries:

```
Endpoint: http://localhost:11435/api/generate
Strategy: least_conn (routes to node with fewest active requests)
Backends: node-gpu-mobile, node-gpu-primary
```

**Usage:**
```bash
# Use port 11435 instead of 11434 for load-balanced 72B inference
curl http://localhost:11435/api/generate -d '{"model":"qwen2.5:72b","prompt":"...","stream":false}'
```

**Config:** `config/ollama-lb.conf`

## Node Inventory

| Node | IP | Role | SSH Port | GPU |
|------|-----|------|----------|-----|
| node-primary | <PRIMARY_IP> | primary | 22 | CPU |
| node-secondary | <SECONDARY_IP> | secondary | 22 | CPU |
| node-gpu-mobile | <GPU_MOBILE_IP> | mobile | 22 | AMD GPU |
| node-gpu-primary | <GPU_PRIMARY_IP> | gpu-primary | 22 | NVIDIA RTX 4090 24GB |

---

## node-gpu-mobile (Mobile Workstation)

- **Hostname**: node-gpu-mobile
- **IP**: <GPU_MOBILE_IP>
- **Role**: GPU-accelerated mobile node

### Hardware
- CPU: AMD Ryzen AI MAX+ 395
- GPU: AMD Radeon (gfx1151)
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

### Setup Commands
```bash
# Add user to render group
sudo usermod -aG render,video $USER

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

## node-secondary (Secondary Server)

- **Hostname**: node-secondary
- **IP**: <SECONDARY_IP>
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

---

## node-primary (Primary Server)

- **Hostname**: node-primary
- **IP**: <PRIMARY_IP>
- **Role**: Primary orchestration node

### Services
- PostgreSQL (primary)
- Ollama
- Load Balancer (nginx)

---

## node-gpu-primary (GPU Primary)

- **Hostname**: node-gpu-primary
- **IP**: <GPU_PRIMARY_IP>
- **OS**: Windows 10
- **Role**: High-performance GPU inference node

### Hardware
- CPU: AMD Ryzen (Gaming)
- GPU: NVIDIA RTX 4090 24GB VRAM
- Memory: 64GB DDR5

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

### SSH Access (Optional)
To enable SSH management from Linux nodes:
1. Enable OpenSSH Server in Windows Settings → Apps → Optional Features
2. Copy public key to `C:\Users\<username>\.ssh\authorized_keys`

### Performance
| Model | Speed | Notes |
|-------|-------|-------|
| qwen2.5:32b | 48.3 tok/s | Fits in 24GB VRAM |
| deepseek-r1:32b | 49.0 tok/s | Fits in 24GB VRAM |
| qwen2.5:72b | 2.8 tok/s | Requires RAM offload (45GB model) |

**Note**: 32B models are the sweet spot for RTX 4090 - they fit entirely in VRAM and deliver ~50 tok/s.
