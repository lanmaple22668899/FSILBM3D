#!/bin/bash
#SBATCH --job-name=case4-bb64
#SBATCH --partition=kshcnormal
#SBATCH --nodes=2
#SBATCH --ntasks=4
#SBATCH --ntasks-per-node=2
#SBATCH --cpus-per-task=16
#SBATCH --mem=8G
#SBATCH --output=slurm-%j.out

cd /public/home/liuyang2/LBM || exit 1
set -euo pipefail
root=/public/home/liuyang2/LBM
test "$(pwd -P)" = "$root"
case "${SLURM_SUBMIT_DIR:?}" in
    "$root"/case4_bounce_back_mpi64.*) ;;
    *) exit 1 ;;
esac
cd "${SLURM_SUBMIT_DIR#"$root"/}"
test "$(pwd -P)" = "$SLURM_SUBMIT_DIR"
base=$(pwd -P)
test "$SLURM_JOB_NUM_NODES" = 2
test "$SLURM_NTASKS" = 4
test "$SLURM_CPUS_PER_TASK" = 16

for path in inFlow.dat FSILBM3D_mpi; do
    test -f "$path" && test ! -L "$path" && test "$(stat -c %h "$path")" = 1 || exit 1
done
run="production-$SLURM_JOB_ID"
mkdir "$run"
cd "$run"
test "$(pwd -P)" = "$base/$run"
mkdir DatBody DatBodySpan DatFlow DatInfo DatContinue tmp
cp "$base/inFlow.dat" inFlow.dat

export OMP_NUM_THREADS="$SLURM_CPUS_PER_TASK"
export OMP_DYNAMIC=FALSE OMP_PLACES=cores OMP_PROC_BIND=close
export TMPDIR="$(pwd -P)/tmp"
export OMPI_MCA_orte_tmpdir_base="$TMPDIR"
export GFORTRAN_UNBUFFERED_ALL=1
mpirun -np "$SLURM_NTASKS" --map-by ppr:2:node:PE=16 --bind-to core --report-bindings \
    "$base/FSILBM3D_mpi" > run.log 2>&1
