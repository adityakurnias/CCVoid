#!/bin/sh -e
#
# Custom XBPS Builder
#

: "${VOID_PACKAGES:=./void-packages}"
: "${PKGS_DIR:=./pkgs}"
: "${REPO_DIR:=./repo/binpkgs}"
: "${SIGN_KEY:=./repo-key.pem}"
: "${SIGNED_BY:=Kurnias <adityakurnia@proton.me>}"

info()  { printf "\033[0;32m[INFO]\033[0m %s\n" "$*"; }
error() { printf "\033[0;31m[ERROR]\033[0m %s\n" "$*" >&2; exit 1; }

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <package_name>"
    exit 1
fi

PKG_TO_BUILD="$1"

# 1. Setup void-packages (Sparse checkout to save disk space)
if [ -d "$VOID_PACKAGES" ]; then
    info "Resetting void-packages..."
    (
        cd "$VOID_PACKAGES"
        git reset --hard >/dev/null
        git clean -fd >/dev/null
        git pull -q
    )
else
    info "Cloning void-packages..."
    git clone --filter=blob:none --no-checkout -q https://github.com/void-linux/void-packages "$VOID_PACKAGES"
    (
        cd "$VOID_PACKAGES"
        git sparse-checkout init --cone
        git sparse-checkout set common etc "srcpkgs/$PKG_TO_BUILD"
        git checkout -q
    )
fi

# 2. Inject custom package template
if [ ! -d "$PKGS_DIR/$PKG_TO_BUILD" ]; then
    error "Package '$PKG_TO_BUILD' not found in '$PKGS_DIR/'"
fi

info "Copying template for '$PKG_TO_BUILD'..."
DEST="$VOID_PACKAGES/srcpkgs/$PKG_TO_BUILD"
rm -rf "$DEST"
cp -r "$PKGS_DIR/$PKG_TO_BUILD" "$DEST"

# 3. Build the package
info "Building '$PKG_TO_BUILD'..."
"$VOID_PACKAGES/xbps-src" pkg "$PKG_TO_BUILD"

# 4. Prepare repository
info "Preparing repository at $REPO_DIR..."
mkdir -p "$REPO_DIR"

info "Copying .xbps package to repository..."
cp "$VOID_PACKAGES/hostdir/binpkgs/${PKG_TO_BUILD}"*.xbps "$REPO_DIR/"

# 5. Sign and reindex repository
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

# 6. Regenerate the package index for index.html
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
} > packages.js

info "✅ DONE! Package ready at: $REPO_DIR"