#!/bin/bash
set -eo pipefail

# Build static libpq (PostgreSQL) for iOS → xcframework
#
# Requires: OpenSSL xcframework already built
#
# Produces: Libs/ios/LibPQ.xcframework/
#
# Usage:
#   ./scripts/ios/build-libpq-ios.sh

PG_VERSION="17.4"
PG_SHA256="1b9e50ed65ef9e4e4ed3c073cb9950a8e38e94a2e7e3c5e4b5b56e585e104248"
IOS_DEPLOY_TARGET="17.0"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIBS_DIR="$PROJECT_DIR/Libs/ios"
BUILD_DIR="$(mktemp -d)"
NCPU=$(sysctl -n hw.ncpu)

run_quiet() {
    local logfile
    logfile=$(mktemp)
    if ! "$@" > "$logfile" 2>&1; then
        echo "FAILED: $*"
        tail -50 "$logfile"
        rm -f "$logfile"
        return 1
    fi
    rm -f "$logfile"
}

cleanup() {
    echo "   Cleaning up build directory..."
    rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

echo "Building static libpq (PostgreSQL $PG_VERSION) for iOS"
echo "   Build dir: $BUILD_DIR"

# --- Locate OpenSSL ---

setup_openssl_prefix() {
    local PLATFORM_KEY=$1  # ios-arm64 or ios-arm64-simulator
    local PREFIX_DIR="$BUILD_DIR/openssl-$PLATFORM_KEY"

    local SSL_LIB=$(find "$LIBS_DIR/OpenSSL-SSL.xcframework" -path "*$PLATFORM_KEY*/libssl.a" | head -1)
    local CRYPTO_LIB=$(find "$LIBS_DIR/OpenSSL-Crypto.xcframework" -path "*$PLATFORM_KEY*/libcrypto.a" | head -1)
    local HEADERS=$(find "$LIBS_DIR/OpenSSL-SSL.xcframework" -path "*$PLATFORM_KEY*/Headers" -type d | head -1)

    if [ -z "$SSL_LIB" ] || [ -z "$CRYPTO_LIB" ]; then
        echo "ERROR: OpenSSL not found for $PLATFORM_KEY. Run build-openssl-ios.sh first."
        exit 1
    fi

    mkdir -p "$PREFIX_DIR/lib" "$PREFIX_DIR/include"
    cp "$SSL_LIB" "$PREFIX_DIR/lib/"
    cp "$CRYPTO_LIB" "$PREFIX_DIR/lib/"
    [ -d "$HEADERS" ] && cp -R "$HEADERS/openssl" "$PREFIX_DIR/include/" 2>/dev/null || true

    OPENSSL_PREFIX="$PREFIX_DIR"
}

# --- Download PostgreSQL ---

echo "=> Downloading PostgreSQL $PG_VERSION..."
curl -fSL "https://ftp.postgresql.org/pub/source/v$PG_VERSION/postgresql-$PG_VERSION.tar.bz2" \
    -o "$BUILD_DIR/postgresql.tar.bz2"
echo "$PG_SHA256  $BUILD_DIR/postgresql.tar.bz2" | shasum -a 256 -c - > /dev/null

tar xjf "$BUILD_DIR/postgresql.tar.bz2" -C "$BUILD_DIR"
PG_SRC="$BUILD_DIR/postgresql-$PG_VERSION"

# --- Build function ---

build_libpq_slice() {
    local SDK_NAME=$1       # iphoneos or iphonesimulator
    local ARCH=$2           # arm64
    local PLATFORM_KEY=$3   # ios-arm64 or ios-arm64-simulator
    local INSTALL_DIR="$BUILD_DIR/install-$SDK_NAME-$ARCH"

    echo "=> Building libpq for $SDK_NAME ($ARCH)..."

    setup_openssl_prefix "$PLATFORM_KEY"

    local SDK_PATH
    SDK_PATH=$(xcrun --sdk "$SDK_NAME" --show-sdk-path)

    local SRC_COPY="$BUILD_DIR/pg-$SDK_NAME-$ARCH"
    cp -R "$PG_SRC" "$SRC_COPY"
    cd "$SRC_COPY"

    local HOST="aarch64-apple-darwin"
    local TARGET_FLAG=""
    if [ "$SDK_NAME" = "iphonesimulator" ]; then
        TARGET_FLAG="-target arm64-apple-ios${IOS_DEPLOY_TARGET}-simulator"
    else
        TARGET_FLAG="-target arm64-apple-ios${IOS_DEPLOY_TARGET}"
    fi

    export IPHONEOS_DEPLOYMENT_TARGET="$IOS_DEPLOY_TARGET"

    run_quiet env \
    CFLAGS="-arch $ARCH -isysroot $SDK_PATH $TARGET_FLAG -mios-version-min=$IOS_DEPLOY_TARGET -Wno-unguarded-availability-new -I$OPENSSL_PREFIX/include" \
    LDFLAGS="-arch $ARCH -isysroot $SDK_PATH $TARGET_FLAG -L$OPENSSL_PREFIX/lib" \
    ac_cv_func_strchrnul=yes \
    ./configure \
        --prefix="$INSTALL_DIR" \
        --host="$HOST" \
        --with-ssl=openssl \
        --without-readline \
        --without-icu \
        --without-gssapi

    # strchrnul compat
    cat > src/port/strchrnul_compat.c << 'COMPAT_EOF'
#include <stddef.h>
char *strchrnul(const char *s, int c) {
    while (*s && *s != (char)c) s++;
    return (char *)s;
}
COMPAT_EOF

    run_quiet make -C src/include -j"$NCPU"
    run_quiet make -C src/common -j"$NCPU"
    run_quiet make -C src/port -j"$NCPU"
    run_quiet make -C src/interfaces/libpq all-static-lib -j"$NCPU"

    # Add strchrnul compat
    xcrun --sdk "$SDK_NAME" cc -arch "$ARCH" -isysroot "$SDK_PATH" $TARGET_FLAG \
        -c -o src/port/strchrnul_compat.o src/port/strchrnul_compat.c
    run_quiet ar rs src/port/libpgport_shlib.a src/port/strchrnul_compat.o

    mkdir -p "$INSTALL_DIR/lib" "$INSTALL_DIR/include"
    cp src/interfaces/libpq/libpq.a "$INSTALL_DIR/lib/"
    cp src/common/libpgcommon_shlib.a "$INSTALL_DIR/lib/libpgcommon.a"
    cp src/port/libpgport_shlib.a "$INSTALL_DIR/lib/libpgport.a"

    # Copy headers
    cp src/interfaces/libpq/libpq-fe.h "$INSTALL_DIR/include/"
    cp src/include/libpq/libpq-fs.h "$INSTALL_DIR/include/" 2>/dev/null || true
    cp src/include/postgres_ext.h "$INSTALL_DIR/include/"
    cp src/include/pg_config_ext.h "$INSTALL_DIR/include/" 2>/dev/null || true

    echo "   Installed to $INSTALL_DIR"
}

# --- Build slices ---

build_libpq_slice "iphoneos" "arm64" "ios-arm64"
build_libpq_slice "iphonesimulator" "arm64" "ios-arm64-simulator"

# --- Create xcframeworks ---

DEVICE_DIR="$BUILD_DIR/install-iphoneos-arm64"
SIM_DIR="$BUILD_DIR/install-iphonesimulator-arm64"

rm -rf "$LIBS_DIR/LibPQ.xcframework"

echo "=> Creating LibPQ.xcframework..."

# Merge libpq + libpgcommon + libpgport into single archive per slice
for DIR in "$DEVICE_DIR" "$SIM_DIR"; do
    mkdir -p "$DIR/merged"
    cp "$DIR/lib/libpq.a" "$DIR/merged/"
    # Extract and re-archive pgcommon + pgport into libpq
    cd "$DIR/merged"
    ar x "$DIR/lib/libpgcommon.a"
    ar x "$DIR/lib/libpgport.a"
    ar rs libpq.a *.o 2>/dev/null
    rm -f *.o
done

xcodebuild -create-xcframework \
    -library "$DEVICE_DIR/merged/libpq.a" \
    -headers "$DEVICE_DIR/include" \
    -library "$SIM_DIR/merged/libpq.a" \
    -headers "$SIM_DIR/include" \
    -output "$LIBS_DIR/LibPQ.xcframework"

echo ""
echo "libpq (PostgreSQL $PG_VERSION) for iOS built successfully!"
echo "   $LIBS_DIR/LibPQ.xcframework"

# --- Verify ---

echo ""
echo "=> Verifying device slice..."
lipo -info "$DEVICE_DIR/lib/libpq.a"
otool -l "$DEVICE_DIR/lib/libpq.a" | grep -A4 "LC_BUILD_VERSION" | head -5

echo ""
echo "Done!"
