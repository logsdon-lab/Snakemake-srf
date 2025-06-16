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
bn_srf_dir=${9}
bn_trf=${10}

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
    return 0
fi

tmp_dir="${outdir_ctg}/temp"
kmer_counts="${outdir_ctg}/count.txt"
motifs="${outdir_ctg}/srf.fa"
monomers="${outdir_ctg}/monomers.tsv"
paf="${outdir_ctg}/srf.paf"
bed="${outdir_ctg}/srf.bed"

mkdir -p "${tmp_dir}"
kmc -fm -k${k} -t${threads} \
    -ci${ci} -cs100_000 \
    "${seq}" "${outdir_ctg}" "${tmp_dir}"
kmc_tools transform "${outdir_ctg}" dump "${kmer_counts}"
rmdir "${tmp_dir}"

# Get HORs
{ ./${bn_srf_dir}/srf -p prefix ${kmer_counts} || true ;} > "${motifs}"
rm -f core*

# Get monomers with trf
if [ -s "${motifs}" ]; then
    ./${bn_trf} "${motifs}" | \
    awk -v FILENAME="${fname}" -v OFS="\t" '{{ print FILENAME, $0 }}' > "${monomers}"
fi
touch ${monomers}

# Enlong and map to seq.
minimap2 -c \
    -N ${max_secondary_alns} \
    -f ${ignore_minimizers_n} \
    -r ${aln_bandwidth} \
    -t ${threads} \
    <(./${bn_srf_dir}/srfutils.js enlong ${motifs}) ${seq} > "${paf}"
{ ./${bn_srf_dir}/srfutils.js paf2bed ${paf} | sort -k 1,1 -k2,2n ;} > "${bed}"

rm -f ${seq}
