---
name: infra-nodes
description: List and manage node inventory
args: ["[list|add|remove|status]", "[--node=NAME]"]
---

# Infrastructure Nodes

Manage the Kage Bunshin distributed node inventory.

## Usage

```bash
/infra-nodes                          # List all nodes
/infra-nodes list                     # List all nodes (same as above)
/infra-nodes status                   # Show node health status
/infra-nodes add --node=newnode       # Add a new node (interactive)
/infra-nodes remove --node=nodename   # Remove a node
```

## Node Inventory

The node inventory is stored in `kage_bunshin.node_inventory`:

```sql
-- View all nodes
SELECT * FROM kage_bunshin.node_inventory WHERE is_active = true;

-- Example output:
-- name          | hostname       | tailscale_ip     | role      | services
-- ndnlinuxsrv1  | localhost      | 100.77.248.9     | primary   | postgres,ollama,kb-api
-- ndnlinuxsrv2  | ndnlinuxsrv2   | 100.95.177.124   | secondary | postgres,ollama
```

## Actions

### list

Display all registered nodes:

```bash
psql -d claude_memory -c "
SELECT
    name,
    hostname,
    tailscale_ip,
    role,
    services,
    last_seen
FROM kage_bunshin.node_inventory
WHERE is_active = true
ORDER BY role, name;
"
```

### status

Check health of each node:

```bash
for row in $(psql -d claude_memory -t -c "SELECT hostname FROM kage_bunshin.node_inventory WHERE is_active = true"); do
    node=$(echo $row | xargs)
    echo -n "$node: "

    if [ "$node" = "localhost" ]; then
        echo "OK (local)"
    elif ssh -o ConnectTimeout=5 $node 'echo OK' 2>/dev/null; then
        # Update last_seen
        psql -d claude_memory -c "UPDATE kage_bunshin.node_inventory SET last_seen = NOW() WHERE hostname = '$node'"
    else
        echo "UNREACHABLE"
    fi
done
```

### add

Add a new node (requires SSH access and Tailscale IP):

```sql
INSERT INTO kage_bunshin.node_inventory
(name, hostname, tailscale_ip, role, services)
VALUES
('newnode', 'newnode.tailnet', '100.x.x.x', 'worker', ARRAY['ollama']);
```

### remove

Remove a node (soft delete):

```sql
UPDATE kage_bunshin.node_inventory
SET is_active = false
WHERE name = 'nodename';
```

## Database Schema

Create the node inventory table if it doesn't exist:

```sql
CREATE TABLE IF NOT EXISTS kage_bunshin.node_inventory (
    id SERIAL PRIMARY KEY,
    name VARCHAR(64) NOT NULL UNIQUE,
    hostname VARCHAR(255) NOT NULL,
    tailscale_ip INET,
    role VARCHAR(32) DEFAULT 'worker',
    services TEXT[] DEFAULT '{}',
    ssh_key_secret VARCHAR(64),  -- Reference to kage_bunshin.secrets
    last_seen TIMESTAMPTZ,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Default nodes
INSERT INTO kage_bunshin.node_inventory (name, hostname, tailscale_ip, role, services)
VALUES
    ('ndnlinuxsrv1', 'localhost', '100.77.248.9', 'primary', ARRAY['postgres', 'ollama', 'kb-api']),
    ('ndnlinuxsrv2', 'ndnlinuxsrv2', '100.95.177.124', 'secondary', ARRAY['postgres', 'ollama'])
ON CONFLICT (name) DO NOTHING;
```

## Expected Output

```
Kage Bunshin Node Inventory
===========================

Name          Hostname       Tailscale IP      Role       Services              Last Seen
----          --------       ------------      ----       --------              ---------
ndnlinuxsrv1  localhost      100.77.248.9      primary    postgres,ollama,kb-api  now
ndnlinuxsrv2  ndnlinuxsrv2   100.95.177.124    secondary  postgres,ollama         2 min ago

Total: 2 active nodes
```
