#!/bin/bash
# sync.sh - Kage Bunshin infrastructure sync script
# Usage: ./sync.sh <action> [--target=NODE] [--dry-run]

set -e

ACTION=${1:-verify}
TARGET=""
DRY_RUN=""

# Parse arguments
for arg in "$@"; do
    case $arg in
        --target=*)
            TARGET="${arg#*=}"
            ;;
        --dry-run)
            DRY_RUN="--dry-run"
            ;;
    esac
done

# Default target if not specified - UPDATE THIS WITH YOUR NODE
if [ -z "$TARGET" ]; then
    TARGET="node-secondary"
fi

KB_DIR=~/projects/kage-bunshin
CLAUDE_DIR=~/.claude

echo "╔════════════════════════════════════════╗"
echo "║     Kage Bunshin Infrastructure Sync   ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "Action:  $ACTION"
echo "Target:  $TARGET"
[ -n "$DRY_RUN" ] && echo "Mode:    DRY RUN (no changes)"
echo ""

sync_code() {
    echo "📦 Syncing code..."
    RSYNC_OPTS="-avz --delete --exclude=.git --exclude=venv --exclude=__pycache__ --exclude=*.pyc --exclude=.pytest_cache"
    [ -n "$DRY_RUN" ] && RSYNC_OPTS="$RSYNC_OPTS --dry-run"

    rsync $RSYNC_OPTS $KB_DIR/ $TARGET:$KB_DIR/
    echo "   ✓ Code synced"
}

sync_config() {
    echo "⚙️  Syncing config..."
    RSYNC_OPTS="-avz"
    [ -n "$DRY_RUN" ] && RSYNC_OPTS="$RSYNC_OPTS --dry-run"

    # Sync .env if exists
    if [ -f "$KB_DIR/.env" ]; then
        rsync $RSYNC_OPTS $KB_DIR/.env $TARGET:$KB_DIR/
    fi

    # Sync skills
    rsync $RSYNC_OPTS $CLAUDE_DIR/skills/ $TARGET:$CLAUDE_DIR/skills/

    echo "   ✓ Config synced"
}

sync_db() {
    echo "🗃️  Syncing database..."
    if [ -n "$DRY_RUN" ]; then
        echo "   Would dump and restore claude_memory database"
        return
    fi

    DUMP_FILE="/tmp/claude_memory_sync_$(date +%s).dump"

    # Dump local
    pg_dump -Fc claude_memory > $DUMP_FILE
    echo "   Dumped to $DUMP_FILE ($(du -h $DUMP_FILE | cut -f1))"

    # Copy to remote
    scp $DUMP_FILE $TARGET:/tmp/
    echo "   Copied to $TARGET"

    # Restore on remote
    ssh $TARGET "pg_restore -c -d claude_memory /tmp/$(basename $DUMP_FILE) 2>/dev/null || true"
    echo "   Restored on $TARGET"

    # Cleanup
    rm $DUMP_FILE
    ssh $TARGET "rm /tmp/$(basename $DUMP_FILE)"
    echo "   ✓ Database synced"
}

sync_models() {
    echo "🤖 Syncing models..."
    LOCAL_MODELS=$(curl -s http://localhost:11434/api/tags | jq -r '.models[].name')

    for model in $LOCAL_MODELS; do
        echo "   Checking $model on $TARGET..."
        if [ -n "$DRY_RUN" ]; then
            echo "   Would pull $model on $TARGET"
        else
            ssh $TARGET "ollama list | grep -q '$model' || ollama pull $model"
        fi
    done
    echo "   ✓ Models synced"
}

verify_sync() {
    echo "🔍 Verifying sync state..."
    echo ""

    # Code files
    echo "Code files:"
    LOCAL_COUNT=$(find $KB_DIR -name "*.py" -type f 2>/dev/null | wc -l)
    REMOTE_COUNT=$(ssh $TARGET "find $KB_DIR -name '*.py' -type f 2>/dev/null | wc -l" 2>/dev/null || echo "0")
    if [ "$LOCAL_COUNT" = "$REMOTE_COUNT" ]; then
        echo "   ✓ Match ($LOCAL_COUNT Python files)"
    else
        echo "   ✗ Mismatch (local: $LOCAL_COUNT, remote: $REMOTE_COUNT)"
    fi

    # Models
    echo ""
    echo "Ollama models:"
    LOCAL_MODELS=$(curl -s localhost:11434/api/tags 2>/dev/null | jq -r '.models[].name' | sort)
    REMOTE_MODELS=$(ssh $TARGET 'curl -s localhost:11434/api/tags 2>/dev/null' | jq -r '.models[].name' | sort 2>/dev/null || echo "")

    if [ "$LOCAL_MODELS" = "$REMOTE_MODELS" ]; then
        echo "   ✓ Models match"
    else
        echo "   ✗ Models differ:"
        echo "   Local only: $(comm -23 <(echo "$LOCAL_MODELS") <(echo "$REMOTE_MODELS") | tr '\n' ' ')"
        echo "   Remote only: $(comm -13 <(echo "$LOCAL_MODELS") <(echo "$REMOTE_MODELS") | tr '\n' ' ')"
    fi

    # PostgreSQL
    echo ""
    echo "PostgreSQL connectivity:"
    if ssh $TARGET "pg_isready -q" 2>/dev/null; then
        echo "   ✓ Remote PostgreSQL reachable"
    else
        echo "   ✗ Remote PostgreSQL unreachable"
    fi
}

case $ACTION in
    code)
        sync_code
        ;;
    config)
        sync_config
        ;;
    db)
        sync_db
        ;;
    models)
        sync_models
        ;;
    verify)
        verify_sync
        ;;
    full)
        sync_code
        sync_config
        sync_db
        sync_models
        verify_sync
        ;;
    *)
        echo "Unknown action: $ACTION"
        echo "Usage: $0 <code|config|db|models|verify|full> [--target=NODE] [--dry-run]"
        exit 1
        ;;
esac

echo ""
echo "════════════════════════════════════════"
echo "Sync complete!"
