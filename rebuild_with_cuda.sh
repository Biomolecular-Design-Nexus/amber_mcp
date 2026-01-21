#!/bin/bash
#
# rebuild_with_cuda.sh - Rebuild AmberTools25 + PMEMD24 with CUDA/GPU support
#
# This script rebuilds the installation with CUDA enabled for GPU acceleration.
# Requires CUDA toolkit to be installed on the system.
#
# Usage:
#   ./rebuild_with_cuda.sh
#
# Prerequisites:
#   - Existing AmberTools installation (run quick_setup.sh first)
#   - CUDA toolkit installed (nvcc available)
#   - NVIDIA GPU with compute capability 6.0+ (Pascal or newer)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}/repo/ambertools25_src"
INSTALL_PREFIX="${SCRIPT_DIR}/env"
BUILD_DIR="${SOURCE_DIR}/build"
JOBS=$(nproc 2>/dev/null || echo 4)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "=============================================="
echo "  Rebuild AmberTools with CUDA/GPU Support"
echo "=============================================="
echo ""

#==============================================================================
# Check CUDA
#==============================================================================

log_info "Checking CUDA installation..."

if ! command -v nvcc &> /dev/null; then
    log_error "nvcc not found. Please install CUDA toolkit first."
    echo ""
    echo "On Ubuntu/Debian:"
    echo "  sudo apt install nvidia-cuda-toolkit"
    echo ""
    echo "Or download from NVIDIA:"
    echo "  https://developer.nvidia.com/cuda-downloads"
    exit 1
fi

CUDA_VERSION=$(nvcc --version | grep "release" | sed 's/.*release \([0-9]*\.[0-9]*\).*/\1/')
CUDA_PATH=$(dirname $(dirname $(which nvcc)))

log_success "CUDA $CUDA_VERSION found at $CUDA_PATH"

# Check GPU
if command -v nvidia-smi &> /dev/null; then
    echo ""
    log_info "Detected GPUs:"
    nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader | while read line; do
        echo "  GPU $line"
    done
fi

echo ""

#==============================================================================
# Check existing installation
#==============================================================================

if [[ ! -d "$BUILD_DIR" ]]; then
    log_error "Build directory not found. Run quick_setup.sh first."
    exit 1
fi

if [[ ! -f "$INSTALL_PREFIX/bin/sander" ]]; then
    log_warning "Existing installation not found. Will do full build."
fi

#==============================================================================
# Clean and reconfigure with CUDA
#==============================================================================

log_info "Cleaning build directory..."
cd "$BUILD_DIR"
# Thorough clean to avoid target conflicts
rm -rf CMakeCache.txt CMakeFiles cmake_install.cmake Makefile CPackConfig.cmake CPackSourceConfig.cmake
rm -rf AmberTools src cmake-packaging

log_info "Configuring with CUDA support..."

# Set MPI environment for conda
export OPAL_PREFIX="$INSTALL_PREFIX"
export PATH="$INSTALL_PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="$INSTALL_PREFIX/lib:$LD_LIBRARY_PATH"
export LIBRARY_PATH="$INSTALL_PREFIX/lib:$LIBRARY_PATH"
export CPATH="$INSTALL_PREFIX/include:$CPATH"

# Set cmake package hints for conda libraries
export CMAKE_PREFIX_PATH="$INSTALL_PREFIX:$CMAKE_PREFIX_PATH"
export PKG_CONFIG_PATH="$INSTALL_PREFIX/lib/pkgconfig:$PKG_CONFIG_PATH"
export NetCDF_ROOT="$INSTALL_PREFIX"
export HDF5_ROOT="$INSTALL_PREFIX"

# Ensure the conda library path is searched first by linker
export LDFLAGS="-L$INSTALL_PREFIX/lib -Wl,-rpath,$INSTALL_PREFIX/lib $LDFLAGS"

# Use MPI compilers from the conda environment
MPI_CC="$INSTALL_PREFIX/bin/mpicc"
MPI_CXX="$INSTALL_PREFIX/bin/mpicxx"
MPI_FC="$INSTALL_PREFIX/bin/mpifort"

log_info "Using MPI from: $INSTALL_PREFIX/bin"

# Detect CUDA architecture
# A100 = sm_80, V100 = sm_70, RTX 30xx = sm_86, RTX 40xx = sm_89
# Default to auto-detection or common architectures
CUDA_ARCH=""
if nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | grep -q "8.0"; then
    CUDA_ARCH="-DCUDA_NVCC_FLAGS=-gencode;arch=compute_80,code=sm_80"
    log_info "Detected A100 GPU, using sm_80"
fi

cmake .. \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
    -DCOMPILER=MANUAL \
    -DMPI=ON \
    -DCUDA=ON \
    -DCUDA_TOOLKIT_ROOT_DIR="$CUDA_PATH" \
    $CUDA_ARCH \
    -DBUILD_PYTHON=ON \
    -DDOWNLOAD_MINICONDA=OFF \
    -DPYTHON_EXECUTABLE="$INSTALL_PREFIX/bin/python" \
    -DCMAKE_C_COMPILER="/usr/bin/gcc" \
    -DCMAKE_CXX_COMPILER="/usr/bin/g++" \
    -DCMAKE_Fortran_COMPILER="/usr/bin/gfortran" \
    -DMPI_C_COMPILER="$MPI_CC" \
    -DMPI_CXX_COMPILER="$MPI_CXX" \
    -DMPI_Fortran_COMPILER="$MPI_FC" \
    -DARPACK_LIBRARY="$INSTALL_PREFIX/lib/libarpack.so" \
    -DNetCDF_LIBRARY="$INSTALL_PREFIX/lib/libnetcdf.so" \
    -DNetCDF_INCLUDE_DIR="$INSTALL_PREFIX/include" \
    -DNetCDF_LIBRARY_F77="$INSTALL_PREFIX/lib/libnetcdff.so" \
    -DNetCDF_LIBRARY_F90="$INSTALL_PREFIX/lib/libnetcdff.so" \
    -DCMAKE_EXE_LINKER_FLAGS="-L$INSTALL_PREFIX/lib -Wl,-rpath,$INSTALL_PREFIX/lib" \
    -DCMAKE_SHARED_LINKER_FLAGS="-L$INSTALL_PREFIX/lib -Wl,-rpath,$INSTALL_PREFIX/lib" \
    -DFORCE_EXTERNAL_LIBS="kmmd;netcdf;netcdf-fortran;arpack;blas;lapack" \
    -DBUILD_RISM=OFF \
    -Wno-dev \
    2>&1 | tee cmake_cuda_output.log

if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    log_error "CMake configuration failed. Check cmake_cuda_output.log"
    exit 1
fi

log_success "CMake configuration completed with CUDA"

#==============================================================================
# Build
#==============================================================================

echo ""
log_info "Building with CUDA support (this may take a while)..."

make -j"$JOBS" 2>&1 | tee build_cuda_output.log

if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    log_error "Build failed. Check build_cuda_output.log"
    exit 1
fi

log_success "Build completed"

#==============================================================================
# Install
#==============================================================================

echo ""
log_info "Installing..."

make install 2>&1 | tee install_cuda_output.log

if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    log_error "Installation failed. Check install_cuda_output.log"
    exit 1
fi

log_success "Installation completed"

#==============================================================================
# Verify CUDA binaries
#==============================================================================

echo ""
log_info "Verifying CUDA-enabled binaries..."

# Source the environment
source "$INSTALL_PREFIX/amber.sh"

# Check for CUDA binaries
cuda_tools=("pmemd.cuda" "pmemd.cuda.MPI")

for tool in "${cuda_tools[@]}"; do
    if [[ -f "$INSTALL_PREFIX/bin/$tool" ]]; then
        log_success "$tool installed: $INSTALL_PREFIX/bin/$tool"
    else
        log_warning "$tool not found"
    fi
done

echo ""
echo "=============================================="
echo "  CUDA Build Complete!"
echo "=============================================="
echo ""
echo "New GPU-accelerated binaries:"
echo "  - pmemd.cuda      (single GPU)"
echo "  - pmemd.cuda.MPI  (multi-GPU)"
echo ""
echo "Usage example:"
echo "  pmemd.cuda -O -i prod.in -o prod.out -p system.prmtop -c equil.rst7 -r prod.rst7 -x prod.nc"
echo ""
echo "For multi-GPU (e.g., 2 GPUs):"
echo "  mpirun -np 2 pmemd.cuda.MPI -O -i prod.in -o prod.out -p system.prmtop -c equil.rst7 -r prod.rst7 -x prod.nc"
echo ""
echo "Performance notes:"
echo "  - GPU version is typically 10-100x faster than CPU for large systems"
echo "  - Best performance with systems > 10,000 atoms"
echo "  - Use 'CUDA_VISIBLE_DEVICES=0' to select specific GPU"
echo ""
