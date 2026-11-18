#!/bin/bash
#SBATCH --job-name=c4-rho64
#SBATCH --partition=kshcnormal
#SBATCH --nodes=2
#SBATCH --ntasks=4
#SBATCH --ntasks-per-node=2
#SBATCH --cpus-per-task=16
#SBATCH --mem=8G
#SBATCH --output=slurm-%j.out

cd /public/home/liuyang2/LBM && set -euo pipefail || exit 1
root=/public/home/liuyang2/LBM
test "$(pwd -P)" = "$root"
case "${SLURM_SUBMIT_DIR:?}" in
    "$root"/case4_rho_3level_h025_mpi64_*) ;;
    *) exit 1 ;;
esac
base=$SLURM_SUBMIT_DIR
test "$(realpath -- "$base")" = "$base"
cd -- "${base#"$root"/}"
for f in FSILBM3D_mpi inFlow.dat cylinder.dat; do
    test -f "$f" && test "$(realpath -- "$f")" = "$base/$f" && test "$(stat -c %h "$f")" = 1 || exit 1
done
test -x FSILBM3D_mpi
test "$SLURM_JOB_NUM_NODES:$SLURM_NTASKS:$SLURM_CPUS_PER_TASK" = 2:4:16
mode=${1:-production}
case "$mode" in smoke|production) ;; *) exit 1 ;; esac
run=$mode-$SLURM_JOB_ID
mkdir -- "$run"
cd -- "$run"
test "$(pwd -P)" = "$base/$run"
mkdir DatBody DatBodySpan DatFlow DatInfo DatContinue tmp
cp "$base/cylinder.dat" cylinder.dat
if [[ "$mode" = smoke ]]; then
    # Two coarse steps; write force history on both for the startup check.
    awk '/! endpoint 500/ {$1="0.0199"} /! timeFlowDelta,timeBodyDelta,timeInfoDelta/ {$3="0.01"} {print}' "$base/inFlow.dat" > inFlow.dat
else
    cp "$base/inFlow.dat" inFlow.dat
fi
export OMP_NUM_THREADS="$SLURM_CPUS_PER_TASK" OMP_DYNAMIC=FALSE OMP_PLACES=cores OMP_PROC_BIND=close
export TMPDIR="$PWD/tmp" OMPI_MCA_orte_tmpdir_base="$PWD/tmp" GFORTRAN_UNBUFFERED_ALL=1
printf 'job=%s mode=%s nodes=%s ranks=%s threads=%s directory=%s\n' "$SLURM_JOB_ID" "$mode" "$SLURM_JOB_NUM_NODES" "$SLURM_NTASKS" "$OMP_NUM_THREADS" "$PWD"
scontrol show hostnames "$SLURM_JOB_NODELIST"
mpirun -np "$SLURM_NTASKS" --map-by ppr:2:node:PE=16 --bind-to core --report-bindings "$base/FSILBM3D_mpi" > run.log 2>&1
test "$(grep -c '^ FIELDSTAT L2 u' run.log)" -eq 3
if [[ "$mode" = smoke ]]; then
    test "$(grep -c '^ Steps:' run.log)" -eq 2
    awk -F, 'NR==1 {next} {e=$1-(NR-1)*0.0025; if (NF!=11 || e < -1e-10 || e > 1e-10 || $2!=NR-1 || $3<1 || $3>100 || tolower($0) ~ /nan|inf/) bad=1} END {exit (NR!=9 || bad)}' DatInfo/IBM_iterations.csv
    awk '/ZONE/ {zones++; next} NF==6 {rows++; if (tolower($0) ~ /nan|inf/) bad=1} END {exit (zones!=2 || rows!=2 || bad)}' DatInfo/Group001_forces.dat
else
    awk '/^ Steps:/ {t=$NF} END {exit (t < 499.999 || t > 500.011)}' run.log
fi
