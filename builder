#!/bin/sh -e
#
# Custom XBPS Builder
#

: "${VOID_PACKAGES:=./void-packages}"
: "${PKGS_DIR:=./pkgs}"
: "${REPO_DIR:=./repo/binpkgs}"
: "${SIGN_KEY:=./repo-key.pem}"
: "${SIGNED_BY:=Kurnias <adityakurnia@proton.me>}"
: "${MASTERDIR:=$VOID_PACKAGES/masterdir-$(uname -m)}"

info()  { printf "\033[0;32m[INFO]\033[0m %s\n" "$*"; }
error() { printf "\033[0;31m[ERROR]\033[0m %s\n" "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $0 [options] [package_name]

Options:
  -b, --bootstrap     Run binary-bootstrap (package name optional)
  -B, --rebootstrap   Remove masterdir (zap), then bootstrap again from scratch
  -h, --help          Show this help

Examples:
  $0 polymc           Build a package
  $0 -b               Bootstrap only
  $0 -b polymc        Bootstrap, then build
  $0 -B polymc        Re-bootstrap from scratch, then build
EOF
}

BOOTSTRAP=0
PKG_TO_BUILD=

while [ "$#" -gt 0 ]; do
    case "$1" in
        -b|--bootstrap)   BOOTSTRAP=1 ;;
        -B|--rebootstrap) BOOTSTRAP=2 ;;
        -h|--help)        usage; exit 0 ;;
        -*)               usage >&2; error "Unknown option: $1" ;;  
        *)
            [ -z "$PKG_TO_BUILD" ] || error "Only one package name is allowed"
            PKG_TO_BUILD="$1"
            ;;
    esac
    shift
done

if [ -z "$PKG_TO_BUILD" ] && [ "$BOOTSTRAP" -eq 0 ]; then
    usage >&2
    exit 1
fi

# 1. Setup void-packages (Sparse checkout to save disk space)
if [ -d "$VOID_PACKAGES" ]; then
    info "Resetting void-packages..."
    (
        cd "$VOID_PACKAGES"
        git fetch -q --depth 1 origin HEAD
        git reset -q --hard FETCH_HEAD
        git clean -fdq
        git sparse-checkout add srcpkgs/xbps-triggers
    )
else
    info "Cloning void-packages..."
    git clone --depth 1 --filter=blob:none --no-checkout -q https://github.com/void-linux/void-packages "$VOID_PACKAGES"
    (
        cd "$VOID_PACKAGES"
        git sparse-checkout init --cone
        git sparse-checkout set common etc srcpkgs/base-files srcpkgs/xbps srcpkgs/xbps-triggers ${PKG_TO_BUILD:+"srcpkgs/$PKG_TO_BUILD"}
        git checkout -q
    )
fi

if [ -f ./etc/conf ]; then
    info "Installing custom xbps-src config..."
    cp ./etc/conf "$VOID_PACKAGES/etc/conf"
fi

# 2. Bootstrap masterdir
if [ "$BOOTSTRAP" -eq 2 ]; then
    info "Removing masterdir (zap)..."
    "$VOID_PACKAGES/xbps-src" zap
fi

if [ "$BOOTSTRAP" -ne 0 ] || [ ! -d "$MASTERDIR" ]; then
    [ "$BOOTSTRAP" -ne 0 ] || info "Masterdir not found, bootstrapping automatically..."
    info "Running binary-bootstrap..."
    "$VOID_PACKAGES/xbps-src" binary-bootstrap
    info "Bootstrap complete."
fi

# Bootstrap-only mode
if [ -z "$PKG_TO_BUILD" ]; then
    info "✅ DONE! No package specified, exiting after bootstrap."
    exit 0
fi

# 3. Inject custom package template
if [ ! -d "$PKGS_DIR/$PKG_TO_BUILD" ]; then
    error "Package '$PKG_TO_BUILD' not found in '$PKGS_DIR/'"
fi

info "Copying template for '$PKG_TO_BUILD'..."
DEST="$VOID_PACKAGES/srcpkgs/$PKG_TO_BUILD"
rm -rf "$DEST"
cp -r "$PKGS_DIR/$PKG_TO_BUILD" "$DEST"

# 4. Build the package
info "Cleaning previous build state..."
"$VOID_PACKAGES/xbps-src" clean "$PKG_TO_BUILD"

info "Removing old built versions of '$PKG_TO_BUILD' from hostdir..."
find "$VOID_PACKAGES/hostdir/binpkgs" -maxdepth 1 \
    -name "${PKG_TO_BUILD}-[0-9]*.xbps*" -type f -delete

info "Building '$PKG_TO_BUILD'..."
"$VOID_PACKAGES/xbps-src" pkg "$PKG_TO_BUILD"

# 5. Prepare repository
info "Preparing repository at $REPO_DIR..."
mkdir -p "$REPO_DIR"

info "Cleaning up old versions of '$PKG_TO_BUILD'..."
find "$REPO_DIR" -maxdepth 1 -name "${PKG_TO_BUILD}-*.xbps*" -type f -delete

info "Copying new .xbps package to repository..."
cp "$VOID_PACKAGES/hostdir/binpkgs/${PKG_TO_BUILD}"*.xbps "$REPO_DIR/"

# 6. Sign and reindex repository
info "Signing packages..."
for pkg in "$REPO_DIR"/*.xbps; do
    [ -e "$pkg" ] || continue
    xbps-rindex --privkey "$SIGN_KEY" --signedby "$SIGNED_BY" --sign-pkg "$pkg" >/dev/null
done

info "Reindexing repository..."
xbps-rindex --force -cC -v "$REPO_DIR" >/dev/null
xbps-rindex --force -a -v "$REPO_DIR"/*.xbps >/dev/null

info "Signing repository metadata..."
xbps-rindex --privkey "$SIGN_KEY" --signedby "$SIGNED_BY" --sign "$REPO_DIR" >/dev/null

# 7. Regenerate the package index for index.html
info "Updating package index..."
val() { sed -n "s/^$1=\"\(.*\)\"\$/\1/p" "$2" | head -1 | tr -d '"'; }
{
    printf 'const PACKAGES = [\n'
    sep=
    for pkg in "$REPO_DIR"/*.xbps; do
        [ -e "$pkg" ] || continue
        base=$(basename "$pkg" .xbps)
        pkgver=$(xbps-uhelper binpkgver "$base")
        name=$(xbps-uhelper getpkgname "$pkgver")
        tpl="$PKGS_DIR/$name/template"
        [ -f "$tpl" ] || error "No template for '$name' in '$PKGS_DIR/'"
        printf '%s{"name":"%s","version":"%s","arch":"%s","license":"%s","homepage":"%s","desc":"%s","maintainer":"%s"}' \
            "$sep" "$name" "$(xbps-uhelper getpkgversion "$pkgver")" "${base#"$pkgver".}" \
            "$(val license "$tpl")" "$(val homepage "$tpl")" "$(val short_desc "$tpl")" "$(val maintainer "$tpl")"
        sep=,
    done
    printf '\n];\n'
} > "packages.js"

info "✅ DONE! Package ready at: $REPO_DIR"
