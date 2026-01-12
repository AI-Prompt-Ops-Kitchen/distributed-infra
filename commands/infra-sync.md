---
name: infra-sync
description: Sync infrastructure between distributed nodes
args: ["<action>", "[--target=NODE]", "[--dry-run]"]
---

# Infrastructure Sync

Sync code, configuration, or database between Kage Bunshin nodes.

## Usage

```bash
/infra-sync full                      # Full sync to all nodes
/infra-sync full --target=ndnlinuxsrv2  # Sync to specific node
/infra-sync code                      # Sync code/repo only
/infra-sync config                    # Sync config files only
/infra-sync db                        # Sync PostgreSQL database
/infra-sync verify                    # Verify sync without changes
/infra-sync full --dry-run            # Show what would sync
```

## Actions

| Action | What It Syncs | Method |
|--------|---------------|--------|
| `full` | Everything | All below |
| `code` | Kage Bunshin repo | rsync |
| `config` | Config files, env | rsync |
| `db` | PostgreSQL | pg_dump/restore |
| `models` | Ollama models | ollama pull |
| `verify` | Nothing (check only) | diff |

## Workflow

Execute the sync based on the action requested. Use the scripts in the plugin's scripts directory.

### For code sync:

```bash
rsync -avz --delete \
    --exclude '.git' \
    --exclude 'venv' \
    --exclude '__pycache__' \
    --exclude '*.pyc' \
    ~/projects/kage-bunshin/ \
    ${TARGET}:~/projects/kage-bunshin/
```

### For db sync:

```bash
# Dump from local
pg_dump -Fc claude_memory > /tmp/claude_memory_sync.dump

# Copy to remote
scp /tmp/claude_memory_sync.dump ${TARGET}:/tmp/

# Restore on remote
ssh ${TARGET} 'pg_restore -c -d claude_memory /tmp/claude_memory_sync.dump 2>/dev/null || true'

# Cleanup
rm /tmp/claude_memory_sync.dump
ssh ${TARGET} 'rm /tmp/claude_memory_sync.dump'
```

### For verify:

```bash
# Compare file counts
diff <(find ~/projects/kage-bunshin -name "*.py" -type f | wc -l) \
     <(ssh ${TARGET} "find ~/projects/kage-bunshin -name '*.py' -type f | wc -l")

# Compare model lists
diff <(curl -s localhost:11434/api/tags | jq -r '.models[].name' | sort) \
     <(ssh ${TARGET} 'curl -s localhost:11434/api/tags' | jq -r '.models[].name' | sort)
```

## Node Inventory

Default targets from `kage_bunshin.node_inventory`:

| Node | Address | Role |
|------|---------|------|
| ndnlinuxsrv2 | ndnlinuxsrv2 | Secondary |

## Credentials

SSH keys are retrieved from `kage_bunshin.secrets`:

```sql
SELECT pgp_sym_decrypt(encrypted_value, 'KEY')
FROM kage_bunshin.secrets
WHERE name = 'ssh-key-ndnlinuxsrv2';
```
