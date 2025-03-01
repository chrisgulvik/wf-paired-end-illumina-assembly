process ANNOTATE_PROKKA {

    // errorStrategy 'terminate'

    publishDir "${params.outpath}/annot",
        mode: "${params.publish_dir_mode}",
        pattern: "*.gbk"
    publishDir "${params.qc_filecheck_log_dir}",
        mode: "${params.publish_dir_mode}",
        pattern: "*.Annotated_GenBank_File.tsv"
    publishDir "${params.process_log_dir}",
        mode: "${params.publish_dir_mode}",
        pattern: ".command.*",
        saveAs: { filename -> "${base}.${task.process}${filename}"}

    label "process_high"
    tag { "${base}" }

    container "snads/prokka@sha256:ef7ee0835819dbb35cf69d1a2c41c5060691e71f9138288dd79d4922fa6d0050"

    input:
        tuple val(base), path(paired_bam), path(single_bam), path(qc_assembly_filecheck), path(base_fna)

    output:
        tuple val(base), path("${base}.gbk"), path("*File*.tsv"), emit: annotation
        path "${base}.Annotated_GenBank_File.tsv", emit: qc_annotated_filecheck
        path ".command.out"
        path ".command.err"
        path "versions.yml", emit: versions

    shell:
        '''
        source bash_functions.sh

        # Exit if previous process fails qc filecheck
        for filecheck in !{qc_assembly_filecheck}; do
          if [[ $(grep "FAIL" ${filecheck}) ]]; then
            error_message=$(awk -F '\t' 'END {print $2}' ${filecheck} | sed 's/[(].*[)] //g')
            msg "${error_message} Check FAILED" >&2
            exit 1
          else
            rm ${filecheck}
          fi
        done
        
        # Remove seperator characters from basename for future processes
        short_base=$(echo !{base} | sed 's/[-._].*//g')
        sed -i "s/!{base}/${short_base}/g" !{base_fna}

        # Annotate cleaned and corrected assembly
        msg "INFO: Running prokka with !{task.cpus} threads"

        prokka \
         --outdir prokka \
         --prefix "!{base}"\
         --force \
         --addgenes \
         --locustag "!{base}" \
         --mincontiglen 1 \
         --evalue 1e-08 \
         --cpus !{task.cpus} \
         !{base_fna}

        for ext in gb gbf gbff gbk; do
          if [ -s "prokka/!{base}.${ext}" ]; then
            mv -f prokka/!{base}.${ext} !{base}.gbk
            break
          fi
        done

        if verify_minimum_file_size "!{base}.gbk" 'Annotated GenBank File' "!{params.min_filesize_annotated_genbank}"; then
          echo -e "!{base}\tAnnotated GenBank File\tPASS" \
           > !{base}.Annotated_GenBank_File.tsv
        else
          echo -e "!{base}\tAnnotated GenBank File\tFAIL" \
           > !{base}.Annotated_GenBank_File.tsv
        fi

        # Get process version
        cat <<-END_VERSIONS > versions.yml
        "!{task.process} (!{base})":
            prokka: $(prokka --version 2>&1 | awk 'NF>1{print $NF}')
        END_VERSIONS
        '''
}