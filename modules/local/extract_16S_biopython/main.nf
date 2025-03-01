process EXTRACT_16S_BIOPYTHON {

    // errorStrategy 'terminate'

    publishDir "${params.process_log_dir}",
        mode: "${params.publish_dir_mode}",
        pattern: ".command.*",
        saveAs: { filename -> "${base}.${task.process}${filename}"}

    tag { "${base}" }
    
    container "gregorysprenger/biopython@sha256:77a50d5d901709923936af92a0b141d22867e3556ef4a99c7009a5e7e0101cc1"

    input:
        tuple val(base), path(annotation), path(qc_annotated_filecheck), path(base_fna)

    output:
        tuple val(base), path("16S.${base}.fa"), emit: extracted_rna
        path ".command.out"
        path ".command.err"
        path "versions.yml", emit: versions

    shell:
        '''
        source bash_functions.sh

        # Exit if previous process fails qc filecheck
        for filecheck in !{qc_annotated_filecheck}; do
          if [[ $(grep "FAIL" ${filecheck}) ]]; then
            error_message=$(awk -F '\t' 'END {print $2}' ${filecheck} | sed 's/[(].*[)] //g')
            msg "${error_message} Check FAILED" >&2
            exit 1
          else
            rm ${filecheck}
          fi
        done

        # Get extract.record.from.genbank.py and check if it exists
        extract_record_script="${DIR}/extract.record.from.genbank.py"
        if ! check_if_file_exists_allow_seconds ${extract_record_script} '60'; then
          exit 1
        fi

        # 16S extraction
        if [[ -s "!{annotation}" ]]; then
          python ${extract_record_script} \
           -i "!{annotation}" \
           -u !{params.genbank_query_qualifier} \
           -o "16S.!{base}.fa" \
           -q "!{params.genbank_query}" \
           --search-type !{params.genbank_search_type} \
           -f !{params.genbank_query_feature}
        fi

        # Get process version
        cat <<-END_VERSIONS > versions.yml
        "!{task.process} (!{base})":
            python: $(python --version 2>&1 | awk '{print $2}')
            biopython: $(python -c 'import Bio; print(Bio.__version__)' 2>&1)
        END_VERSIONS
        '''
}