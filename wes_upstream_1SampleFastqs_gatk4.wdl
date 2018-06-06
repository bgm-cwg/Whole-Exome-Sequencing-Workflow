workflow wes 
{
      #RESOURCES SECTION
	  File dbSNP_vcf
	  File dbSNP_vcf_idx
	
	  String known_indels_sites_VCF
	  String known_indels_sites_idx
	  String ref_fasta
	
	  File ref_dict
	
	  #INPUT SECTION
	  File fastq1
	  File fastq2
	  String sampleName
	  
	  String base_name
	
	  #don't know about -p
	  String bwa_commandline="bwa mem -R '@RG\\tID:@HS2000\\tPL:ILLUMINA\\tLB:bgm_lib\\tSM:" + base_name + sampleName + "' -K 100000000 -v 3 -t $bwa_threads -Y $bash_ref_fasta"
	
	  File scattered_calling_intervals_list
	  Array[String] scattered_calling_intervals = read_lines(scattered_calling_intervals_list)
	
	  #Optimization flags
	  Int bwa_threads
	  Int samtools_threads
	
	  String tools
	  String res_dir  

	  call CreateSequenceGroupingTSV
	  {
	     input:
	       ref_dict = ref_dict
	  }
	  
	  call GetBwaVersion
	  {
	     input:
	       tools = tools
	  }
	
	  #String key_sampleName         =sampleName
	  #Pair[File, File] value_fastqs = (fastq1, fastq2)
      
	  call Fastq_to_uBAM
	  {
	     input:
		   tools                = tools,
		   fastq1               = fastq1,
		   fastq2               = fastq2,
		   sampleName           = base_name + sampleName,
		   output_uBAM_baseName = base_name + sampleName + ".u."
	  }
	
	  call SortSam_byQuery as Fastq_to_uBAM_sort
	  {
	     input:
	       input_bam           = Fastq_to_uBAM.uBAM,
	       output_bam_basename = "sorted_uBAM",
	       compressionLvl      = 2,
	       picard              = tools + "/picard.jar"
	  }
	  
	  call SamToFastqAndBwaMem 
	  {
	      input:
	        fastq1               = fastq1,
	        fastq2               = fastq2,
	        bwa_commandline      = bwa_commandline,
	        output_bam_basename  = base_name + "." + sampleName + ".unmerged",
	        ref_fasta            = ref_fasta,
	        
	        bwa_threads          = bwa_threads, 
	        samtools_threads     = samtools_threads,
	  	    tools                = tools,

	        java_heap_memory     = "3000m",	  
	        memory               = "14 GB",
	        cpu                  = bwa_threads
	  }
	
	  call SortSam_byQuery as sortAlignedBam
	  {
	     input:
	       input_bam           = SamToFastqAndBwaMem.output_bam,
	       output_bam_basename = base_name + "." + sampleName + ".sorted.aligned",
	       compressionLvl      = 2,
	       picard              = tools + "/picard.jar"
	  }
	
	  call MergeBamAlignment
	  {
	     input:
	       alignedBAM          = sortAlignedBam.output_bam,
	       uBAM                = Fastq_to_uBAM_sort.output_bam,
	       output_bam_basename = base_name + "." + sampleName + "merged.aligned",
	       ref_fasta           = ref_fasta,
	       bwa_version         = GetBwaVersion.version,
	       bwa_mem_commandline = bwa_commandline,
	       compressionLvl      = 2,
	       picard              = tools + "/picard.jar"
	  }
	
	  call Fix_RG_Header
	  {
	     input:
	       input_bam = MergeBamAlignment.output_bam,
	       samtools  = tools + "/samtools-1.8/samtools",
	       pyScript  = tools + "/test.py"
	  }
	
	  call SortSam_byQuery as sortMergedBam
	  {
	     input:
	       input_bam           = Fix_RG_Header.output_bam,
	       output_bam_basename = base_name + "." + sampleName + ".sorted.merged.aligned",
	       compressionLvl      = 2,
	       picard              = tools + "/picard.jar"
	  }
  
	  call MarkDuplicates 
	  {
	     input:
	       input_bams           = sortMergedBam.output_bam,
	       output_bam_basename  = base_name + "." + sampleName + ".aligned.unsorted.duplicates_marked",
	       metrics_filename     = "duplicate_metrics",
	       compressionLvl       = 2,
	       picard               = tools + "/picard.jar"
	  }
	
	  call SortAndFixTags as SortAndFixSampleBam
	  {
	    input:
	      input_bam                 = MarkDuplicates.output_bam,
	      output_bam_basename       = base_name + "." + sampleName + ".aligned.duplicate_marked.sorted",
	      ref_fasta                 = ref_fasta,
	      tools                     = tools,
	      sort_java_heap_memory     = "4000m",
	      fix_tags_java_heap_memory = "4000m",
	      memory                    = "4 GB",
	      cpu                       = 16
	  }

	  scatter (subgroup in CreateSequenceGroupingTSV.sequence_grouping)
	  {
	     call BaseRecalibrator 
	     {
	        input:
	          input_bam                     = SortAndFixSampleBam.output_bam,
	          input_bam_index               = SortAndFixSampleBam.output_bam_index,
	          recalibration_report_filename = base_name + "." + sampleName + ".recal_data.csv",
	          sequence_group_interval       = subgroup,
	          dbSNP_vcf                     = dbSNP_vcf,
	          dbSNP_vcf_idx                 = dbSNP_vcf_idx,
	          known_indels_sites_VCF        = known_indels_sites_VCF,
	          known_indels_sites_idx        = known_indels_sites_idx,
	          ref_dict                      = ref_dict,
	          ref_fasta                     = ref_fasta,
	          gatk_launch                   = tools + "/gatk-4.0.3.0/gatk"
	     }
	  }
	
	  call GatherBqsrReports
	  {
	    input:
	      input_bqsr_reports     = BaseRecalibrator.recalibration_report,
	      output_report_filename = base_name + "." + sampleName + ".recal_data.csv",
	      tools                  = tools
	  }
	
	  scatter (subgroup in CreateSequenceGroupingTSV.sequence_grouping_with_unmapped)
	  {
	    call ApplyBQSR
	    {
	      input:
	        input_bam               = SortAndFixSampleBam.output_bam,
	        #input_bam_index        = SortAndFixSampleBam.output_bam_index,
	        output_bam_basename     = base_name + "." + sampleName + ".aligned.duplicates_marked.recalibrated",
	        recalibration_report    = GatherBqsrReports.output_bqsr_report,
	        sequence_group_interval = subgroup,
	        ref_fasta               = ref_fasta,
	        compression_level       = 2,
		    tools                   = tools
	    }
	  }
	
	  call GatherBamFiles
	  {
	    input:
	      input_bams          = ApplyBQSR.recalibrated_bam,
	      output_bam_basename = base_name + "." + sampleName + ".gathered",
	      tools               = tools,
          sampleName          = base_name + sampleName,
	      cpu                 = 3,
          res_dir             = res_dir,
	      java_heap_memory    = "6000m",
	      memory              = "6500MB"
	   }
	
	  scatter (subInterval in scattered_calling_intervals)
	  {
	     call HaplotypeCaller
	     {
	      input:
	        input_bam        = GatherBamFiles.output_bam,
	        input_bam_index  = GatherBamFiles.output_bam_index,
	        interval_list    = subInterval,
	        interval_padding = 100,
	        gvcf_basename    = subInterval + ".g",
	        ref_fasta        = ref_fasta,
            res_dir          = res_dir + "/" + base_name + sampleName,
		    tools            = tools,
	        memory           = "12GB",
	        cpu              = 2
	     }
	  }
	  
	  output
	  {
	     Array[File] gvcfs = HaplotypeCaller.output_gvcf
	     Array[File] gvcfs_idx = HaplotypeCaller.output_gvcf_index
	  } 
}


task HaplotypeCaller
{ 
  String tools
  String input_bam
  String input_bam_index
  String interval_list
  Int interval_padding
  String gvcf_basename
  String ref_fasta
  
  String res_dir

  String memory
  Int cpu
  
  command
  {
    ${tools}/gatk-4.0.3.0/gatk --java-options "-Xms8g -XX:GCTimeLimit=50 -XX:GCHeapFreeLimit=10 -XX:ParallelGCThreads=2" HaplotypeCaller \
      -R ${ref_fasta} \
      -O ${gvcf_basename}.vcf \
      -I ${input_bam} \
      -L ${interval_list} \
      -ip ${interval_padding} \
      -ERC GVCF \
      --max-alternate-alleles 3 \
      -RF OverclippedReadFilter \
      --smith-waterman FASTEST_AVAILABLE \
      --native-pair-hmm-use-double-precision true


    sed -i 's/ID=AD,Number=R/ID=AD,Number=\./g' ${gvcf_basename}.vcf

    cp ${gvcf_basename}.vcf ${gvcf_basename}vcf
    bgzip ${gvcf_basename}vcf
    tabix -p vcf ${gvcf_basename}vcf.gz

    mv ${gvcf_basename}vcf.gz ${res_dir}
    mv ${gvcf_basename}vcf.gz.tbi ${res_dir}
  }

  runtime
  {
     memory: memory
     cpu: cpu
  }

  output
  {
     File output_gvcf = "${gvcf_basename}.vcf"
     File output_gvcf_index = "${gvcf_basename}.vcf.idx"
  }
}

task GatherBamFiles
{
  Array[File] input_bams
  String res_dir
  String output_bam_basename
  String java_heap_memory
  String sampleName
  String memory
  Int cpu
  String tools  

  command
  {
    java -Xmx${java_heap_memory} -Xms2000m -XX:ParallelGCThreads=2  -jar ${tools}/picard.jar \
      GatherBamFiles \
      INPUT=${sep=' INPUT=' input_bams} \
      OUTPUT=${output_bam_basename}.bam \
      CREATE_INDEX=false \
      CREATE_MD5_FILE=true

      ${tools}/samtools-1.8/samtools view -H ${output_bam_basename}.bam | sed "s/SM:[^\t]*/SM:${sampleName}/g" | samtools reheader - ${output_bam_basename}.bam > ${output_bam_basename}_fixed.bam
      ${tools}/samtools-1.8/samtools index ${output_bam_basename}_fixed.bam


      cp ${output_bam_basename}_fixed.bam ${sampleName}.recal.realign.dedup.bam
      cp ${output_bam_basename}_fixed.bam.bai ${sampleName}.recal.realign.dedup.bam.bai
      mv ${sampleName}.recal.realign.dedup.bam ${res_dir}
      mv ${sampleName}.recal.realign.dedup.bam.bai ${res_dir}
  }

  runtime
  {
    memory: memory
    cpu: cpu
  }

  output
  {
    File output_bam       = "${output_bam_basename}_fixed.bam"
    File output_bam_index = "${output_bam_basename}_fixed.bam.bai"
  }
}

task Fastq_to_uBAM
{
   File fastq1
   File fastq2

   String sampleName
   String output_uBAM_baseName

   String tools 

   command
   {
     java -XX:ParallelGCThreads=1 -Xmx8G -jar ${tools}/picard.jar FastqToSam \
     FASTQ=${fastq1} \
     FASTQ2=${fastq2} \
     OUTPUT=${output_uBAM_baseName}.bam \
     READ_GROUP_NAME=${sampleName} \
     SAMPLE_NAME=${sampleName} \
     LIBRARY_NAME=Lib_A
   }

   runtime
   {
      memory: "8 GB"
      cpu: 3
   }

   output
   {
      File uBAM = "${output_uBAM_baseName}.bam" 
   }
}



# Get version of BWA
task GetBwaVersion
{
  String tools
  command 
  {
    # Not setting "set -o pipefail" here because /bwa has a rc=1 and we don't want to allow rc=1 to succeed 
    # because the sed may also fail with that error and that is something we actually want to fail on.
    ${tools}/bwa/bwa-0.7.17/bwa 2>&1 | \
    grep -e '^Version' | \
    sed 's/Version: //'
  }
  runtime 
  {
    memory: "100 MB"
    cpu: 1
  }

  output 
  {
    String version = read_string(stdout())
  }
}


task SamToFastqAndBwaMem
{
  File fastq1
  File fastq2

  String bwa_commandline
  String output_bam_basename

  String ref_fasta
  #File ref_fasta_index
  #File ref_dict

  Int bwa_threads
  Int samtools_threads

  String java_heap_memory
  String tools
  
  String memory
  Int cpu 
  

  command
  {
    set -o pipefail
    set -e

    # set the bash variable needed for the command-line
    bash_ref_fasta=${ref_fasta}
    bwa_threads=${bwa_threads}
    
    ${tools}/bwa/bwa-0.7.17/${bwa_commandline} ${fastq1} ${fastq2} | \
    ${tools}/samtools-1.8/samtools view -1 -@ ${samtools_threads} - > ${output_bam_basename}.bam 2>> bwa_err.log
  }

  runtime
  {
    memory: memory
    cpu: cpu
  }

  output 
  {
    File output_bam     = "${output_bam_basename}.bam"
    File bwa_stderr_log = "bwa_err.log"
  }
}

task SortSam_byQuery
{
  File input_bam
  String output_bam_basename
  Int compressionLvl
  String picard

  command
  {
     java -Dsamjdk.compression_level=${compressionLvl} -Xms4000m -XX:ParallelGCThreads=2 -jar ${picard} \
     SortSam \
     INPUT=${input_bam} \
     OUTPUT=${output_bam_basename}.bam \
     SORT_ORDER="queryname" \
     CREATE_INDEX=true \
     CREATE_MD5_FILE=true \
     MAX_RECORDS_IN_RAM=800000
  }

  runtime 
  {
    cpu: 3
    memory: "10000 MB"
  }

  output
  {
    File output_bam     = "${output_bam_basename}.bam"
    File output_bam_md5 = "${output_bam_basename}.bam.md5"
  }
}

task BwaMem 
{
  File fastq1
  File fastq2

  String bwa_mem_commandline
  String samTools
  String bwa_version
  
  String output_bam_basename

  String ref_fasta
  
  command 
  {
      set -o pipefail
      set -e

      bash_ref_fasta=${ref_fasta}
      bash_fastq1=${fastq1}
      bash_fastq2=${fastq2}

      ${bwa_mem_commandline} | ${samTools} view -@ 16 -Sbhu - > ${output_bam_basename}.bam 2>> bwa_err.log
      #${bwa_mem_commandline} | ${samTools} sort -n -@16 -O BAM -o ${output_bam_basename}.bam - > ${output_bam_basename}.log 2>> bwa_err.log 
  }

  runtime
  {
     cpu: 16
  }

  output
  {
     File alignedBAM = "${output_bam_basename}.bam"
  }
}

task MergeBamAlignment
{
   File alignedBAM
   File uBAM
   String output_bam_basename
   String ref_fasta
   String bwa_version
   String bwa_mem_commandline
   Int compressionLvl
   String picard   

   command
   {   
      java -XX:ParallelGCThreads=2 -Dsamjdk.compression_level=${compressionLvl} -Xms3000m -jar ${picard} \
      MergeBamAlignment \
      VALIDATION_STRINGENCY=SILENT \
      EXPECTED_ORIENTATIONS=FR \
      ATTRIBUTES_TO_RETAIN=X0 \
      ATTRIBUTES_TO_REMOVE=NM \
      ATTRIBUTES_TO_REMOVE=MD \
      ALIGNED_BAM=${alignedBAM} \
      UNMAPPED_BAM=${uBAM} \
      OUTPUT=${output_bam_basename}.bam \
      REFERENCE_SEQUENCE=${ref_fasta} \
      PAIRED_RUN=true \
      SORT_ORDER="unsorted" \
      IS_BISULFITE_SEQUENCE=false \
      ALIGNED_READS_ONLY=false \
      CLIP_ADAPTERS=false \
      MAX_RECORDS_IN_RAM=2000000 \
      ADD_MATE_CIGAR=true \
      MAX_INSERTIONS_OR_DELETIONS=-1 \
      PRIMARY_ALIGNMENT_STRATEGY=MostDistant \
      PROGRAM_RECORD_ID="bwamem" \
      PROGRAM_GROUP_VERSION="${bwa_version}" \
      PROGRAM_GROUP_COMMAND_LINE="${bwa_mem_commandline}" \
      PROGRAM_GROUP_NAME="bwamem" \
      UNMAPPED_READ_STRATEGY=COPY_TO_TAG \
      ALIGNER_PROPER_PAIR_FLAGS=true \
      UNMAP_CONTAMINANT_READS=true \
      ADD_PG_TAG_TO_READS=false
   }

   runtime
   {
      cpu: 3
      memory: "3200 MB"
   }

   output
   {
      File output_bam = "${output_bam_basename}.bam"
   }
  
}

task MarkDuplicates
{
   Array[File] input_bams
   String output_bam_basename
   String metrics_filename
   Int compressionLvl
   String picard

   command
   {
      java -Dsamjdk.compression_level=${compressionLvl} -Xms4000m -XX:ParallelGCThreads=2 -jar ${picard} \
      MarkDuplicates \
      INPUT=${sep=' INPUT=' input_bams} \
      OUTPUT=${output_bam_basename}.bam \
      METRICS_FILE=${metrics_filename} \
      VALIDATION_STRINGENCY=SILENT \
      OPTICAL_DUPLICATE_PIXEL_DISTANCE=2500 \
      ASSUME_SORT_ORDER="queryname" \
      CREATE_MD5_FILE=true
   }

   runtime
   {
      cpu: 3
      memory: "4200 MB"
   }

  output
  {
     File output_bam        = "${output_bam_basename}.bam"
     File duplicate_metrics = "${metrics_filename}"
  }
}

task CreateSequenceGroupingTSV 
{
  File ref_dict

  # Use python to create the Sequencing Groupings used for BQSR and PrintReads Scatter.
  # It outputs to stdout where it is parsed into a wdl Array[Array[String]]
  # e.g. [["1"], ["2"], ["3", "4"], ["5"], ["6", "7", "8"]]
  command <<<
    python <<CODE
    with open("${ref_dict}", "r") as ref_dict_file:
        sequence_tuple_list = []
        longest_sequence = 0
        for line in ref_dict_file:
            if line.startswith("@SQ"):
                line_split = line.split("\t")
                # (Sequence_Name, Sequence_Length)
                sequence_tuple_list.append((line_split[1].split("SN:")[1], int(line_split[2].split("LN:")[1])))
        longest_sequence = sorted(sequence_tuple_list, key=lambda x: x[1], reverse=True)[0][1]
    # We are adding this to the intervals because hg38 has contigs named with embedded colons and a bug in GATK strips off
    # the last element after a :, so we add this as a sacrificial element.
    # hg38_protection_tag = ":1+"
    # initialize the tsv string with the first sequence

    hg38_protection_tag = "" #hg19 not need it?    

    tsv_string = sequence_tuple_list[0][0] + hg38_protection_tag
    temp_size = sequence_tuple_list[0][1]
    for sequence_tuple in sequence_tuple_list[1:]:
        if temp_size + sequence_tuple[1] <= longest_sequence:
            temp_size += sequence_tuple[1]
            tsv_string += "\t" + sequence_tuple[0] + hg38_protection_tag
        else:
            tsv_string += "\n" + sequence_tuple[0] + hg38_protection_tag
            temp_size = sequence_tuple[1]
    # add the unmapped sequences as a separate line to ensure that they are recalibrated as well
    with open("sequence_grouping.txt","w") as tsv_file:
      tsv_file.write(tsv_string)
      tsv_file.close()

    tsv_string += '\n' + "unmapped"

    with open("sequence_grouping_with_unmapped.txt","w") as tsv_file_with_unmapped:
      tsv_file_with_unmapped.write(tsv_string)
      tsv_file_with_unmapped.close()
    CODE
  >>>

  runtime
  {
    memory: "100 MB"
    cpu: 1
  }

  output 
  {
    Array[Array[String]] sequence_grouping               = read_tsv("sequence_grouping.txt")
    Array[Array[String]] sequence_grouping_with_unmapped = read_tsv("sequence_grouping_with_unmapped.txt")
  }
}

task BaseRecalibrator 
{
  String input_bam
  File input_bam_index
  String recalibration_report_filename
  Array[String] sequence_group_interval

  File dbSNP_vcf
  File dbSNP_vcf_idx

  File known_indels_sites_VCF
  File known_indels_sites_idx

  File ref_dict
  String ref_fasta

  String gatk_launch

  command 
  {
    ${gatk_launch} --java-options "-XX:ParallelGCThreads=1" IndexFeatureFile -F ${input_bam}

    ${gatk_launch} --java-options "-XX:GCTimeLimit=50 -XX:GCHeapFreeLimit=10 -XX:+PrintFlagsFinal \
      -XX:+PrintGCTimeStamps -XX:+PrintGCDateStamps -XX:+PrintGCDetails \
      -Xloggc:gc_log.log -Xms4000m -XX:ParallelGCThreads=2" \
      BaseRecalibrator \
      -R ${ref_fasta} \
      -I ${input_bam} \
      -OQ \
      -O ${recalibration_report_filename} \
      -known-sites ${dbSNP_vcf} \
      -known-sites ${known_indels_sites_VCF} \
      -L ${sep=" -L " sequence_group_interval}
  }
  runtime 
  {
    memory: "4 GB"
    cpu: 3
  }

  output 
  {
    File recalibration_report = "${recalibration_report_filename}"
  }
}

task Fix_RG_Header
{
   File input_bam
   String pyScript
   String samtools

   command
   {
      python ${pyScript} -H -i ${input_bam} -o - | ${samtools} reheader - ${input_bam} > fixed.bam
   }

   output
   {
      File output_bam = "fixed.bam"
   }
}

task SortAndFixTags
{
  File input_bam
  String output_bam_basename
  String ref_fasta
  String sort_java_heap_memory
  String fix_tags_java_heap_memory
  String memory
  Int cpu
  String tools
  
  command
  {
    set -o pipefail
    
    ${tools}/samtools-1.8/samtools sort -l 2 -n -@16 -O BAM -o ${input_bam}.sorted.bam

    java -Xmx${fix_tags_java_heap_memory} -XX:ParallelGCThreads=2 -jar ${tools}/picard.jar \
    SetNmAndUqTags \
    INPUT=${input_bam}.sorted.bam \
    OUTPUT=${output_bam_basename}.bam \
    CREATE_INDEX=true \
    CREATE_MD5_FILE=true \
    REFERENCE_SEQUENCE=${ref_fasta}
  }

  runtime
  {
    memory: memory
    cpu: cpu
  }

  output
  {
    File output_bam       = "${output_bam_basename}.bam"
    File output_bam_index = "${output_bam_basename}.bai"
    File output_bam_md5   = "${output_bam_basename}.bam.md5"
  }
}


task GatherBqsrReports 
{
  Array[File] input_bqsr_reports
  String output_report_filename
  String tools
  
  command
  {
      ${tools}/gatk-4.0.3.0/gatk --java-options "-Xms3000m -XX:ParallelGCThreads=2"  GatherBQSRReports \
      -I ${sep=' -I ' input_bqsr_reports} \
      -O ${output_report_filename} 
  }

  runtime 
  {
    memory: "3500 MB"
    cpu: 3
  }

  output
  {
    File output_bqsr_report = "${output_report_filename}"
  }
}

task ApplyBQSR
{
  String input_bam
  String output_bam_basename
  File recalibration_report
  Array[String] sequence_group_interval
  String ref_fasta
 
  Int compression_level
  String tools

  command 
  {
    ${tools}/gatk-4.0.3.0/gatk --java-options "-XX:+PrintFlagsFinal -XX:+PrintGCTimeStamps -XX:+PrintGCDateStamps \
      -XX:+PrintGCDetails -Xloggc:gc_log.log \
      -XX:GCTimeLimit=50 -XX:GCHeapFreeLimit=10 -Dsamjdk.compression_level=${compression_level} -Xms3000m -XX:ParallelGCThreads=2" \
      ApplyBQSR \
      -OBM \
      -R ${ref_fasta} \
      -I ${input_bam} \
      -OQ \
      -O ${output_bam_basename}.bam \
      -bqsr ${recalibration_report} \
      --static-quantized-quals 10 --static-quantized-quals 20 --static-quantized-quals 30 \
      -L ${sep=" -L " sequence_group_interval}
  }

  runtime
  {
    memory: "3500 MB"
    cpu: 3
  }

  output
  {
    File recalibrated_bam          = "${output_bam_basename}.bam"
    File recalibrated_bam_checksum = "${output_bam_basename}.bam.md5"
  }
}



