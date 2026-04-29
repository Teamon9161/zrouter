#!/bin/sh
set -eu

repo="${ZROUTER_INSTALL_REPO:-Teamon9161/zrouter}"
version="${ZROUTER_VERSION:-latest}"
install_dir="${ZROUTER_INSTALL_DIR:-$HOME/.local/bin}"
current_version="${1:-${ZROUTER_CURRENT_VERSION:-}}"
skill_spec="${ZROUTER_SKILL_SPEC:-@Teamon9161/zrouter/skill}"
install_skill="${ZROUTER_INSTALL_SKILL:-auto}"

need_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "missing required command: $1" >&2
        exit 1
    fi
}

download() {
    url="$1"
    out="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fL --progress-bar "$url" -o "$out"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$out" "$url"
    else
        echo "missing required command: curl or wget" >&2
        exit 1
    fi
}

sha256_file() {
    file="$1"

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$file" | awk '{print $1}'
    else
        echo "missing required command: sha256sum or shasum" >&2
        exit 1
    fi
}

print_skill_guidance() {
    echo ""
    echo "To use zrouter from Claude Code, install the zrouter skill:"
    echo "  skill -A $skill_spec --claude"
}

install_zrouter_skill() {
    if ! command -v skill >/dev/null 2>&1; then
        echo "skill CLI not found; skipping zrouter skill installation."
        print_skill_guidance
        return 1
    fi

    skill -A "$skill_spec" --claude
}

maybe_install_skill() {
    case "$install_skill" in
        0|false|no|skip)
            print_skill_guidance
            return 0
            ;;
        1|true|yes)
            install_zrouter_skill || exit 1
            return 0
            ;;
    esac

    if ! command -v skill >/dev/null 2>&1; then
        print_skill_guidance
        return 0
    fi

    if [ -r /dev/tty ] && [ -w /dev/tty ]; then
        printf "Install the zrouter Claude Code skill now? [Y/n] " >/dev/tty
        read answer </dev/tty || answer=""
        case "$answer" in
            n|N|no|NO|No)
                print_skill_guidance
                ;;
            *)
                install_zrouter_skill || print_skill_guidance
                ;;
        esac
    else
        print_skill_guidance
    fi
}

case "$(uname -s)" in
    Linux) os="linux" ;;
    Darwin) os="macos" ;;
    *)
        echo "unsupported OS: $(uname -s)" >&2
        exit 1
        ;;
esac

case "$(uname -m)" in
    x86_64 | amd64) arch="x86_64" ;;
    arm64 | aarch64) arch="aarch64" ;;
    *)
        echo "unsupported architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

if [ "$version" = "latest" ] && [ -n "$current_version" ]; then
    latest_tag=""
    if command -v curl >/dev/null 2>&1; then
        latest_tag=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
            -H "User-Agent: zrouter-updater" \
            | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' | head -1) || true
    elif command -v wget >/dev/null 2>&1; then
        latest_tag=$(wget -qO- "https://api.github.com/repos/$repo/releases/latest" \
            | grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' | head -1) || true
    fi
    if [ -n "$latest_tag" ]; then
        latest_version="${latest_tag#v}"
        if [ "$current_version" = "$latest_version" ]; then
            echo "zrouter $current_version is already up to date"
            exit 0
        fi
        echo "Updating zrouter $current_version -> $latest_version..."
    fi
fi

archive="zrouter-$arch-$os.tar.gz"
if [ "$version" = "latest" ]; then
    base_url="https://github.com/$repo/releases/latest/download"
else
    case "$version" in
        v*) tag="$version" ;;
        *) tag="v$version" ;;
    esac
    base_url="https://github.com/$repo/releases/download/$tag"
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM

download "$base_url/$archive" "$tmp_dir/$archive"
download "$base_url/checksums.txt" "$tmp_dir/checksums.txt"

expected="$(awk -v file="$archive" '$2 == file { print $1 }' "$tmp_dir/checksums.txt")"
if [ -z "$expected" ]; then
    echo "checksum not found for $archive" >&2
    exit 1
fi

actual="$(sha256_file "$tmp_dir/$archive")"
if [ "$actual" != "$expected" ]; then
    echo "checksum mismatch for $archive" >&2
    exit 1
fi

need_cmd tar
mkdir -p "$install_dir"
tar -xzf "$tmp_dir/$archive" -C "$tmp_dir"

if command -v install >/dev/null 2>&1; then
    install -m 755 "$tmp_dir/zrouter" "$install_dir/zrouter"
else
    cp "$tmp_dir/zrouter" "$install_dir/zrouter"
    chmod 755 "$install_dir/zrouter"
fi

case ":$PATH:" in
    *":$install_dir:"*) ;;
    *)
        echo "Installed zrouter to $install_dir, but that directory is not in PATH."
        echo "Add this to your shell profile:"
        echo "  export PATH=\"$install_dir:\$PATH\""
        ;;
esac

echo "zrouter installed to $install_dir/zrouter"
maybe_install_skill
