#!/bin/bash
# From the repository root: bash examples/case4_3level_h025_mpi64/prepare.sh NEW_CASE_DIR
set -euo pipefail
dest=${1:?Supply a new case directory}
case_files=examples/case4_3level_h025_mpi64
solver=24d782235d044fdcaa03411fac2abb78cc5ab798
mkdir -- "$dest"
git archive "$solver" Makefile src tests/ibm_force_balance.f90 | tar -xf - -C "$dest"
cp -- "$case_files"/{inFlow.dat,cylinder.dat,submit.slurm,case4-runtime.patch} "$dest/"
cd -- "$dest"
git apply --no-index --unidiff-zero case4-runtime.patch
printf '%s\n' "$solver" > solver-commit.txt
sha256sum Makefile src/* tests/ibm_force_balance.f90 inFlow.dat cylinder.dat submit.slurm case4-runtime.patch solver-commit.txt > SHA256SUMS
