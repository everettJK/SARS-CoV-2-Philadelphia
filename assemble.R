library(ShortRead)
library(tidyverse)
library(optparse)
library(genbankr)
library(GenomicRanges)

option_list = list(
  make_option(c("--softwareDir"), type="character", default='/home/common/SARS-CoV-2-Philadelphia', help="path to work directory", metavar="character"),
  make_option(c("--workDir"), type="character", default='/tmp', help="path to work directory", metavar="character"),
  make_option(c("--fgbioCommand"), type="character", default=NULL, help="fgbio command", metavar="character"),
  make_option(c("--fgbioTrimPrimerCoords"), type="character", default=NULL, help="fgbio primer trimming coords BED file", metavar="character"),
  make_option(c("--outputFile"), type="character", default='save.RData', help="path to output RData file", metavar="character"),
  make_option(c("--R1"), type="character", default=NULL, help="comma delimited list of R1 fastq files", metavar="character"),
  make_option(c("--R2"), type="character", default=NULL, help="comma delimited list of R2 fastq files", metavar="character"),
  
  make_option(c("--refGenomeFasta"), type="character", default='/home/common/SARS-CoV-2-Philadelphia/data/references/Wuhan-Hu-1.fasta', help="reference genome FASTA path", metavar="character"),   
  make_option(c("--refGenomeBWA"), type="character", default='/home/common/SARS-CoV-2-Philadelphia/data/references/Wuhan-Hu-1.fasta', help="path to ref genome BWA database", metavar="character"),   
  make_option(c("--refGenomeGenBank"), type="character", default='/home/common/SARS-CoV-2-Philadelphia/data/references/Wuhan-Hu-1.gb', help="path to ref genome genBank file", metavar="character"), 

  #make_option(c("--refGenomeFasta"), type="character", default='/home/common/SARS-CoV-2-Philadelphia/data/references/NC_045512.2.fasta', help="reference genome FASTA path", metavar="character"),   
  #make_option(c("--refGenomeBWA"), type="character", default='/home/common/SARS-CoV-2-Philadelphia/data/references/NC_045512.2.fasta', help="path to ref genome BWA database", metavar="character"),   
  #make_option(c("--refGenomeGenBank"), type="character", default='/home/common/SARS-CoV-2-Philadelphia/data/references/NC_045512.2.gb', help="path to ref genome genBank file", metavar="character"), 
  
  make_option(c("--minVariantPhredScore"), type="integer", default=20, help="minimum PHRED score allowed for called varinats", metavar="character"),
  make_option(c("--bwaPath"), type="character", default='/home/everett/ext/bwa', help="path to bwa binary", metavar="character"), 
  make_option(c("--megahitPath"), type="character", default='/home/everett/ext/megahit/bin/megahit', help="path to megahit binary", metavar="character"), 
  make_option(c("--minBWAmappingScore"), type="integer", default=30, help="minimum BWA mapping score", metavar="character"), 
  make_option(c("--minPangolinConf"), type="numeric", default=0.9, help="minimum pangolin confidence value (0-1)", metavar="character"), 
  make_option(c("--samtoolsBin"), type="character", default='/home/everett/ext/samtools/bin', help="path to samtools bin", metavar="character"), 
  make_option(c("--condaShellPath"), type="character", default='/home/everett/miniconda3/etc/profile.d/conda.sh', help="path to conda.sh", metavar="character"),
  make_option(c("--bcftoolsBin"), type="character", default='/home/everett/ext/bcftools/bin',  help="path to bcftools bin", metavar="character"),
  make_option(c("--aaa"), type="character", default=NULL,  help="aaa", metavar="character"),
  make_option(c("--trimQualCode"), type="character", default='5',  help="Min qual trim code", metavar="character"))

 
opt_parser = OptionParser(option_list=option_list)
opt = parse_args(opt_parser)


#Testing data
# opt$R1 <- '/media/lorax/data/SARS-CoV-2/sequencing/210628_Planet_random/VSP3001-1_S10_R1_001.fastq.gz'
# opt$R2 <- '/media/lorax/data/SARS-CoV-2/sequencing/210628_Planet_random/VSP3001-1_S10_R2_001.fastq.gz'
# opt$workDir <- '/home/common/SARS-CoV-2-Philadelphia/scratch/tmp.dev'
# opt$outputFile <- '/home/common/SARS-CoV-2-Philadelphia/summaries/dev.RData'
# opt$refGenomeBWA <- '/home/common/SARS-CoV-2-Philadelphia/data/references/NC_045512.2.fasta'
# opt$fgbioCommand <- 'java -jar /home/everett/miniconda3/envs/fgbio/share/fgbio/fgbio.jar'
# opt$fgbioTrimPrimerCoords <- '/home/common/SARS-CoV-2-Philadelphia/data/references/SARScoV2.FLEX.primer_info.tab'


source(paste0(opt$softwareDir, '/lib/assemble.lib.R'))

# Handle missing required parameters.
if(! 'R1' %in% names(opt)) stop('--R1 must be defined.')
if(! 'R2' %in% names(opt)) stop('--R2 must be defined.')


# Create work directory.
if(dir.exists(opt$workDir)) stop('Error -- work directory already exists')
dir.create(opt$workDir)
if(! dir.exists(opt$workDir)) stop('Error -- could not create the work directory.')


# Create table of software and R package version numbers.
opt$softwareVersionTable <- createSoftwareVersionTable()


# Define data structures which must be present even if empty for downstream analyses.
opt$errorCode <- 0
opt$errorMessage <- NA
opt$pangolinAssignment <- NA
opt$pangolinAssignmentConflict <- NA
opt$pangolinAssignmentPangoLEARN_version <- NA
opt$variantTable      <- data.frame()
opt$variantTableMajor <- data.frame()
opt$contigs           <- Biostrings::DNAStringSet()


R1s <- unlist(strsplit(opt$R1, ','));  if(! all(file.exists(R1s))) stop('All the R1 files could not be found.')
R2s <- unlist(strsplit(opt$R2, ','));  if(! all(file.exists(R2s))) stop('All the R1 files could not be found.')

t1 <- paste0(opt$workDir, '/x')

# Combine R1 and R2 data files in composite R1 and R2 files.
system(paste0('cat ', paste0(R1s, collapse = ' '), ' > ', t1, '_R1.fastq'))
system(paste0('cat ', paste0(R2s, collapse = ' '), ' > ', t1, '_R2.fastq'))
  

# Quality trim reads and create trimmed FASTA files.
r <- prepareTrimmedReads(readFastq(paste0(t1, '_R1.fastq')), readFastq(paste0(t1, '_R2.fastq')), qualCode = opt$trimQualCode)
writeFasta(r[[1]], file = paste0(t1, '_R1.trimmed.fasta'))
writeFasta(r[[2]], file = paste0(t1, '_R2.trimmed.fasta'))


# Align trimmed reads to the reference genome.
system(paste0(opt$bwaPath, ' mem -M ', opt$refGenomeBWA, ' ',  paste0(t1, '_R1.trimmed.fasta'), ' ', 
              paste0(t1, '_R2.trimmed.fasta'),  ' > ', paste0(t1, '_genome.sam')))
system(paste0(opt$samtoolsBin, '/samtools view -S -b ', paste0(t1, '_genome.sam'), ' > ', paste0(t1, '_genome.bam')))
invisible(file.remove(paste0(t1, '_genome.sam')))

if('fgbioCommand' %in% names(opt) & 'fgbioTrimPrimerCoords' %in% names(opt)){
  comm <- paste0(opt$fgbioCommand, ' TrimPrimers -i ', t1, '_genome.bam -o ', t1, '_genome.bam2 -H true -p ', opt$fgbioTrimPrimerCoords)
  p <- c('#!/bin/bash', paste0('source ', opt$condaShellPath), 'conda activate fgbio', comm)
  writeLines(p, file.path(opt$workDir, 'fgbio.script'))
  system(paste0('chmod 755 ', file.path(opt$workDir, 'fgbio.script')))
  system(file.path(opt$workDir, 'fgbio.script'))
  system(paste0('mv ', t1, '_genome.bam2 ', t1, '_genome.bam'))
  opt$fgbioPrimerTrimmed <- TRUE
}


# Remove read pairs with mapping qualities below the provided min score.
system(paste0(opt$samtoolsBin, '/samtools view -q ', opt$minBWAmappingScore, ' -b ', t1, '_genome.bam > ', t1, '_genome.filt.bam'))


# Retrieve a list of aligned reads.
alignedReadsIDs <- system(paste0(opt$samtoolsBin, '/samtools view ', t1, '_genome.filt.bam | cut  -f 1 | uniq'), intern = TRUE)

if(length(alignedReadsIDs) == 0){
  opt$errorCode <- 1
  opt$errorMessage <- 'No quality trimmed readsa aligned to the reference genome.'
  save(opt, file = opt$outputFile)
  unlink(opt$workDir, recursive = TRUE)
  stop()
}

# Build contigs with reads that aligned to the reference genome in the proper orientation and sufficient mapping scores.
writeFasta(r[[1]][names(r[[1]]) %in% alignedReadsIDs], file = paste0(t1, '_R1.trimmed.genomeAligned.fasta'))
writeFasta(r[[2]][names(r[[2]]) %in% alignedReadsIDs], file = paste0(t1, '_R2.trimmed.genomeAligned.fasta'))

opt$contigs <- megaHitContigs(paste0(t1, '_R1.trimmed.genomeAligned.fasta'), paste0(t1, '_R2.trimmed.genomeAligned.fasta'), 
                              workDir = paste0(t1, '_megahit'), megahit.path = opt$megahitPath)


refGenomeLength <- width(readFasta(opt$refGenomeFasta))

# Align contigs to reference genome and only retain those that map well (alignment flag == 0 or 16).
writeFasta(opt$contigs, file = paste0(t1, '_contigs.fasta'))
system(paste0(opt$bwaPath, ' mem -M ', opt$refGenomeBWA, ' ',  paste0(t1, '_contigs.fasta'), ' > ', paste0(t1, '_contigs.sam')))
sam <- readLines(paste0(t1, '_contigs.sam'))
samLines <- sam[! grepl('^@', sam)]

if(length(samLines) != 0){
  sam <- subset(read.table(textConnection(samLines), sep = '\t', header = FALSE, fill = TRUE), V2 %in% c(0, 16))
  sam$length <- sapply(as.character(sam$V13), samMD2length)
  opt$contigs <- opt$contigs[names(opt$contigs) %in% sam$V1]

  if(length(opt$contigs) > 0){
    d <- group_by(sam, V1) %>% top_n(1, length) %>% dplyr::slice(1) %>% 
         summarise(start = V4, length = length, editDist = as.integer(str_extract(V12, '\\d+'))) %>% ungroup()
  
    opt$contigStartPos   <- d[match(names(opt$contigs), d$V1),]$start
    opt$contigEndPos     <- opt$contigStartPos + d[match(names(opt$contigs), d$V1),]$length
    opt$contigsEditDists <- d[match(names(opt$contigs), d$V1),]$editDist
    names(opt$contigs)   <- paste0(names(opt$contigs), ' [', opt$contigsEditDists, ']')
    
    # Check to make sure that the assembler did not create something much longer than the reference.
    opt$contigs <- opt$contigs[! opt$contigEndPos > refGenomeLength + 50]
    
  } else {
    opt$contigStartPos <- NA
    opt$contigEndPos <- NA
    opt$contigsEditDists <- NA
  }
} else 
{
  opt$contigs <- Biostrings::DNAStringSet()
  opt$contigStartPos <- NA
  opt$contigEndPos <- NA
  opt$contigsEditDists <- NA
}


system(paste0(opt$samtoolsBin, '/samtools sort -o ', paste0(t1, '_genome.filt.sorted.bam'), ' ', paste0(t1, '_genome.filt.bam')))
system(paste0(opt$samtoolsBin, '/samtools index ', paste0(t1, '_genome.filt.sorted.bam')))


# Save bam and bam index files for downstream analyses.
# system(paste0('cp ', t1, '_genome.filt.sorted.bam ', sub('.RData', '.bam', sub('VSPdata', 'VSPalignments', opt$outputFile))))
# system(paste0('cp ', t1, '_genome.filt.sorted.bam.bai ', sub('.RData', '.bam.bai', sub('VSPdata', 'VSPalignments', opt$outputFile))))


# Determine the maximum read depth. Overlapping mates will count a position twice.
system(paste0(opt$samtoolsBin, '/samtools depth -d 0 ', paste0(t1, '_genome.filt.sorted.bam'), ' -o ', paste0(t1, '.depth')))
maxReadDepth <- max(read.table(paste0(t1, '.depth'), sep = '\t', header = FALSE)[,3])


# Create pileup data file for determining depth at specific locations.
# (!) mpileup will remove duplicate reads.
system(paste0(opt$samtoolsBin, '/samtools mpileup -A -a -Q 0 -o ', paste0(t1, '.pileup'), ' -d ', maxReadDepth, 
              ' -f ', opt$refGenomeFasta, ' ', paste0(t1, '_genome.filt.sorted.bam')))


# Determine the percentage of the reference genome covered in the pileup data.
opt$pileupData <- tryCatch({
                              read.table(paste0(t1, '.pileup'), sep = '\t', header = FALSE, quote = '')[,1:5]
                           }, error = function(e) {
                              return(data.frame())
                           })



# Pileup format reports the number of read pairs (column 4) while VCF format (DP) 
# reports the number of reads which appears to report 2x the pileup format value. 
# Confirmed by looking at pileup in IGV.


if(nrow(opt$pileupData) > 0){
  refGenomeLength <- nchar(as.character(readFasta(opt$refGenomeFasta)@sread))
  opt$refGenomePercentCovered <- nrow(subset(opt$pileupData,  V4 >= 1))  / refGenomeLength
  opt$refGenomePercentCovered_5reads <- nrow(subset(opt$pileupData,  V4 >= 5))  / refGenomeLength
  
  # If pileup data could be created then we can try to call variants.
  # --max-depth 100000 
  system(paste0(opt$bcftoolsBin, '/bcftools mpileup -A -Ou -f ', opt$refGenomeFasta, ' -d 10 ',
                paste0(t1, '_genome.filt.sorted.bam'), ' |  ', opt$bcftoolsBin,  '/bcftools call -mv -Oz ', 
                ' -o ', paste0(t1, '.vcf.gz')))
  
  
  # Read in the variant table created by bcf tools. 
  # We use tryCatch() here because the table may be empty only containing the header information.
  opt$variantTable <- tryCatch({
      ### system(paste0(opt$bcftoolsBin, "/bcftools filter -i'QUAL>", opt$minVariantPhredScore, "' ", 
      system(paste0(opt$bcftoolsBin, "/bcftools filter -i'QUAL>", opt$minVariantPhredScore, " && DP>10' ", 
                    paste0(t1, '.vcf.gz'), " -O z -o ", paste0(t1, '.filt.vcf.gz')))
      
      system(paste0(opt$bcftoolsBin, '/bcftools index ', t1, '.filt.vcf.gz'))
      
      x <- read.table(paste0(t1, '.filt.vcf.gz'), sep = '\t', header = FALSE, comment.char = '#')
      names(x) <- c('CHROM', 'POS', 'ID', 'REF', 'ALT', 'QUAL', 'FILTER', 'INFO', 'FORMAT', 'OTHER')
      x <- x[, !is.na(names(x))]
      x
    },  error=function(cond) {
      return(data.frame()) 
    })
  
  if(nrow(opt$variantTable) > 0){
    opt$variantTable <- tryCatch({
      # Here we parse the pileup data to create a more informative alt call for variants.
      x <- bind_rows(lapply(1:nrow(opt$variantTable), function(i){
                  x <- opt$variantTable[i,]
                  p <- parsePileUpString(subset(opt$pileupData, V2 == x$POS)$V5)
                  
                  # Expand the variant call to include the different possibilities.
                  x <- x[rep(1, length(p)),]
                  x$ALT <- names(p)
                  x$percentAlt <- p
                  x <- subset(x, percentAlt > 0)
                  x$reads <- subset(opt$pileupData, V2 == x$POS[1])$V4
                  
                  dplyr::select(x, -ID, -FILTER, -INFO, -FORMAT, -OTHER)
                }))
      x
    }, error=function(cond) {
      stop('Error parsing variant occurrences.')
    })
    
    
    # Select the major variant for each position.
    opt$variantTableMajor <- dplyr::filter(opt$variantTable,  percentAlt >= 0.5 & ! ALT == 'e') %>%
                             dplyr::group_by(POS) %>%
                             dplyr::top_n(1, wt = percentAlt) %>%
                             dplyr::slice(1) %>%
                             dplyr::ungroup() %>%
                             dplyr::filter(reads >= 5)
    
  }
} else {
  opt$refGenomePercentCovered <- 0
  opt$refGenomePercentCovered_5reads  <- 0
  
  opt$errorCode <- 5
  opt$errorMessage <- 'No pileup or variant data available.'
}


# Determine the result of the variants on the AA sequence of viral proteins.
# This approach assumes all orfs are non-overlapping pos. strand sequenes.
if(nrow(opt$variantTableMajor) > 0){

  # Here we copy the variant vcf file and selectively remove calls 
  # which are not found in our filtered variantTable. This is done 
  # to preserve the additional comment lines which appear to be necessary. 

  tryCatch({
    system(paste0('cp ', t1, '.filt.vcf.gz ', t1, '.filt.vcf.copy.gz'))
    system(paste0('gunzip ', t1, '.filt.vcf.copy.gz'))
    
    o <- lapply(readLines(paste0(t1, '.filt.vcf.copy')), function(x){
      if(grepl('^#', x)){
        return(x)
      } else {
        if(as.integer(unlist(strsplit(x, '\t'))[2]) %in% opt$variantTableMajor$POS){
          return(x)
        } else {
          return(NULL)
        }
      }
    })
    
    write(unlist(o[! sapply(o, is.null)]), file = paste0(t1, '.filt.vcf.copy2'))
    
    # Capture vcf
    # read.table(textConnection(unlist(opt$finalVCF)), sep = '\t')
    opt$finalVCF = o[! sapply(o, is.null)]
    
    system(paste0('bgzip ', t1, '.filt.vcf.copy2'))
    system(paste0(opt$bcftoolsBin, '/bcftools index ', t1, '.filt.vcf.copy2.gz'))
    system(paste0('cat  ', opt$refGenomeFasta, ' | ', opt$bcftoolsBin, '/bcftools consensus ',  
                  t1, '.filt.vcf.copy2.gz > ', t1, '.consensus.fasta'))
  
    opt$concensusSeq <- as.character(readFasta(paste0(t1, '.consensus.fasta'))@sread)
    
    # Predict pangolin lineage for genomes with >= 90% coverage.
    # if(opt$refGenomePercentCovered >= 0.90){
    if(opt$refGenomePercentCovered_5reads >= 0.95){
      
      # Create a bash script which will start the requires Conda environment and run pangolin.
      p <- c('#!/bin/bash', paste0('source ', opt$condaShellPath), 'conda activate pangolin', 'pangolin -o $2 $1')
      writeLines(p, file.path(opt$workDir, 'pangolin.script'))
      system(paste0('chmod 755 ', file.path(opt$workDir, 'pangolin.script')))
      
      comm <- paste0(file.path(opt$workDir, 'pangolin.script'), ' ', t1, '.consensus.fasta ', t1, '.consensus.pangolin')
      system(comm)
      
      if(file.exists(paste0(t1, '.consensus.pangolin/lineage_report.csv'))){
        o <- read.csv(paste0(t1, '.consensus.pangolin/lineage_report.csv')) 
      
        if(nrow(o) > 0){
            opt$pangolinAssignment <- o[1,]$lineage
            opt$pangolinAssignmentConflict <- o[1,]$conflict
            opt$pangolinAssignmentPangoLEARN_version <- o[1,]$pangoLEARN_version
        }
      }
    } 
  }, error=function(cond) {
    stop('Error creating concensus sequence.')
  })
  
  message('Concensus sequence is ', refGenomeLength - nchar(opt$concensusSeq), ' NT shorter than the reference sequence.')
  
  gb <- readGenBank(opt$refGenomeGenBank)
  
  cds <- gb@cds
  seqlevels(cds) <- 'genome'
  seqnames(cds)  <- 'genome'
  
  # Calculate how the shift left or right caused by deletions and insertions.
  opt$variantTableMajor$shift <- ifelse(grepl('del', opt$variantTableMajor$ALT), (nchar(opt$variantTableMajor$ALT)-3)*-1, 0)
  opt$variantTableMajor$shift <- ifelse(grepl('ins', opt$variantTableMajor$ALT), (nchar(opt$variantTableMajor$ALT)-3), opt$variantTableMajor$shift)
  
  # Remove variant positions flanking indels since they appear to be artifacts. 
  artifacts <- c(opt$variantTableMajor[grep('ins|del', opt$variantTableMajor$ALT),]$POS + abs(opt$variantTableMajor[grep('ins|del', opt$variantTableMajor$ALT),]$shift),
                 opt$variantTableMajor[grep('ins|del', opt$variantTableMajor$ALT),]$POS -1)
  
  opt$variantTableMajor <- opt$variantTableMajor[! opt$variantTableMajor$POS %in% artifacts,]
  
  opt$variantTableMajor <- bind_rows(lapply(split(opt$variantTableMajor, 1:nrow(opt$variantTableMajor)), function(x){
    
    # Determine the offset of this position in the concensus sequence because it may not be the same length
    # if indels have been applied. Here we sum the indel shifts before this variant call.
    
    # JKE -- grep can return multiples?
    
    offset <- sum(opt$variantTableMajor[1:grep(x$POS, opt$variantTableMajor$POS),]$shift) 
    
    cds2 <- cds
    start(cds2) <- start(cds2) + offset 
    end(cds2) <- end(cds2) + offset 
    
    v1 <- GRanges(seqnames = 'genome', ranges = IRanges(x$POS, end = x$POS), strand = '+')
    o1 <- GenomicRanges::findOverlaps(v1, cds)
    
    v2 <- GRanges(seqnames = 'genome', ranges = IRanges(x$POS + offset, end = x$POS + offset), strand = '+')
    o2 <- GenomicRanges::findOverlaps(v2, cds2)
    
    if(length(o2) == 0){
      x$genes <- 'intergenic'
      
      if (grepl('ins', as.character(x$ALT))){
        x$type <- paste0('ins ', nchar(x$ALT)-3)
      } else if (grepl('del', as.character(x$ALT))){
        x$type <- paste0('del ', nchar(x$ALT)-3)
      } else {
        x$type <- ' '
      }
    } else {
      
      # Define the gene the variant is within.
      hit1 <- cds[subjectHits(o1)]
      hit2 <- cds2[subjectHits(o2)]
      
      x$genes <- paste0(hit2$gene, collapse = ', ')
      
      # Native gene AA sequence.
      orf1  <- as.character(translate(DNAString(substr(as.character(readFasta(opt$refGenomeFasta)@sread), start(hit1), end(hit1)))))
      
      # Variant gene AA sequence.
      orf2 <- as.character(translate(DNAString(substr(opt$concensusSeq, start(hit2), end(hit2)))))
      
    
      # Determine the offset of this position in the concensus sequence because it may not be the same length
      # if indels have been applied. Here we sum the indel shifts before this variant call.
      # offset <- sum(opt$variantTableMajor[1:grep(x$POS, opt$variantTableMajor$POS),]$shift)
      
      #              1   2   3   4   5   6   7   8
      # 123 456 789 012 345 678 901 234 567 890 123
      # ATG CAT TGA ATG GGC TTA CGA GCT TAA GTA TAG
      #             ^             x  21-10 + 2 = 13/3 = 4.3 ~ 4
      #                          x   20-10 + 2 = 12/3 = 4.0 = 4
      #                         x    19-10 + 2 = 11/3 = 3.6 ~ 4
      #                                 x   25-10 + 2 = 17/3 = 5.6 ~ 6
      #                                  x  26-10 + 2 = 18/3 = 6.0 = 6
      #                                   x 27-10 + 2 = 19/3 = 6.3 ~ 6
      
      aa <- round(((x$POS - start(hit1)) + 2)/3)
      orf_aa <- substr(orf1, aa, aa)

      aa2 <- round((((x$POS + offset) - start(hit2)) + 2)/3)
      orf2_aa <- substr(orf2, aa2, aa2)

      maxALTchars <- max(nchar(unlist(strsplit(as.character(x$ALT), ','))))

      if(nchar(as.character(x$REF)) == 1 & nchar(as.character(x$ALT)) > 1 & maxALTchars == 1){
        x$type <- paste0(x$POS, '_mixedPop')
      } else if (grepl('ins', as.character(x$ALT))){
        x$type <- paste0('ins ', nchar(x$ALT)-3)
      } else if (grepl('del', as.character(x$ALT))){
        x$type <- paste0('del ', nchar(x$ALT)-3)
      } else if (orf_aa != orf2_aa){
        x$type <- paste0(orf_aa, aa2, orf2_aa)
      } else {
        x$type <- 'silent'
      }
     }
    x
  }))
  
} else {
  # There were no variants called so we report the reference as the concensus sequence.
  opt$concensusSeq <- as.character(readFasta(opt$refGenomeFasta)@sread)
}


# BCFtools calls indels by the base preceding the modification.
# Here we find deletion calls and increment the position by one to mark the first deleted base.
i <- opt$variantTable$POS %in% opt$variantTable[grep('del', opt$variantTable$ALT),]$POS
if(any(i)) opt$variantTable[i,]$POS <- opt$variantTable[i,]$POS + 1


# Deletions may be incomplete and we do not want to call variants for bases beneath major deletions.
# Here we delete variants beneath major deletions. 
#
# This may be too harsh since there may be true mixed populations -- consider a more robust approach.
i <- opt$variantTableMajor$POS %in% opt$variantTableMajor[grep('del', opt$variantTableMajor$ALT),]$POS

if(any(i)){
  o <- opt$variantTableMajor[i,]
  r <- unlist(lapply(split(o, 1:nrow(o)), function(x){
    (x$POS+1):(x$POS+1+abs(x$shift))
  }))
  opt$variantTableMajor <- opt$variantTableMajor[! opt$variantTableMajor$POS %in% r,]
}

i <- opt$variantTableMajor$POS %in% opt$variantTableMajor[grep('del', opt$variantTableMajor$ALT),]$POS
if(any(i)) opt$variantTableMajor[i,]$POS <- opt$variantTableMajor[i,]$POS + 1


save(opt, file = opt$outputFile)
unlink(opt$workDir, recursive = TRUE)
