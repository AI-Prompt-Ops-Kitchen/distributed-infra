---
name: infra-overview
description: Overview of distributed infrastructure management capabilities
when_to_use: When the user asks about distributed infrastructure, server management, or needs to understand the Kage Bunshin node topology
---

# Distributed Infrastructure Overview

This skill provides context about the Kage Bunshin distributed infrastructure.

## Node Inventory

| Node | Hostname | Tailscale IP | Role | Services |
|------|----------|--------------|------|----------|
| Primary | ndnlinuxsrv1 | 100.77.248.9 | Main orchestrator | PostgreSQL, Ollama, KB API |
| Secondary | ndnlinuxsrv2 | 100.95.177.124 | Worker node | Ollama, PostgreSQL replica |

## Available Commands

- `/infra-sync` - Sync code, config, or database between nodes
- `/infra-test` - Run distributed infrastructure tests
- `/infra-nodes` - List and manage node inventory

## Credentials Integration

Credentials are stored encrypted in `kage_bunshin.secrets` table using pgcrypto.
Use `/kb-secrets` to manage SSH keys, API tokens, and other sensitive data.

## Quick Health Check

```bash
# Check all nodes
/kb-status --verbose

# Check specific node
/kb-status --node=ndnlinuxsrv2
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Tailscale VPN (100.x.x.x)                │
└─────────────────────────────────────────────────────────────┘
           │                                    │
           ▼                                    ▼
┌─────────────────────┐              ┌─────────────────────┐
│   ndnlinuxsrv1      │              │   ndnlinuxsrv2      │
│   (Primary)         │              │   (Secondary)       │
├─────────────────────┤              ├─────────────────────┤
│ • PostgreSQL (main) │◄────────────►│ • PostgreSQL        │
│ • Ollama            │   pg_dump    │ • Ollama            │
│ • Kage Bunshin API  │   rsync      │                     │
│ • Claude Code       │              │                     │
└─────────────────────┘              └─────────────────────┘
```
