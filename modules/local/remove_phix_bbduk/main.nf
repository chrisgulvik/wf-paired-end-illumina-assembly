process REMOVE_PHIX_BBDUK {

    // errorStrategy 'terminate'

    publishDir "${params.outpath}/trim_reads",
        mode: "${params.publish_dir_mode}",
        pattern: "*.{raw,phix}.tsv"
    publishDir "${params.qc_filecheck_log_dir}",
        mode: "${params.publish_dir_mode}",
        pattern: "*.{PhiX_Genome_File,PhiX-removed_FastQ_Files}.tsv"
    publishDir "${params.process_log_dir}",
        mode: "${params.publish_dir_mode}",
        pattern: ".command.*",
        saveAs: { filename -> "${base}.${task.process}${filename}" }

    label "process_low"
    tag { "${base}" }
    
    container "snads/bbtools@sha256:9f2a9b08563839cec87d856f0fc7607c235f464296fd71e15906ea1d15254695"

    input:
        tuple val(base), path(input), path(qc_input_filecheck)

    output:
        tuple val(base), path("${base}_noPhiX-R1.fsq"), path("${base}_noPhiX-R2.fsq"), path("*File*.tsv"), emit: phix_removed
        path "${base}.PhiX_Genome_File.tsv", emit: qc_phix_genome_filecheck
        path "${base}.PhiX-removed_FastQ_Files.tsv", emit: qc_phix_removed_filecheck
        path "${base}.raw.tsv"
        path "${base}.phix.tsv"
        path ".command.out"
        path ".command.err"
        path "versions.yml", emit: versions

    shell:
        '''
        source bash_functions.sh
        
        # Exit if previous process fails qc filecheck
        for filecheck in !{qc_input_filecheck}; do
          if [[ $(grep "FAIL" ${filecheck}) ]]; then
            error_message=$(awk -F '\t' 'END {print $2}' ${filecheck} | sed 's/[(].*[)] //g')
            msg "${error_message} Check FAILED" >&2
            exit 1
          else
            rm ${filecheck}
          fi
        done

        # Get PhiX, check if it exists, and verify file size
        PHIX="${DIR}/PhiX_NC_001422.1.fasta"
        if ! check_if_file_exists_allow_seconds ${PHIX} '60'; then
          exit 1
        fi
        if verify_minimum_file_size ${PHIX} 'PhiX Genome' "!{params.min_filesize_phix_genome}"; then
          echo -e "!{base}\tPhiX Genome\tPASS" >> !{base}.PhiX_Genome_File.tsv
        else
          echo -e "!{base}\tPhiX Genome\tFAIL" >> !{base}.PhiX_Genome_File.tsv
        fi

        # Remove PhiX
        msg "INFO: Running bbduk with !{task.cpus} threads"
        
        bbduk.sh \
        threads=!{task.cpus} \
        k=31 \
        hdist=1 \
        ref="${PHIX}" \
        in="!{input[0]}" \
        in2="!{input[1]}" \
        out=!{base}_noPhiX-R1.fsq \
        out2=!{base}_noPhiX-R2.fsq \
        qin=auto \
        qout=33 \
        overwrite=t

        for suff in R1.fsq R2.fsq; do
          if verify_minimum_file_size "!{base}_noPhiX-${suff}" 'PhiX-removed FastQ Files' "!{params.min_filesize_fastq_phix_removed}"; then
            echo -e "!{base}\tPhiX-removed FastQ ($suff) File\tPASS" \
              >> !{base}.PhiX-removed_FastQ_Files.tsv
          else
            echo -e "!{base}\tPhiX-removed FastQ ($suff) File\tFAIL" \
              >> !{base}.PhiX-removed_FastQ_Files.tsv
          fi
        done

        TOT_READS=$(grep '^Input: ' .command.err | awk '{print $2}')
        TOT_BASES=$(grep '^Input: ' .command.err | awk '{print $4}')

        if [[ -z "${TOT_READS}" || -z "${TOT_BASES}" ]]; then
          msg 'ERROR: unable to parse input counts from bbduk log' >&2
          exit 1
        fi

        PHIX_READS=$(grep '^Contaminants: ' .command.err | awk '{print $2}' | sed 's/,//g')
        PHIX_BASES=$(grep '^Contaminants: ' .command.err | awk '{print $5}' | sed 's/,//g')

        msg "INFO: ${TOT_BASES} bp and $TOT_READS reads provided as raw input"
        msg "INFO: ${PHIX_BASES:-0} bp of PhiX were detected and removed in ${PHIX_READS:-0} reads"

        echo -e "!{base}\t${TOT_BASES} bp Raw\t${TOT_READS} reads Raw" \
        > !{base}.raw.tsv
        echo -e "!{base}\t${PHIX_BASES:-0} bp PhiX\t${PHIX_READS:-0} reads PhiX" \
        > !{base}.phix.tsv

        # Get process version
        cat <<-END_VERSIONS > versions.yml
        "!{task.process} (!{base})":
            bbduk: $(bbduk.sh --version 2>&1 | head -n 2 | tail -1 | awk 'NF>1{print $NF}')
        END_VERSIONS
        '''
}
