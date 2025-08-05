#!/bin/bash

set -euo pipefail

infile=${1}
outdir=${2}
threads=${3}
k=${4}
ci=${5}
max_secondary_alns=${6}
ignore_minimizers_n=${7}
aln_bandwidth=${8}
bn_srf=${9}
script_utils=${10}
bn_trf=${11}

fname=$(basename "${infile%%.*}")
outdir_ctg="${outdir}/${fname}"
seq="${outdir_ctg}/${fname}.fa"

if [[ ${infile} == *fasta.gz || ${infile} == *fa.gz ]]; then
    mkdir -p "${outdir_ctg}"
    zcat ${infile} > ${seq}
elif [[ ${infile} == *.fasta || ${infile} == *.fa ]]; then
    mkdir -p "${outdir_ctg}"
    ln -s $(realpath ${infile}) ${seq} || true
else
    exit 0
fi

tmp_dir="${outdir_ctg}/temp"
kmer_counts="${outdir_ctg}/count.txt"
motifs="${outdir_ctg}/srf.fa"
monomers="${outdir_ctg}/trf_monomers.tsv"
paf="${outdir_ctg}/srf.paf"
bed="${outdir_ctg}/srf.bed"

mkdir -p "${tmp_dir}"
kmc -fm -k${k} -t${threads} \
    -ci${ci} -cs100_000 \
    "${seq}" "${outdir_ctg}" "${tmp_dir}"
kmc_tools transform "${outdir_ctg}" dump "${kmer_counts}"
rmdir "${tmp_dir}"

# Get HORs
{ ./${bn_srf} -p prefix ${kmer_counts} || true ;} > "${motifs}"
# Remove any core dumps, kmer counts, and kmc databases.
rm -f core* "${kmer_counts}" ${outdir_ctg}.kmc_*

# Get monomers with trf
if [ -s "${motifs}" ]; then
    ./${bn_trf} "${motifs}" | \
    awk -v FNAME="${fname}" -v OFS="\t" '{{ print $0, FNAME }}' > "${monomers}"
fi
touch ${monomers}

# Enlong and map to seq.
minimap2 -c \
    --eqx \
    -N ${max_secondary_alns} \
    -f ${ignore_minimizers_n} \
    -r ${aln_bandwidth} \
    -t ${threads} \
    <(./${script_utils} enlong ${motifs}) ${seq} > "${paf}"

{ ./${script_utils} paf2bed ${paf} | sort -k 1,1 -k2,2n ;} > "${bed}"

rm -f ${seq}
