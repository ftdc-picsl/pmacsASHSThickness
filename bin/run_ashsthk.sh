#!/bin/bash
set -e

module load singularity/3.8.3

# Set this to 0 to leave tmp directory for debugging
cleanupTmp=1

# Keeps all files left by the container, and copies them to the
# output directory. This can be used to save intermediate files when the
# script runs successfully
keepAllFiles=0

# Which hemisphere to run. Some users may need
hemi="both"

scriptPath=$(readlink -e "$0")
scriptDir=$(dirname "${scriptPath}")
# Repo base dir under which we find bin/ and containers/
repoDir=${scriptDir%/bin}

image="${repoDir}/containers/ashsthk-4.0.sif"

templateDir="/project/ftdc_pipeline/ftdc-picsl/pmacsASHSThickness/templates/ashsthk_3T_T1_template_v1"

#######################################################################
#
#  Program:   ASHSTHK (Multi template thickness pipeline for ASHS)
#  Module:    $Id$
#  Language:  BASH Shell Script
#  Copyright (c) 2021 Long Xie, University of Pennsylvania
#
#  This file is the implementation of the multi-template thickness pipeline
#  to measure thickness of medial temporal lobe subregions. Modified for
#  PMACS by Philip Cook
#
#######################################################################

function usage()
{
echo "
$0: multi-template thickness pipeline for ASHS
  usage:
    $0 -i /path/to/subj_id/ashs -o /path/to/output [options]
"
}

# some basic functions
function help()
{
  usage

  cat <<-USAGETEXT

  required options:
    -i path           Input ASHS segmentation directory. The script will look first for files ending in
                      "MTLSeg_[left,right].nii.gz", as output by the fastashs or pmacsASHS pipeline. If
                      this is not found, the script looks for "[left,right]_lfseg_heur.nii.gz", as output
                      by running ashs_main.sh directly.

    -a path           Path to the multi-template thickness template directory.

    -o path           Output directory and file prefix

  optional:
    -h                Print help

    -e string         Which hemisphere to process. Either "left", "right", or "both" (default = ${hemi}).

    -k (0)/1          If 1, copy the contents of the working directory to the output (default = $keepAllFiles).

    -s integer        Run only one stage (see below); also accepts range (e.g. -s 1-3).
                      By default, Only steps 1 to 5 will be run (to variant template).
                      If the user pointwise correspondance is desired, steps 6-8 are needed.
                      Stages:
                        1: Perform affine and coarse deformable registration between
                           subject segmentation to all the atlases.
                        2: Determine group membership.
                        3: Perform deformable registration to the selected variant template.
                        4: Perform geodesic shooting to the variant template (VT)
                        5: Evaluate fit quality and measure thickness for VT.
                        6: Perform deformable registration to the unified template.
                        7: Perform geodesic shooting to the unified template (UT).
                        8: Evaluate fit quality and measure thickness for UT.


Multi-threading is handled automatically - the maximum number of threads is set to the number of cores available
to the job. The registration step will be multi-threaded, but the geodesic shooting runs with a single thread,
so it may be more efficient to parallelize by running hemispheres independently.

If you use this software in research, please cite

Long Xie, et al, "Multi-template analysis of human perirhinal cortex in brain MRI:
Explicitly accounting for anatomical variability", NeuroImage 2017 Jan 1; 144(Pt A):183-202,
PMID: 27702610, PMCID: PMC5183532, DOI: 10.1016/j.neuroimage.2016.09.070



USAGETEXT
}

# function to clean up tmp and report errors at exit
function cleanup {
  EXIT_CODE=$?
  LAST_CMD=${BASH_COMMAND}
  set +e # disable termination on error

  if [[ $cleanupTmp -gt 0 ]]; then
    rm -rf ${jobTmpDir}/work_right ${jobTmpDir}/work_left
    rm -f ${jobTmpDir}/*
    rmdir ${jobTmpDir}
  else
    echo "Leaving working directory ${jobTmpDir}"
  fi

  if [[ ${EXIT_CODE} -gt 0 ]]; then
    echo "
$0 EXITED ON ERROR - PROCESSING MAY BE INCOMPLETE"
    echo "
The command \"${LAST_CMD}\" exited with code ${EXIT_CODE}
"
  fi

  exit $EXIT_CODE
}

# Exits, triggering cleanup, on CTRL+C
function sigintCleanup {
   exit $?
}

if [[ $# -lt 1 ]]; then
  usage
  echo "Try $0 -h for more information."
  exit 2
fi

# Check we're in a bsub job
if [[ -z "${LSB_DJOB_NUMPROC}" ]]; then
  echo "Script must be run from within an LSB job"
  exit 1
fi

while getopts "a:e:i:k:o:s:h" opt; do
  case $opt in
    a) templateDir=$(readlink -m "$OPTARG");;
    e) hemi=$(echo $OPTARG | tr '[:upper:]' '[:lower:]');;
    i) inputDir=$(readlink -m "$OPTARG");;
    k) keepAllFiles=$OPTARG;;
    o) outputDir=$(readlink -m "$OPTARG");;
    s) STAGE_SPEC=$OPTARG;;
    h) help; exit 0;;
    \?) echo "Unknown option $OPTARG"; exit 2;;
    :) echo "Option $OPTARG requires an argument"; exit 2;;

  esac
done

##############################################

if [[ ! -d $templateDir ]]; then
  echo "Template directory $templateDir does not exist"
  exit 1
fi

inputType="none"
inputFilePrefix=""

fastASHS=`ls ${inputDir}/*_MTLSeg_left.nii.gz 2> /dev/null || echo`
ashsMain=`ls ${inputDir}/*_left_lfseg_heur.nii.gz 2> /dev/null || echo`

if [[ -f "${fastASHS}" ]]; then
  echo "Found fastashs input $fastASHS"
  inputType="fastashs"
  fileBN=`basename $fastASHS`
  inputFilePrefix=${fileBN%_MTLSeg_left.nii.gz}
elif [[ -f "$ashsMain" ]]; then
  echo "Found ashs input $ashsMain"
  inputType="ashs"
  fileBN=`basename $ashsMain`
  inputFilePrefix=${fileBN%_left_lfseg_heur.nii.gz}
else
  echo "Cannot find ASHS segmentations in input directory ${inputDir}"
  exit 1
fi

if [[ ! -d "${templateDir}" ]]; then
  echo "Cannot find template directory $templateDir"
  exit 1
fi

mkdir -p ${outputDir}

if [[ ! -d ${outputDir} ]]; then
  echo "Output directory $outputDir cannot be created"
  exit 1
fi


# Set the start and end stages
if [[ $STAGE_SPEC ]]; then
  STAGE_START=$(echo $STAGE_SPEC | awk -F '-' '$0 ~ /^[0-9]+-*[0-9]*$/ {print $1}')
  STAGE_END=$(echo $STAGE_SPEC | awk -F '-' '$0 ~ /^[0-9]+-*[0-9]*$/ {print $NF}')
  if [[ $STAGE_START -lt 1 ]]; then
    STAGE_START=1
  fi
  if [[ $STAGE_END -gt 8 ]]; then
    STAGE_END=8
  fi
  if [[ $STAGE_END -lt $STAGE_START ]]; then
    STAGE_END=$STAGE_START
  fi
else
  STAGE_START=1
  STAGE_END=5
fi

jobTmpDir=$( mktemp -d -p /scratch ashsthk.${LSB_JOBID}.XXXXXXX.tmpdir )

if [[ ! -d "$jobTmpDir" ]]; then
  echo "Could not create job temp dir ${jobTmpDir}"
  exit 1
fi

trap cleanup EXIT

trap sigintCleanup SIGINT

# This script accepts "both" for the hemisphere but the container does not,
# default to process both in series
whichSide="left right"

if [[ $hemi != "both" ]]; then
  # should be either left or right. Anything else will
  # trigger an error when the segmentation cannot be mounted
  whichSide=$hemi
fi

for side in $whichSide; do

  segOrig=""

  if [[ $inputType == "fastashs" ]]; then
    segOrig="${inputDir}/${inputFilePrefix}_MTLSeg_${side}.nii.gz"
  elif [[ -f "$ashsMain" ]]; then
    segOrig="${inputDir}/${inputFilePrefix}_${side}_lfseg_heur.nii.gz"
  else
    echo "Unrecognized ashs segmentation input: $inputType"
    exit 1
  fi

  echo "
--- Container details ---"
singularity inspect $image
  echo "---
"
  singCmd="singularity exec \
    --cleanenv \
    --no-home \
    --env ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=${LSB_DJOB_NUMPROC} \
    --env MCR_CACHE_ROOT=/tmp \
    -B ${templateDir}:/app/template:ro \
    -B ${jobTmpDir}:/tmp \
    -B ${segOrig}:/app/input/${inputFilePrefix}_${side}_ASHSSeg.nii.gz \
    $image \
    /bin/bash /home/ashsthk/ashsthk_main.sh \
      -n $inputFilePrefix \
      -i /app/input/${inputFilePrefix}_${side}_ASHSSeg.nii.gz \
      -l $side \
      -a /app/template \
      -s ${STAGE_START}-${STAGE_END} \
      -t ${LSB_DJOB_NUMPROC} \
      -w /tmp"

  echo "
----- Singularity call -----
$singCmd
---
"
  $singCmd

done

# copy output to output directory
if [[ $keepAllFiles -gt 0 ]]; then
  cp -r ${jobTmpDir}/* ${outputDir}
else
  # Just copy output files in the tmp dir
  outputFiles=`ls -p ${jobTmpDir} | grep -v /`
  for f in $outputFiles; do
    cp ${jobTmpDir}/${f} ${outputDir}
  done
fi







