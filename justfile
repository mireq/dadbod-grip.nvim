# dadbod-grip.nvim

src := "~/.config/nvim/lua/dadbod-grip"
dest := "lua/dadbod-grip"

# Show current version
version:
    @grep '_version' {{src}}/init.lua | head -1 | sed 's/.*"\(.*\)".*/\1/'

# Bump version, commit, tag, push, create GitHub release
release bump:
    #!/usr/bin/env bash
    set -euo pipefail
    current=$(grep '_version' {{src}}/init.lua | head -1 | sed 's/.*"\(.*\)".*/\1/')
    IFS='.' read -r major minor patch <<< "$current"
    case "{{bump}}" in
        patch) patch=$((patch + 1)) ;;
        minor) minor=$((minor + 1)); patch=0 ;;
        major) major=$((major + 1)); minor=0; patch=0 ;;
        *) echo "Usage: just release patch|minor|major"; exit 1 ;;
    esac
    new="${major}.${minor}.${patch}"
    echo "Bumping $current -> $new"
    sed -i '' "s/M._version = \"$current\"/M._version = \"$new\"/" {{src}}/init.lua
    just sync
    git add -A
    git commit -m "release v${new}"
    git tag -a "v${new}" -m "v${new}"
    git push origin main --tags
    gh release create "v${new}" --title "v${new}" --generate-notes

# Sync lua files from nvim config to repo
sync:
    #!/usr/bin/env bash
    set -euo pipefail
    rsync -av --delete \
        --exclude='test/' \
        {{src}}/ {{dest}}/
    echo "Synced {{src}} -> {{dest}}"
