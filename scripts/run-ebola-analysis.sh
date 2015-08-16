#!/bin/bash

set -euo pipefail

# usage
if [[ $# -ne 1 ]]; then
	
	echo -e "\nUsage: $(basename $0) <aligner>"
	echo -e "Run ebola variant analysis"
	echo -e ""
	exit

fi

OPT=$1 # can be bwa or bwt

# set output dir
if [[ "$OPT" == "bwa" ]]; then
	DATA="projects/ebola/data-bwa"
elif [[ "$OPT" == "bwt" ]]; then
	DATA="projects/ebola/data-bwt"
else
	echo -e "Not an option for an aligner. Currenlty only 'bwa' and 'bwt'"
	exit 1
fi


# for each month and each replicate
for month in may jun aug; do

	for rep in 1 2; do

	echo -e "Downloading reads collected in $month rep $rep...\n"

		# download data for both reps
		sraid=$(cat $DATA/$month/sraid_${rep}.txt)
		fastq-dump --split-files --gzip --outdir $DATA/${month}/ $sraid
		mv $DATA/$month/${sraid}_1.fastq.gz $DATA/$month/reads_1_${rep}.fastq.gz
		mv $DATA/$month/${sraid}_2.fastq.gz $DATA/$month/reads_2_${rep}.fastq.gz

	done

	echo -e "Analyzing reads collected in $month\n"

	# create qc reports
	parallel "fastqc -t 4 --nogroup $DATA/$month/reads_1_{}.fastq.gz" ::: 1 2
	parallel "unzip -o $DATA/$month/reads_1_{}_fastqc.zip -d $DATA/$month" ::: 1 2

	# trim reads
	parallel "trimmomatic PE -threads 4 -phred33 \
	$DATA/$month/reads_1_{}.fastq.gz $DATA/$month/reads_2_{}.fastq.gz \
	$DATA/$month/trimmed_1_{}.fastq.gz $DATA/$month/unpaired_1_{}.fastq.gz \
	$DATA/$month/trimmed_2_{}.fastq.gz $DATA/$month/unpaired_2_{}.fastq.gz \
	TRAILING:20 SLIDINGWINDOW:4:25 MINLEN:36 2> $DATA/$month/trim_{}.log" ::: 1 2

	# align reads
	if [[ $OPT == "bwa" ]]; then

		REF="refs/ebola-2014.fasta"

		parallel "bwa mem -t 4 $REF $DATA/$month/trimmed_1_{}.fastq.gz $DATA/$month/trimmed_2_{}.fastq.gz 2> $DATA/$month/aln_{}.log |
		samtools view -b - | \
		samtools sort -o - tmp > $DATA/$month/aln_{}.bam
		samtools index $DATA/$month/aln_{}.bam
		samtools flagstat $DATA/$month/aln_{}.bam > $DATA/$month/aln_{}.stats" ::: 1 2

		# call variants
		parallel "samtools mpileup -ugf $REF $DATA/$month/aln_{}.bam | bcftools call -cv > $DATA/$month/results_{}.vcf" ::: 1 2

		# convert to bed
		parallel "awk '! /\#/' $DATA/$month/results_{}.vcf | \
		awk '{if(length($$4) > length($$5)) print $$1\t($$2-1)\t($$2+length($$4)-1); else print $$1\t($$2-1)\t($$2+length($$5)-1)}' > $DATA/$month/variants_{}.bed" ::: 1 2

		# zip and index vcf files
		parallel "bgzip -f $DATA/$month/results_{}.vcf" ::: 1 2
		parallel "tabix -p vcf $DATA/$month/results_{}.vcf.gz" ::: 1 2
		parallel "bcftools stats -F $REF -s - $DATA/$month/results_{}.vcf.gz > $DATA/$month/results_{}.vcf.gz.stats" ::: 1 2
	
	elif [[ $OPT == "bwt" ]]; then

		REF="refs/ebola-2014"
	
		parallel "bowtie2 --threads 4 --local -x $REF -1 $DATA/$month/trimmed_1_{}.fastq.gz -2 $DATA/$month/trimmed_2_{}.fastq.gz 2> $DATA/$month/aln_{}.log |
		samtools view -b - | \
		samtools sort -o - tmp > $DATA/$month/aln_{}.bam
		samtools index $DATA/$month/aln_{}.bam
		samtools flagstat $DATA/$month/aln_{}.bam > $DATA/$month/aln_{}.stats" ::: 1 2

		# call variants
		parallel "samtools mpileup -ugf $REF.fasta $DATA/$month/aln_{}.bam | bcftools call -cv > $DATA/$month/results_{}.vcf" ::: 1 2

		# convert to bed
		parallel "awk '! /\#/' $DATA/$month/results_{}.vcf | \
		awk '{if(length($$4) > length($$5)) print $$1\t($$2-1)\t($$2+length($$4)-1); else print $$1\t($$2-1)\t($$2+length($$5)-1)}' > $DATA/$month/variants_{}.bed" ::: 1 2

		# zip and index vcf files
		parallel "bgzip -f $DATA/$month/results_{}.vcf" ::: 1 2
		parallel "tabix -p vcf $DATA/$month/results_{}.vcf.gz" ::: 1 2
		parallel "bcftools stats -F $REF.fasta -s - $DATA/$month/results_{}.vcf.gz > $DATA/$month/results_{}.vcf.gz.stats" ::: 1 2

	fi

	# concatenate bam files
	samtools cat $DATA/$month/aln_1.bam $DATA/$month/aln_2.bam | samtools sort -o - tmp > $DATA/$month/aln.bam
	samtools index $DATA/$month/aln.bam
	samtools flagstat $DATA/$month/aln.bam > $DATA/$month/aln.stats

done
