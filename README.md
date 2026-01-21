# Amber MCP

> Model Context Protocol server for Amber molecular dynamics simulation and analysis workflows

## Table of Contents
- [Overview](#overview)
- [Installation](#installation)
- [Local Usage (Scripts)](#local-usage-scripts)
- [MCP Server Installation](#mcp-server-installation)
- [Using with Claude Code](#using-with-claude-code)
- [Using with Gemini CLI](#using-with-gemini-cli)
- [Available Tools](#available-tools)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## Overview

This MCP server provides computational chemistry and molecular dynamics simulation capabilities based on AmberTools22/Amber22. It offers both standalone scripts and MCP tools for analyzing MD simulations, setting up free energy calculations, and configuring QM/MM calculations for enzyme-substrate complexes.

### Features
- [ ] **MD Trajectory Analysis**: Parse and analyze Amber .mdout files with energy plotting
- [ ] **PBSA Free Energy Setup**: Configure Poisson-Boltzmann Surface Area calculations
- [ ] **QM/MM Setup**: Prepare quantum mechanics/molecular mechanics calculations
- [ ] **Batch Processing**: Process multiple simulation files simultaneously
- [ ] **Job Management**: Submit and track long-running calculations
- [ ] **Configuration Management**: Flexible parameter control via JSON configs

### Directory Structure
```
./
├── README.md               # This file
├── requirements.txt        # Python dependencies
├── src/
│   └── server.py           # MCP server
├── scripts/
│   ├── md_analysis.py      # MD trajectory analysis
│   ├── pbsa_free_energy.py # PBSA setup and analysis
│   ├── qmmm_setup.py       # QM/MM calculation setup
│   └── lib/                # Shared utilities
│       ├── __init__.py     # Library initialization
│       ├── io.py           # File I/O utilities
│       └── utils.py        # General utilities
├── examples/
│   ├── use_case_*.py       # Example scripts
│   └── data/               # Demo data
│       └── sample.mdout    # Sample MD output file
├── configs/                # Configuration files
│   ├── md_analysis_config.json      # MD analysis settings
│   ├── pbsa_free_energy_config.json # PBSA calculation parameters
│   ├── qmmm_setup_config.json       # QM/MM setup parameters
│   └── default_config.json          # Common default settings
├── reports/                # Step documentation
└── repo/                   # Original Amber source
```

---

## Installation

### Prerequisites
- Conda or Mamba (mamba recommended for faster installation)
- Python 3.10+
- AmberTools22 (for full functionality)

### Create Environment
Please follow the environment setup procedure from `reports/step3_environment.md`. An example workflow is shown below.

```bash
# Navigate to the MCP directory
cd /mnt/data/done_projects/2026/ProteinMCP/ProteinMCP/tool-mcps/amber_mcp

# Create conda environment (use mamba if available)
# Check for package manager
if command -v mamba &> /dev/null; then
    PKG_MGR="mamba"
    mamba create -p ./env python=3.10 -y
    mamba activate ./env
else
    PKG_MGR="conda"
    conda create -p ./env python=3.10 -y
    conda activate ./env
fi
echo "Using package manager: $PKG_MGR"

# Install Dependencies
pip install -r requirements.txt

# Install MCP dependencies
pip install fastmcp loguru --ignore-installed
```

---

## Local Usage (Scripts)

You can use the scripts directly without MCP for local processing.

### Available Scripts

| Script | Description | Example |
|--------|-------------|---------|
| `scripts/md_analysis.py` | Analyze MD simulation output files | See below |
| `scripts/pbsa_free_energy.py` | Set up PBSA free energy calculations | See below |
| `scripts/qmmm_setup.py` | Set up QM/MM calculations | See below |

### Script Examples

#### MD Analysis

```bash
# Activate environment
mamba activate ./env

# Run script
python scripts/md_analysis.py \
  --input examples/data/sample.mdout \
  --output results/md_analysis \
  --csv
```

**Parameters:**
- `--input, -i`: Path to .mdout file from MD simulation (required)
- `--output, -o`: Output prefix for generated files (default: auto)
- `--csv`: Export data as CSV (optional)

#### PBSA Free Energy Setup

```bash
python scripts/pbsa_free_energy.py \
  --topology complex.prmtop \
  --trajectory trajectory.nc \
  --output pbsa_results
```

**Parameters:**
- `--topology, -t`: Path to .prmtop topology file (required)
- `--trajectory, -x`: Path to trajectory (.nc, .mdcrd) file (optional)
- `--output, -o`: Output directory (default: pbsa_output)

#### QM/MM Setup

```bash
python scripts/qmmm_setup.py \
  --topology enzyme_substrate.prmtop \
  --coordinates enzyme_substrate.rst7 \
  --qm-atoms ":100-105|:200" \
  --output qmmm_setup
```

**Parameters:**
- `--topology, -t`: Path to .prmtop topology file (required)
- `--coordinates, -c`: Path to coordinates (.rst7, .inpcrd) file (optional)
- `--qm-atoms`: Amber atom selection mask for QM region (optional)
- `--output, -o`: Output directory (default: qmmm_output)

---

## MCP Server Installation

### Option 1: Using fastmcp (Recommended)

```bash
# Install MCP server for Claude Code
fastmcp install src/server.py --name pmemd24_src
```

### Option 2: Manual Installation for Claude Code

```bash
# Add MCP server to Claude Code
claude mcp add pmemd24_src -- $(pwd)/env/bin/python $(pwd)/src/server.py

# Verify installation
claude mcp list
```

### Option 3: Configure in settings.json

Add to `~/.claude/settings.json`:

```json
{
  "mcpServers": {
    "pmemd24_src": {
      "command": "/mnt/data/done_projects/2026/ProteinMCP/ProteinMCP/tool-mcps/amber_mcp/env/bin/python",
      "args": ["/mnt/data/done_projects/2026/ProteinMCP/ProteinMCP/tool-mcps/amber_mcp/src/server.py"]
    }
  }
}
```

---

## Using with Claude Code

After installing the MCP server, you can use it directly in Claude Code.

### Quick Start

```bash
# Start Claude Code
claude
```

### Example Prompts

#### Tool Discovery
```
What tools are available from pmemd24_src?
```

#### Basic MD Analysis
```
Use analyze_md_trajectory with input_file @examples/data/sample.mdout
```

#### PBSA Setup with Configuration
```
Use setup_pbsa_calculation with topology_file @examples/complex.prmtop using config @configs/pbsa_free_energy_config.json
```

#### QM/MM Setup with Custom Parameters
```
Use setup_qmmm_calculation with topology_file @examples/enzyme.prmtop qm_atoms ":100-105|:200" qm_method "M06-2X"
```

#### Batch Processing
```
Use batch_analyze_md_trajectories with input_files ["@examples/data/rep1.mdout", "@examples/data/rep2.mdout", "@examples/data/rep3.mdout"]
```

#### Long-Running Tasks (Submit API)
```
Submit analyze_md_trajectory for @examples/data/large_trajectory.mdout
Then check the job status
```

### Using @ References

In Claude Code, use `@` to reference files and directories:

| Reference | Description |
|-----------|-------------|
| `@examples/data/sample.mdout` | Reference a specific MD output file |
| `@configs/md_analysis_config.json` | Reference a config file |
| `@results/` | Reference output directory |

---

## Using with Gemini CLI

### Configuration

Add to `~/.gemini/settings.json`:

```json
{
  "mcpServers": {
    "pmemd24_src": {
      "command": "/mnt/data/done_projects/2026/ProteinMCP/ProteinMCP/tool-mcps/amber_mcp/env/bin/python",
      "args": ["/mnt/data/done_projects/2026/ProteinMCP/ProteinMCP/tool-mcps/amber_mcp/src/server.py"]
    }
  }
}
```

### Example Prompts

```bash
# Start Gemini CLI
gemini

# Example prompts (same as Claude Code)
> What tools are available?
> Use analyze_md_trajectory with input_file examples/data/sample.mdout
```

---

## Available Tools

### Quick Operations (Sync API)

These tools return results immediately (< 10 minutes):

| Tool | Description | Parameters |
|------|-------------|------------|
| `analyze_md_trajectory` | Analyze MD simulation output files | `input_file`, `output_file`, `include_plots`, `save_csv`, `config_file` |
| `setup_pbsa_calculation` | Set up PBSA free energy calculations | `topology_file`, `trajectory_file`, `output_dir`, `ionic_strength`, `config_file` |
| `setup_qmmm_calculation` | Set up QM/MM calculations | `topology_file`, `coordinates_file`, `qm_atoms`, `qm_method`, `output_dir`, `config_file` |

### Long-Running Tasks (Submit API)

These tools return a job_id for tracking (> 10 minutes):

| Tool | Description | Parameters |
|------|-------------|------------|
| `submit_long_running_task` | Submit background calculations | `input_file`, `script_name`, `output_dir`, `job_name`, `**kwargs` |

### Batch Processing Tools

| Tool | Description | Parameters |
|------|-------------|------------|
| `batch_analyze_md_trajectories` | Process multiple MD files | `input_files`, `output_dir`, `include_plots`, `save_csv`, `config_file` |

### Job Management Tools

| Tool | Description |
|------|-------------|
| `get_job_status` | Check job progress |
| `get_job_result` | Get results when completed |
| `get_job_log` | View execution logs |
| `cancel_job` | Cancel running job |
| `list_jobs` | List all jobs |

### Utility Tools

| Tool | Description |
|------|-------------|
| `list_example_files` | List available test data |
| `get_tool_info` | Get comprehensive tool information |

---

## Examples

### Example 1: MD Trajectory Analysis

**Goal:** Analyze molecular dynamics simulation output to extract energy data and generate plots

**Using Script:**
```bash
python scripts/md_analysis.py \
  --input examples/data/sample.mdout \
  --output results/example1/ \
  --csv
```

**Using MCP (in Claude Code):**
```
Use analyze_md_trajectory to process @examples/data/sample.mdout and save results to results/example1/ with save_csv True
```

**Expected Output:**
- Energy plots (total energy and temperature vs time)
- CSV file with extracted energy data
- Summary statistics of energy components

### Example 2: PBSA Free Energy Setup

**Goal:** Set up PBSA free energy calculations for enzyme-substrate binding

**Using Script:**
```bash
python scripts/pbsa_free_energy.py \
  --topology complex.prmtop \
  --trajectory trajectory.nc \
  --output pbsa_analysis
```

**Using MCP (in Claude Code):**
```
Use setup_pbsa_calculation with topology_file @examples/complex.prmtop trajectory_file @examples/trajectory.nc output_dir "pbsa_analysis"
```

**Expected Output:**
- PBSA input file (pbsa.in)
- Topology decomposition script
- Analysis workflow scripts

### Example 3: QM/MM Calculation Setup

**Goal:** Set up QM/MM calculations for enzyme active site

**Using Script:**
```bash
python scripts/qmmm_setup.py \
  --topology enzyme.prmtop \
  --coordinates enzyme.rst7 \
  --qm-atoms ":100-105|:200" \
  --qm-method "B3LYP" \
  --output qmmm_setup
```

**Using MCP (in Claude Code):**
```
Use setup_qmmm_calculation with topology_file @examples/enzyme.prmtop coordinates_file @examples/enzyme.rst7 qm_atoms ":100-105|:200" qm_method "B3LYP"
```

**Expected Output:**
- QM/MM input file
- QM region selection script
- Analysis workflow scripts

### Example 4: Batch Processing

**Goal:** Process multiple simulation replicates at once

**Using Script:**
```bash
for f in examples/data/*.mdout; do
  python scripts/md_analysis.py --input "$f" --output results/batch/
done
```

**Using MCP (in Claude Code):**
```
Use batch_analyze_md_trajectories with input_files ["@examples/data/rep1.mdout", "@examples/data/rep2.mdout", "@examples/data/rep3.mdout"] output_dir "results/batch"
```

**Expected Output:**
- Individual analysis for each file
- Batch summary with success/failure statistics

---

## Demo Data

The `examples/data/` directory contains sample data for testing:

| File | Description | Use With |
|------|-------------|----------|
| `sample.mdout` | Sample Amber MD output (100 time steps) | `analyze_md_trajectory` |

---

## Configuration Files

The `configs/` directory contains configuration templates:

| Config | Description | Parameters |
|--------|-------------|------------|
| `md_analysis_config.json` | MD analysis settings | plot_dpi, figure_size, energy_components |
| `pbsa_free_energy_config.json` | PBSA calculation parameters | istrng, fillratio, radiopt, epsout |
| `qmmm_setup_config.json` | QM/MM setup parameters | qm_method, qm_charge, md_settings |
| `default_config.json` | Common default settings | output_format, log_level, amber_defaults |

### Config Example

```json
{
  "output_formats": ["png"],
  "plot_dpi": 300,
  "figure_size": [10, 6],
  "include_summary": true,
  "save_csv": false,
  "grid": true
}
```

---

## Troubleshooting

### Environment Issues

**Problem:** Environment not found
```bash
# Recreate environment
mamba create -p ./env python=3.10 -y
mamba activate ./env
pip install -r requirements.txt
```

**Problem:** Import errors
```bash
# Verify installation
python -c "from src.server import mcp"
```

### MCP Issues

**Problem:** Server not found in Claude Code
```bash
# Check MCP registration
claude mcp list

# Re-add if needed
claude mcp remove pmemd24_src
claude mcp add pmemd24_src -- $(pwd)/env/bin/python $(pwd)/src/server.py
```

**Problem:** Tools not working
```bash
# Test server directly
python -c "
from src.server import mcp
print(list(mcp.list_tools().keys()))
"
```

### Job Issues

**Problem:** Job stuck in pending
```bash
# Check job directory
ls -la jobs/

# View job log
cat jobs/<job_id>/job.log
```

**Problem:** Job failed
```
Use get_job_log with job_id "<job_id>" and tail 100 to see error details
```

### File Path Issues

**Problem:** File not found errors
- Ensure input files exist and paths are correct
- Use absolute paths when in doubt
- Check file permissions are readable

**Problem:** Permission denied errors
```bash
# Fix file permissions
chmod +r examples/data/*.mdout
chmod +w results/
```

---

## Development

### Running Tests

```bash
# Activate environment
mamba activate ./env

# Run tests
pytest tests/ -v
```

### Starting Dev Server

```bash
# Run MCP server in dev mode
fastmcp dev src/server.py
```

### Testing Tools

```bash
# Test tool discovery
python -c "from src.server import mcp; print(mcp.call_tool('get_tool_info', {}))"

# Test MD analysis with sample data
python -c "from src.server import mcp; print(mcp.call_tool('analyze_md_trajectory', {'input_file': 'examples/data/sample.mdout'}))"
```

---

## License

Based on AmberTools22/Amber22 molecular dynamics package

## Credits

Based on [Amber22/AmberTools22](https://ambermd.org/) molecular dynamics simulation software