#!/bin/bash

#############################################################################################
# A function for renaming specific files for further analysis.
# 
# Inputs (all required):
# 1 : Full path to directory containing dirs to set up.
# 2 : Chosen fieldmap magnitude image (i.e. fmap_mag 1 = e1 or 2 = e2)
# 3 : Chosen task-rest_bold
# 4 : Chosen task-rest_sbref
# 5 : Run fmap_rads? (1 = yes, 0 = no).
# 6 : x coord for BET centre estimate
# 7 : y coord for BET centre estimate
# 8 : z coord for BET centre estimate
#
# Requirements for running this script:
# FSL (version 6.0.2 or higher)
#
# NOTES:
# This function can be used after relevant directories have been set up in BIDS format (see https://bids.neuroimaging.io/).
# You must select the files required for further analysis by leaving them in the directory and removing all other irrelavent files. 
# This script will rename remaining files in keeping with BIDS format.
#
#############################################################################################


#################### Version log & disclaimer ###############################################
#
# Version 1_files_bids_naming.sh has been written by S Goksan and last edited on 03rd APR 2020. 
#
# Disclaimer:
# We recommend using the information in this file as guidance only.
# All scripts have been written specifically for use with the dataset described in Goksan et al., 2020, in prep. 
# There is no guarantee that it will work on another data set. 
# 
# If you do use this script, please reference Goksan et al., 2020, in prep
#
#############################################################################################

### MANUAL EDIT MAY BE NEEDED
# Note: if multiple structurals were collected, you should only leave the best one in your anat directory.
# Note: json files were created by using the function dcm2niix in order to convert DICOM images to NIFTI format (see instructions to install dcm2niix at: https://github.com/rordenlab/dcm2niix)


# This information will be provided if you call the function without any inputs.
Usage() {
 echo "Use this as:"
 echo "./`basename $0` <path to DIR/> <2 for fmap_mag_e2 or 1 for e1> <orig_task-rest_bold> <orig_task-rest_sbref> <RUNFMAP_RADS? 1=yes> [finally input coords for centre of brain estimate for BET] <x> <y> <z>" 
 echo ""
 echo "Remember to exclude file endings so both nifti and json are renamed"
}

# Just give usage if no arguments are specified
if [ $# -eq 0 ] ; then Usage; exit 0; fi

# Set the path to the directory containing files
path=$1
cd $path
DIR="`dirname $path`"

REST_BOLD=`basename $3`
REST_SBREF=`basename $4`

N="`basename $path`";

# renaming chosen images

# rename structural T1 and json
if [ ! -e ${path}anat/${N}_T1w.nii.gz ] ; then
	mv ${path}anat/*T1*.nii.gz ${path}anat/${N}_T1w.nii.gz
	echo "${N} struct_T1w nifti file renamed."
fi
if [ ! -e ${path}anat/${N}_T1w.json ] ; then
	mv ${path}anat/*T1*.json ${path}anat/${N}_T1w.json
	echo "${N} struct_T1w json file renamed."
fi

# rename fieldmap files 
if [ $2 == 2 ] ; then
	mv ${path}fmap/*_e2.nii.gz ${path}fmap/${N}_fmap_mag.nii.gz
	mv ${path}fmap/*_e2.json ${path}fmap/${N}_fmap_mag.json
	echo "${N} fmap_mag_e2 files renamed."
	else
	mv ${path}fmap/*_e1.nii.gz ${path}fmap/${N}_fmap_mag.nii.gz
	mv ${path}fmap/*_e1.json ${path}fmap/${N}_fmap_mag.json
	echo "${N} fmap_mag_e1 files renamed."
fi

mv ${path}fmap/*_e2_ph.nii.gz ${path}fmap/${N}_fmap_phase.nii.gz
mv ${path}fmap/*_e2_ph.json ${path}fmap/${N}_fmap_phase.json
echo "${N} fmap_phase files renamed."

# rename BOLD files
mv ${path}func/${REST_BOLD}.nii.gz ${path}func/${N}_task-rest_bold.nii.gz
mv ${path}func/${REST_BOLD}.json ${path}func/${N}_task-rest_bold.json

mv ${path}func/${REST_SBREF}.nii.gz ${path}func/${N}_task-rest_sbref.nii.gz
mv ${path}func/${REST_SBREF}.json ${path}func/${N}_task-rest_sbref.json

echo "${N} task-rest files renamed."

# rename diffusion files
mv ${path}dwi/*_DTI_2X2X2_2_MULTISHELL_000*.nii.gz ${path}dwi/${N}_dwi.nii.gz
mv ${path}dwi/*_DTI_2X2X2_2_MULTISHELL_000*.json ${path}dwi/${N}_dwi.json
mv ${path}dwi/*.bval ${path}dwi/${N}_dwi.bval
mv ${path}dwi/*.bvec ${path}dwi/${N}_dwi.bvec
mv ${path}dwi/*DTI_*MULTISHELL_SBREF*.nii.gz ${path}dwi/${N}_dwi_sbref.nii.gz
mv ${path}dwi/*DTI_*MULTISHELL_SBREF*.json ${path}dwi/${N}_dwi_sbref.json
mv ${path}dwi/*DTI_B0_NEGPE_0*.nii.gz ${path}dwi/${N}_dwi_b0negPE.nii.gz
mv ${path}dwi/*DTI_B0_NEGPE_0*.json ${path}dwi/${N}_dwi_b0negPE.json
echo "${N} all DTI files renamed."


# RUN BETs
# Run BET on T1 
	if [ ! -e ${path}anat/${N}_T1w_brain.nii.gz ] ; then 
		bet ${path}anat/${N}_T1w.nii.gz ${path}anat/${N}_T1w_brain.nii.gz -A -f 0.5 -g 0 -c $6 ${7} ${8} -m -s
		BACK_PID=$!
		wait $BACK_PID	
		if [ -e ${path}anat/${N}_T1w_brain.nii.gz ] ; then 		
			echo "--BET done on T1--"
		else
			echo "--BET was not completed for $N--"
			exit 1
		fi
		
		# Visualize (or not) the output of BET

		echo -n "--Check the final brain extraction in fsleyes ? <y/n>" \n
		read ans
		wait

		if [ "$ans" != "${ans#[Yy]}" ] ; then
			cd ${path}anat  
			fsleyes ${N}_T1w.nii.gz ${N}_T1w_brain.nii.gz ${N}_T1w_brain_outskull_mask.nii.gz
			wait
		fi

		# Choice of mask for brain extraction
		echo -n "--Use outskull mask for brain extraction ? <y/n>" \n
		read ans

		if [ "$ans" != "${ans#[Yy]}" ] ; then
			fslmaths ${N}_T1w -mas ${N}_T1w_brain_outskull_mask.nii.gz ${N}_T1w_brain
			${T1_skullmask_used} = $ans
			echo "--Brain extracted image created from outskull mask--"
			# As outskull mask is often too big, run another bet to get rid of some more non-brain.
			bet ${path}anat/${N}_T1w_brain.nii.gz ${path}anat/${N}_T1w_brain.nii.gz -f 0.15 -g 0
			BACK_PID=$!
			wait $BACK_PID
			echo "--BET done on T1w_brain--"
		else
			echo "--Original BET remains for T1w_brain--"
			echo "This may need editing before running FEAT."
			${T1_skullmask_used} = $ans
		fi

	fi

	

	
# Run BET on fmap
	if [ $5 -eq 1 ] ; then
		if [ ! -e ${path}func/${N}_task-rest_aroma_example_mask.nii.gz ] ; then
			cd ${path}func
			bet ${N}_task-rest_sbref.nii.gz ${N}_task-rest_aroma_example.nii.gz -f 0.3 -n -m -R
			wait
			echo "--SBref BET done--"
		fi
	
		# Use sbref mask to get fmap_mag_brain
		# Register fmap image to sbref
		cd ${path}
		flirt -in fmap/${N}_fmap_mag.nii.gz -ref func/${N}_task-rest_sbref.nii.gz -omat fmap/${N}_fmap2sbref.mat
		echo "matrix created for ${N} sbref2fmap"
		
		# inverse the matrix
		convert_xfm -omat fmap/${N}_sbref2fmap.mat -inverse fmap/${N}_fmap2sbref.mat
		echo "inverse matrix created for ${N} fmap2sbref"
		
		# apply to sbref then create mask
		flirt -in func/${N}_task-rest_sbref.nii.gz -ref fmap/${N}_fmap_mag.nii.gz -applyxfm -init fmap/${N}_sbref2fmap.mat -out fmap/${N}_sbref2fmap.nii.gz
		cd ${path}fmap
		bet ${N}_sbref2fmap.nii.gz ${N}_sbref2fmap_brain.nii.gz -f 0.35 -n -m -R
		wait
		fslmaths ${N}_sbref2fmap_brain_mask.nii.gz -ero ${N}_sbref2fmap_brain_mask.nii.gz
		echo "image of ${N}_sbref2fmap_brain_mask created using bet and then eroded."
		
		fslmaths ${N}_fmap_mag.nii.gz -mas ${N}_sbref2fmap_brain_mask.nii.gz ${N}_fmap_mag_brain.nii.gz

	### CHECK Registered that mask looks good...the next step also allows for manual editing.
	
	if [ ! -e ${N}_sbref2fmap_brain_handdrawn_mask.nii.gz ] ; then
		echo -n "--Visualise & edit fmap brain extraction ? <y/n>"
		read ans

		if [ "$ans" != "${ans#[Yy]}" ] ; then  
			fsleyes ${N}_fmap_mag.nii.gz ${N}_fmap_mag_brain.nii.gz ${N}_sbref2fmap_brain_mask.nii.gz &
			echo -n "--NOTE: any edited mask must be named ${N}_sbref2fmap_brain_handdrawn_mask.nii.gz--"
		fi
		wait
		echo "--Was fmap_mag_brain acceptable ? <y/n>"
		read ans
		if [ "$ans" != "${ans#[Yy]}" ] ; then
			fslmaths ${N}_fmap_mag.nii.gz -mas ${N}_sbref2fmap_brain_handdrawn_mask.nii.gz ${N}_fmap_mag_brain.nii.gz
		fi
	fi 

		if [ -e ${N}_sbref2fmap_brain_handdrawn_mask.nii.gz ] ; then 
			fsl_prepare_fieldmap SIEMENS ${N}_fmap_phase.nii.gz ${N}_fmap_mag_brain.nii.gz ${N}_fmap_rads.nii.gz 2.46
			fmap_betmask_used=ans;
			wait
			# checked and the Delta TE is 2.46 (from tags)!
			echo "--Fieldmap created--"
		else
			echo "--Fieldmap was not created. Create appropriate fmap_mag_brain image and create fmap manually--"
		fi	
	fi

# add a text file which identifies the original names of the data being used for processing.

echo "Original file names 

Version of script run: ./`basename $0` 
Last edited by SG on 03rd Apr 2020.

origt1: ${N}_T1w.nii.gz
origfmap_mag: $2
orig_task-rest_bold: $3
orig_task-rest_sbref: $4
orig_dwi_data: ${path}dwi/*_DTI_2X2X2_2_MULTISHELL_000*.nii.gz
T1_outskull_mask_used? <y/n>: ${T1_skullmask_used}
fmap_mask_from_bet_acceptable: ${fmap_betmask_used}
Note: if fmap mask was not acceptable then it can be manually edited in fsleyes.

" > ${path}orig_files.txt


