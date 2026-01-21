#!/bin/bash
#
# quick_start.sh - Run a single protein MD simulation with Amber
#
# This script automates the process of running a molecular dynamics simulation
# for a single protein molecule, including:
#   1. System preparation (tleap)
#   2. Energy minimization
#   3. Heating
#   4. Equilibration (NPT)
#   5. Production MD
#
# Usage:
#   ./quick_start.sh <protein.pdb> [options]
#
# Options:
#   -n, --name NAME        Job name (default: from PDB filename)
#   -t, --time NS          Production simulation time in ns (default: 10)
#   -T, --temp KELVIN      Temperature in Kelvin (default: 300)
#   -b, --box ANGSTROM     Box buffer size in Angstrom (default: 12)
#   -s, --salt MOLARITY    Salt concentration in M (default: 0.15)
#   -f, --forcefield FF    Force field: ff14SB, ff19SB (default: ff19SB)
#   -w, --water MODEL      Water model: tip3p, opc, tip4pew (default: opc)
#   -c, --cpu              Force CPU execution (no GPU)
#   -d, --dry-run          Generate files but don't run simulations
#   -o, --outdir DIR       Output directory (default: ./md_<name>)
#   -h, --help             Show this help message
#
# Examples:
#   ./quick_start.sh protein.pdb
#   ./quick_start.sh protein.pdb -n my_sim -t 100 -T 310
#   ./quick_start.sh protein.pdb --forcefield ff14SB --water tip3p
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AMBER_ENV="${SCRIPT_DIR}/env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

#==============================================================================
# Default parameters
#==============================================================================

PDB_FILE=""
JOB_NAME=""
SIM_TIME_NS=10
TEMPERATURE=300
BOX_BUFFER=12
SALT_CONC=0.15
FORCEFIELD="ff19SB"
WATER_MODEL="opc"
USE_GPU=true
DRY_RUN=false
OUTPUT_DIR=""

#==============================================================================
# Parse arguments
#==============================================================================

show_help() {
    head -40 "$0" | grep "^#" | sed 's/^#//' | sed 's/^ //'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--name)
            JOB_NAME="$2"
            shift 2
            ;;
        -t|--time)
            SIM_TIME_NS="$2"
            shift 2
            ;;
        -T|--temp)
            TEMPERATURE="$2"
            shift 2
            ;;
        -b|--box)
            BOX_BUFFER="$2"
            shift 2
            ;;
        -s|--salt)
            SALT_CONC="$2"
            shift 2
            ;;
        -f|--forcefield)
            FORCEFIELD="$2"
            shift 2
            ;;
        -w|--water)
            WATER_MODEL="$2"
            shift 2
            ;;
        -c|--cpu)
            USE_GPU=false
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -o|--outdir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        -*)
            log_error "Unknown option: $1"
            exit 1
            ;;
        *)
            if [[ -z "$PDB_FILE" ]]; then
                PDB_FILE="$1"
            else
                log_error "Unexpected argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

#==============================================================================
# Validate inputs
#==============================================================================

if [[ -z "$PDB_FILE" ]]; then
    log_error "No PDB file specified"
    echo ""
    echo "Usage: $0 <protein.pdb> [options]"
    echo "Use -h or --help for more information"
    exit 1
fi

if [[ ! -f "$PDB_FILE" ]]; then
    log_error "PDB file not found: $PDB_FILE"
    exit 1
fi

# Get absolute path
PDB_FILE="$(cd "$(dirname "$PDB_FILE")" && pwd)/$(basename "$PDB_FILE")"

# Set job name from PDB filename if not specified
if [[ -z "$JOB_NAME" ]]; then
    JOB_NAME="$(basename "$PDB_FILE" .pdb)"
fi

# Set output directory
if [[ -z "$OUTPUT_DIR" ]]; then
    OUTPUT_DIR="./md_${JOB_NAME}"
fi

# Map force field names
case "$FORCEFIELD" in
    ff14SB|ff14sb)
        FF_SOURCE="leaprc.protein.ff14SB"
        ;;
    ff19SB|ff19sb)
        FF_SOURCE="leaprc.protein.ff19SB"
        ;;
    *)
        log_error "Unknown force field: $FORCEFIELD (supported: ff14SB, ff19SB)"
        exit 1
        ;;
esac

# Map water model names
case "$WATER_MODEL" in
    tip3p|TIP3P)
        WATER_SOURCE="leaprc.water.tip3p"
        WATER_BOX="TIP3PBOX"
        ;;
    opc|OPC)
        WATER_SOURCE="leaprc.water.opc"
        WATER_BOX="OPCBOX"
        ;;
    tip4pew|TIP4PEW)
        WATER_SOURCE="leaprc.water.tip4pew"
        WATER_BOX="TIP4PEWBOX"
        ;;
    *)
        log_error "Unknown water model: $WATER_MODEL (supported: tip3p, opc, tip4pew)"
        exit 1
        ;;
esac

#==============================================================================
# Source Amber environment
#==============================================================================

if [[ ! -f "$AMBER_ENV/amber.sh" ]]; then
    log_error "Amber environment not found. Run quick_setup.sh first."
    exit 1
fi

source "$AMBER_ENV/amber.sh"

# Determine MD engine
if [[ "$USE_GPU" == true ]] && command -v pmemd.cuda &> /dev/null; then
    MD_ENGINE="pmemd.cuda"
    log_info "Using GPU-accelerated pmemd.cuda"
elif command -v pmemd &> /dev/null; then
    MD_ENGINE="pmemd"
    log_info "Using CPU pmemd"
else
    MD_ENGINE="sander"
    log_warning "Using sander (slower than pmemd)"
fi

#==============================================================================
# Print configuration
#==============================================================================

echo ""
echo "=============================================="
echo "  Amber MD Simulation Setup"
echo "=============================================="
echo ""
echo "Input PDB:       $PDB_FILE"
echo "Job name:        $JOB_NAME"
echo "Output dir:      $OUTPUT_DIR"
echo "Force field:     $FORCEFIELD"
echo "Water model:     $WATER_MODEL"
echo "Temperature:     ${TEMPERATURE} K"
echo "Box buffer:      ${BOX_BUFFER} Å"
echo "Salt conc:       ${SALT_CONC} M"
echo "Simulation:      ${SIM_TIME_NS} ns"
echo "MD engine:       $MD_ENGINE"
echo ""

#==============================================================================
# Create output directory
#==============================================================================

mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

log_step "Working directory: $(pwd)"

#==============================================================================
# Step 1: Prepare system with tleap
#==============================================================================

log_step "1. Preparing system with tleap..."

cat > tleap.in << EOF
# Load force field
source $FF_SOURCE
source $WATER_SOURCE

# Load protein
mol = loadpdb $PDB_FILE

# Check for problems
check mol

# Solvate with water box
solvatebox mol $WATER_BOX $BOX_BUFFER

# Add ions to neutralize the system
# addIons2 handles both positive and negative systems automatically
addIons2 mol Na+ 0
addIons2 mol Cl- 0

# Save topology and coordinates
saveamberparm mol system.prmtop system.inpcrd

# Save PDB for visualization
savepdb mol system.pdb

quit
EOF

if [[ "$DRY_RUN" == false ]]; then
    tleap -f tleap.in > tleap.log 2>&1

    if [[ ! -f "system.prmtop" ]] || [[ ! -f "system.inpcrd" ]]; then
        log_error "tleap failed. Check tleap.log for details."
        cat tleap.log
        exit 1
    fi

    # Get system info
    NATOMS=$(grep -c "ATOM" system.pdb 2>/dev/null || echo "unknown")
    log_success "System prepared: $NATOMS atoms"
else
    log_info "[DRY-RUN] Would run tleap"
fi

#==============================================================================
# Step 2: Create input files
#==============================================================================

log_step "2. Creating simulation input files..."

# Calculate steps (2 fs timestep)
NSTEPS_PROD=$((SIM_TIME_NS * 500000))  # ns * 1e6 fs / 2 fs
NSTEPS_HEAT=25000      # 50 ps heating
NSTEPS_EQUIL=250000    # 500 ps equilibration

# Minimization input
cat > min.in << EOF
Minimization
 &cntrl
   imin=1,           ! Minimization
   maxcyc=5000,      ! Max cycles
   ncyc=2500,        ! Steepest descent cycles, then conjugate gradient
   ntb=1,            ! Constant volume PBC
   ntr=1,            ! Restrain heavy atoms
   restraint_wt=10.0,
   restraintmask='!@H=',
   cut=10.0,
   ntpr=100,
 /
EOF

# Minimization without restraints
cat > min2.in << EOF
Minimization (no restraints)
 &cntrl
   imin=1,
   maxcyc=5000,
   ncyc=2500,
   ntb=1,
   ntr=0,
   cut=10.0,
   ntpr=100,
 /
EOF

# Heating input (NVT)
cat > heat.in << EOF
Heating from 0 to ${TEMPERATURE} K
 &cntrl
   imin=0,           ! MD
   irest=0,          ! New simulation
   ntx=1,            ! Read coordinates only
   ntb=1,            ! Constant volume PBC
   cut=10.0,
   ntr=1,            ! Restrain protein
   restraint_wt=5.0,
   restraintmask='@CA',
   nstlim=${NSTEPS_HEAT},
   dt=0.002,         ! 2 fs timestep
   ntc=2,            ! SHAKE on hydrogens
   ntf=2,            ! No force calc on H bonds
   tempi=0.0,
   temp0=${TEMPERATURE},
   ntt=3,            ! Langevin thermostat
   gamma_ln=2.0,
   ig=-1,            ! Random seed
   ntpr=500,
   ntwx=500,
   ntwr=5000,
   iwrap=1,
   nmropt=1,         ! NMR restraints for temperature ramp
 /
 &wt type='TEMP0', istep1=0, istep2=${NSTEPS_HEAT}, value1=0.0, value2=${TEMPERATURE}, /
 &wt type='END' /
EOF

# Equilibration input (NPT)
cat > equil.in << EOF
Equilibration (NPT)
 &cntrl
   imin=0,
   irest=1,          ! Restart
   ntx=5,            ! Read coordinates and velocities
   ntb=2,            ! Constant pressure PBC
   pres0=1.0,        ! 1 atm
   ntp=1,            ! Isotropic pressure scaling
   taup=2.0,         ! Pressure relaxation time
   cut=10.0,
   ntr=1,            ! Restrain CA atoms
   restraint_wt=2.0,
   restraintmask='@CA',
   nstlim=${NSTEPS_EQUIL},
   dt=0.002,
   ntc=2,
   ntf=2,
   temp0=${TEMPERATURE},
   ntt=3,
   gamma_ln=2.0,
   ig=-1,
   ntpr=500,
   ntwx=500,
   ntwr=10000,
   iwrap=1,
 /
EOF

# Production input (NPT)
cat > prod.in << EOF
Production MD (NPT)
 &cntrl
   imin=0,
   irest=1,
   ntx=5,
   ntb=2,
   pres0=1.0,
   ntp=1,
   taup=2.0,
   cut=10.0,
   ntr=0,            ! No restraints
   nstlim=${NSTEPS_PROD},
   dt=0.002,
   ntc=2,
   ntf=2,
   temp0=${TEMPERATURE},
   ntt=3,
   gamma_ln=2.0,
   ig=-1,
   ntpr=5000,        ! Energy output every 10 ps
   ntwx=5000,        ! Trajectory every 10 ps
   ntwr=50000,       ! Restart every 100 ps
   iwrap=1,
   ioutfm=1,         ! NetCDF trajectory format
 /
EOF

log_success "Input files created"

#==============================================================================
# Step 3: Run simulations
#==============================================================================

if [[ "$DRY_RUN" == true ]]; then
    log_info "[DRY-RUN] Would run the following simulations:"
    echo "  1. Minimization with restraints"
    echo "  2. Minimization without restraints"
    echo "  3. Heating (0 -> ${TEMPERATURE} K)"
    echo "  4. Equilibration (NPT, 500 ps)"
    echo "  5. Production (NPT, ${SIM_TIME_NS} ns)"
    echo ""
    log_info "Files created in: $OUTPUT_DIR"
    exit 0
fi

run_md() {
    local name=$1
    local input=$2
    local output=$3
    local coords=$4
    local restart=$5
    local extra_args=${6:-""}

    log_info "Running $name..."

    $MD_ENGINE -O \
        -i "$input" \
        -o "$output.out" \
        -p system.prmtop \
        -c "$coords" \
        -r "$restart" \
        -x "$output.nc" \
        -ref system.inpcrd \
        $extra_args

    if [[ $? -ne 0 ]]; then
        log_error "$name failed! Check $output.out"
        exit 1
    fi

    log_success "$name completed"
}

# Minimization 1 (with restraints)
log_step "3. Running minimization (with restraints)..."
$MD_ENGINE -O \
    -i min.in \
    -o min.out \
    -p system.prmtop \
    -c system.inpcrd \
    -r min.rst7 \
    -ref system.inpcrd

if [[ $? -ne 0 ]]; then
    log_error "Minimization 1 failed! Check min.out"
    exit 1
fi
log_success "Minimization 1 completed"

# Minimization 2 (no restraints)
log_step "4. Running minimization (no restraints)..."
$MD_ENGINE -O \
    -i min2.in \
    -o min2.out \
    -p system.prmtop \
    -c min.rst7 \
    -r min2.rst7

if [[ $? -ne 0 ]]; then
    log_error "Minimization 2 failed! Check min2.out"
    exit 1
fi
log_success "Minimization 2 completed"

# Heating
log_step "5. Running heating (0 -> ${TEMPERATURE} K)..."
$MD_ENGINE -O \
    -i heat.in \
    -o heat.out \
    -p system.prmtop \
    -c min2.rst7 \
    -r heat.rst7 \
    -x heat.nc \
    -ref min2.rst7

if [[ $? -ne 0 ]]; then
    log_error "Heating failed! Check heat.out"
    exit 1
fi
log_success "Heating completed"

# Equilibration
log_step "6. Running equilibration (NPT, 500 ps)..."
$MD_ENGINE -O \
    -i equil.in \
    -o equil.out \
    -p system.prmtop \
    -c heat.rst7 \
    -r equil.rst7 \
    -x equil.nc \
    -ref heat.rst7

if [[ $? -ne 0 ]]; then
    log_error "Equilibration failed! Check equil.out"
    exit 1
fi
log_success "Equilibration completed"

# Production
log_step "7. Running production MD (NPT, ${SIM_TIME_NS} ns)..."
$MD_ENGINE -O \
    -i prod.in \
    -o prod.out \
    -p system.prmtop \
    -c equil.rst7 \
    -r prod.rst7 \
    -x prod.nc

if [[ $? -ne 0 ]]; then
    log_error "Production failed! Check prod.out"
    exit 1
fi
log_success "Production completed"

#==============================================================================
# Summary
#==============================================================================

echo ""
echo "=============================================="
echo "  MD Simulation Complete!"
echo "=============================================="
echo ""
echo "Output files in: $OUTPUT_DIR"
echo ""
echo "Key files:"
echo "  - system.prmtop    : Topology file"
echo "  - system.inpcrd    : Initial coordinates"
echo "  - prod.rst7        : Final restart file"
echo "  - prod.nc          : Production trajectory"
echo "  - prod.out         : Production output"
echo ""
echo "Analysis commands:"
echo "  # Load trajectory in cpptraj"
echo "  cpptraj -p system.prmtop -y prod.nc"
echo ""
echo "  # Calculate RMSD"
echo "  cpptraj << EOF"
echo "  parm system.prmtop"
echo "  trajin prod.nc"
echo "  rms first @CA out rmsd.dat"
echo "  run"
echo "  EOF"
echo ""
echo "  # Extract frames as PDB"
echo "  cpptraj -p system.prmtop -y prod.nc -x frames.pdb"
echo ""
