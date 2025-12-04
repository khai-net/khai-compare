#!/bin/bash
set -e

# Detect platform
PLATFORM=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

if [ "$PLATFORM" = "darwin" ]; then
    TARGET="macos-arm64"
    CMAKE_ARCH="arm64"
elif [ "$PLATFORM" = "linux" ] && [ "$ARCH" = "x86_64" ]; then
    TARGET="linux-x86_64"
    CMAKE_ARCH="x86_64"
elif [ "$PLATFORM" = "linux" ] && [ "$ARCH" = "aarch64" ]; then
    TARGET="linux-aarch64"
    CMAKE_ARCH="aarch64"
else
    echo "Unsupported platform: $PLATFORM $ARCH"
    exit 1
fi

echo "Building for: $TARGET"

# Create directory structure
mkdir -p third-party/src
mkdir -p third-party/build
mkdir -p third-party/lib
mkdir -p third-party/include

cd third-party

# Library versions
ZSTD_VERSION="1.5.6"
BSON_VERSION="2.0.0"
MONGOC_VERSION="2.0.0"
EXPAT_VERSION="2.6.4"
MINIZIP_VERSION="4.0.7"
XLSXIO_VERSION="0.2.36"

# Build zstd
echo "Building zstd..."
if [ ! -d "src/zstd-${ZSTD_VERSION}" ]; then
    cd src
    curl -L "https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz" -o zstd.tar.gz
    tar xzf zstd.tar.gz
    rm zstd.tar.gz
    cd ..
fi

cd src/zstd-${ZSTD_VERSION}
make clean || true

if [ "$PLATFORM" = "darwin" ]; then
    make lib CFLAGS="-O3 -arch ${CMAKE_ARCH}" -j$(sysctl -n hw.ncpu)
else
    make lib CFLAGS="-O3 -fPIC" -j$(nproc)
fi

cp lib/libzstd.a ../../lib/
cp lib/zstd.h ../../include/
cd ../..

# Build libbson
echo "Building libbson..."
if [ ! -d "src/mongo-c-driver-${MONGOC_VERSION}" ]; then
    cd src
    curl -L "https://github.com/mongodb/mongo-c-driver/releases/download/${MONGOC_VERSION}/mongo-c-driver-${MONGOC_VERSION}.tar.gz" -o mongo-c-driver.tar.gz
    tar xzf mongo-c-driver.tar.gz
    rm mongo-c-driver.tar.gz
    cd ..

    # Patch the CMakeLists.txt to fix CMP0042 policy issue
    echo "Patching mongo-c-driver CMakeLists.txt..."
    if [ -f "src/mongo-c-driver-${MONGOC_VERSION}/src/libbson/CMakeLists.txt" ]; then
        # Remove the entire if (APPLE) block that sets CMP0042 to OLD
        sed -i.bak '/if (APPLE)/,/endif ()/{ /cmake_policy (SET CMP0042 OLD)/d; }' src/mongo-c-driver-${MONGOC_VERSION}/src/libbson/CMakeLists.txt
    fi
    if [ -f "src/mongo-c-driver-${MONGOC_VERSION}/src/libmongoc/CMakeLists.txt" ]; then
        sed -i.bak '/if (APPLE)/,/endif ()/{ /cmake_policy (SET CMP0042 OLD)/d; }' src/mongo-c-driver-${MONGOC_VERSION}/src/libmongoc/CMakeLists.txt
    fi
else
    echo "Source already exists, checking if patch is needed..."
    # Apply patch if not already applied
    if grep -q "cmake_policy.*CMP0042.*OLD" src/mongo-c-driver-${MONGOC_VERSION}/src/libbson/CMakeLists.txt 2>/dev/null; then
        echo "Applying patch to libbson..."
        sed -i.bak '/if (APPLE)/,/endif ()/{ /cmake_policy (SET CMP0042 OLD)/d; }' src/mongo-c-driver-${MONGOC_VERSION}/src/libbson/CMakeLists.txt
    fi
    if grep -q "cmake_policy.*CMP0042.*OLD" src/mongo-c-driver-${MONGOC_VERSION}/src/libmongoc/CMakeLists.txt 2>/dev/null; then
        echo "Applying patch to libmongoc..."
        sed -i.bak '/if (APPLE)/,/endif ()/{ /cmake_policy (SET CMP0042 OLD)/d; }' src/mongo-c-driver-${MONGOC_VERSION}/src/libmongoc/CMakeLists.txt
    fi
fi

cd build
rm -rf bson-build
mkdir -p bson-build
cd bson-build

CMAKE_OPTS="-DENABLE_MONGOC=OFF -DENABLE_BSON=ON -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$(pwd)/../../install"
CMAKE_OPTS="$CMAKE_OPTS -DCMAKE_POLICY_DEFAULT_CMP0042=NEW"

if [ "$PLATFORM" = "darwin" ]; then
    CMAKE_OPTS="$CMAKE_OPTS -DCMAKE_OSX_ARCHITECTURES=${CMAKE_ARCH}"
fi

cmake ../../src/mongo-c-driver-${MONGOC_VERSION} $CMAKE_OPTS
cmake --build . --config Release
cmake --install .

# Copy libraries and headers
INSTALL_LIB="../../install/lib"
INSTALL_INC="../../install/include"

# Find the actual library names
if [ -f "$INSTALL_LIB/libbson2.a" ]; then
    cp "$INSTALL_LIB/libbson2.a" ../../lib/libbson2.a
    echo "Copied libbson2.a"
elif [ -f "$INSTALL_LIB/libbson-2.0.a" ]; then
    cp "$INSTALL_LIB/libbson-2.0.a" ../../lib/libbson2.a
    echo "Copied libbson-2.0.a"
elif [ -f "$INSTALL_LIB/libbson-static-2.0.a" ]; then
    cp "$INSTALL_LIB/libbson-static-2.0.a" ../../lib/libbson2.a
    echo "Copied libbson-static-2.0.a"
elif [ -f "$INSTALL_LIB/libbson.a" ]; then
    cp "$INSTALL_LIB/libbson.a" ../../lib/libbson2.a
    echo "Copied libbson.a"
else
    echo "Error: libbson library not found in $INSTALL_LIB"
    ls -la "$INSTALL_LIB" || true
    exit 1
fi

# Copy headers - check multiple possible locations
if [ -d "$INSTALL_INC/bson-2.0.0" ]; then
    cp -r "$INSTALL_INC/bson-2.0.0/"* ../../include/
    echo "Copied bson-2.0.0 headers"
elif [ -d "$INSTALL_INC/libbson-2.0" ]; then
    cp -r "$INSTALL_INC/libbson-2.0/"* ../../include/
    echo "Copied libbson-2.0 headers"
elif [ -d "$INSTALL_INC/libbson-1.0" ]; then
    cp -r "$INSTALL_INC/libbson-1.0/"* ../../include/
    echo "Copied libbson-1.0 headers"
else
    echo "Error: libbson headers not found in $INSTALL_INC"
    ls -la "$INSTALL_INC" || true
    exit 1
fi
cd ../..

# Build libmongoc
echo "Building libmongoc..."
cd build
rm -rf mongoc-build
mkdir -p mongoc-build
cd mongoc-build

CMAKE_OPTS="-DENABLE_MONGOC=ON -DENABLE_BSON=ON -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$(pwd)/../../install"
CMAKE_OPTS="$CMAKE_OPTS -DENABLE_AUTOMATIC_INIT_AND_CLEANUP=OFF -DENABLE_ZSTD=OFF"
CMAKE_OPTS="$CMAKE_OPTS -DCMAKE_POLICY_DEFAULT_CMP0042=NEW"

if [ "$PLATFORM" = "darwin" ]; then
    CMAKE_OPTS="$CMAKE_OPTS -DCMAKE_OSX_ARCHITECTURES=${CMAKE_ARCH}"
fi

cmake ../../src/mongo-c-driver-${MONGOC_VERSION} $CMAKE_OPTS
cmake --build . --config Release
cmake --install .

# Copy libraries and headers
INSTALL_LIB="../../install/lib"
INSTALL_INC="../../install/include"

# Find the actual library names
if [ -f "$INSTALL_LIB/libmongoc2.a" ]; then
    cp "$INSTALL_LIB/libmongoc2.a" ../../lib/libmongoc2.a
    echo "Copied libmongoc2.a"
elif [ -f "$INSTALL_LIB/libmongoc-2.0.a" ]; then
    cp "$INSTALL_LIB/libmongoc-2.0.a" ../../lib/libmongoc2.a
    echo "Copied libmongoc-2.0.a"
elif [ -f "$INSTALL_LIB/libmongoc-static-2.0.a" ]; then
    cp "$INSTALL_LIB/libmongoc-static-2.0.a" ../../lib/libmongoc2.a
    echo "Copied libmongoc-static-2.0.a"
elif [ -f "$INSTALL_LIB/libmongoc.a" ]; then
    cp "$INSTALL_LIB/libmongoc.a" ../../lib/libmongoc2.a
    echo "Copied libmongoc.a"
else
    echo "Error: libmongoc library not found in $INSTALL_LIB"
    ls -la "$INSTALL_LIB" || true
    exit 1
fi

# Copy headers - check multiple possible locations
if [ -d "$INSTALL_INC/mongoc-2.0.0" ]; then
    cp -r "$INSTALL_INC/mongoc-2.0.0/"* ../../include/
    echo "Copied mongoc-2.0.0 headers"
elif [ -d "$INSTALL_INC/libmongoc-2.0" ]; then
    cp -r "$INSTALL_INC/libmongoc-2.0/"* ../../include/
    echo "Copied libmongoc-2.0 headers"
elif [ -d "$INSTALL_INC/libmongoc-1.0" ]; then
    cp -r "$INSTALL_INC/libmongoc-1.0/"* ../../include/
    echo "Copied libmongoc-1.0 headers"
else
    echo "Error: libmongoc headers not found in $INSTALL_INC"
    ls -la "$INSTALL_INC" || true
    exit 1
fi
cd ../..

# Build expat
echo "Building expat..."
if [ ! -d "src/libexpat-R_${EXPAT_VERSION//./_}" ]; then
    cd src
    curl -L "https://github.com/libexpat/libexpat/archive/refs/tags/R_${EXPAT_VERSION//./_}.tar.gz" -o expat.tar.gz
    tar xzf expat.tar.gz
    rm expat.tar.gz
    cd ..
fi

cd build
rm -rf expat-build
mkdir -p expat-build
cd expat-build

CMAKE_OPTS="-DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$(pwd)/../../install"
CMAKE_OPTS="$CMAKE_OPTS -DEXPAT_BUILD_EXAMPLES=OFF -DEXPAT_BUILD_TESTS=OFF -DEXPAT_BUILD_TOOLS=OFF"
CMAKE_OPTS="$CMAKE_OPTS -DEXPAT_SHARED_LIBS=OFF"

if [ "$PLATFORM" = "darwin" ]; then
    CMAKE_OPTS="$CMAKE_OPTS -DCMAKE_OSX_ARCHITECTURES=${CMAKE_ARCH}"
fi

cmake ../../src/libexpat-R_${EXPAT_VERSION//./_}/expat $CMAKE_OPTS
cmake --build . --config Release
cmake --install .

# Copy library and headers
cp ../../install/lib/libexpat.a ../../lib/
cp -r ../../install/include/expat*.h ../../include/
echo "Copied expat library and headers"
cd ../..

# Build minizip-ng (modern minizip)
echo "Building minizip-ng..."
if [ ! -d "src/minizip-ng-${MINIZIP_VERSION}" ]; then
    cd src
    curl -L "https://github.com/zlib-ng/minizip-ng/archive/refs/tags/${MINIZIP_VERSION}.tar.gz" -o minizip-ng.tar.gz
    tar xzf minizip-ng.tar.gz
    rm minizip-ng.tar.gz
    cd ..
fi

cd build
rm -rf minizip-build
mkdir -p minizip-build
cd minizip-build

CMAKE_OPTS="-DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$(pwd)/../../install"
CMAKE_OPTS="$CMAKE_OPTS -DMZ_BUILD_TESTS=OFF -DMZ_BUILD_UNIT_TESTS=OFF"
CMAKE_OPTS="$CMAKE_OPTS -DBUILD_SHARED_LIBS=OFF"
# Disable optional compression/encryption to reduce dependencies
CMAKE_OPTS="$CMAKE_OPTS -DMZ_BZIP2=OFF -DMZ_LZMA=OFF -DMZ_ZSTD=OFF"
CMAKE_OPTS="$CMAKE_OPTS -DMZ_OPENSSL=OFF -DMZ_LIBBSD=OFF -DMZ_LIBCOMP=OFF"
CMAKE_OPTS="$CMAKE_OPTS -DMZ_ICONV=OFF"

if [ "$PLATFORM" = "darwin" ]; then
    CMAKE_OPTS="$CMAKE_OPTS -DCMAKE_OSX_ARCHITECTURES=${CMAKE_ARCH}"
fi

cmake ../../src/minizip-ng-${MINIZIP_VERSION} $CMAKE_OPTS
cmake --build . --config Release
cmake --install .

# Copy library and headers
if [ -f "../../install/lib/libminizip.a" ]; then
    cp ../../install/lib/libminizip.a ../../lib/
elif [ -f "../../install/lib/libminizip-ng.a" ]; then
    cp ../../install/lib/libminizip-ng.a ../../lib/libminizip.a
fi

# Create both minizip and minizip-ng include directories for compatibility
mkdir -p ../../include/minizip
mkdir -p ../../include/minizip-ng

# Copy headers to both locations for maximum compatibility
if [ -d "../../install/include/minizip-ng" ]; then
    cp -r ../../install/include/minizip-ng/* ../../include/minizip-ng/
    cp -r ../../install/include/minizip-ng/* ../../include/minizip/
elif [ -d "../../install/include/minizip" ]; then
    cp -r ../../install/include/minizip/* ../../include/minizip/
    cp -r ../../install/include/minizip/* ../../include/minizip-ng/
fi

# Also copy mz*.h files if they exist at root level
cp ../../install/include/mz*.h ../../include/minizip-ng/ 2>/dev/null || true
cp ../../install/include/mz*.h ../../include/minizip/ 2>/dev/null || true

echo "Copied minizip library and headers"
cd ../..

# Build xlsxio
echo "Building xlsxio..."
if [ ! -d "src/xlsxio-${XLSXIO_VERSION}" ]; then
    cd src
    curl -L "https://github.com/brechtsanders/xlsxio/archive/refs/tags/${XLSXIO_VERSION}.tar.gz" -o xlsxio.tar.gz
    tar xzf xlsxio.tar.gz
    rm xlsxio.tar.gz
    cd ..
fi

cd src/xlsxio-${XLSXIO_VERSION}

# Clean and rebuild with correct architecture
make clean || true

XLSXIO_CFLAGS="-O3 -Iinclude -Ilib -I../../include"
XLSXIO_LDFLAGS="-L../../lib"

if [ "$PLATFORM" = "darwin" ]; then
    XLSXIO_CFLAGS="$XLSXIO_CFLAGS -arch ${CMAKE_ARCH}"
    XLSXIO_LDFLAGS="$XLSXIO_LDFLAGS -arch ${CMAKE_ARCH}"
else
    XLSXIO_CFLAGS="$XLSXIO_CFLAGS -fPIC"
fi

# Build xlsxio - only build static libraries
make libxlsxio_read.a libxlsxio_write.a CFLAGS="$XLSXIO_CFLAGS" LDFLAGS="$XLSXIO_LDFLAGS" || {
    echo "Error building xlsxio."
    exit 1
}

# Copy libraries and headers to third-party
cp libxlsxio_read.a ../../lib/
cp libxlsxio_write.a ../../lib/
cp include/xlsxio_read.h ../../include/
cp include/xlsxio_write.h ../../include/
echo "Copied xlsxio libraries and headers"

cd ../..

echo ""
echo "Build complete for $TARGET"
echo "Libraries installed in: $(pwd)/lib"
echo "Headers installed in: $(pwd)/include"
