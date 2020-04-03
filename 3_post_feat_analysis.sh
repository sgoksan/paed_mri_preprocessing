#!/bin/sh

#############################################################################################
#
# The script will run the second part of the BOLD preprocessing steps, including: 
# (a) Linear and non-linear Registration of the structural to template images (in MNI space)
# (b) ICA_AROMA (updated for use with the paediatric template)
# (c) Temporal Filtering of the EPI
#
# Once set up, it requires NO inputs in order to run. 
# This script will only run .feat folders where BOLD denoising has not been done yet.
#
# Requirements for running this script:
# FSL (version 6.0.2 or higher)
# ICA_AROMA (see https://github.com/maartenmennes/ICA-AROMA to download and install)
#
# INSTRUCTIONS FOR USE:
# This script requires editing before it can be used. See comments below. 
#
# Notes: 
# The following should already been done: Registration of EPI to structural, brain extraction of EPI, motion correction, b0 unwarping, highpass filtering and spatial smoothing. 
# This can be set up and run manually using the FSL (version 6.0.2) FEAT GUI (v 6.00)). 
# 
#############################################################################################

#################### Version log & disclaimer ###############################################
#
# Version 3_post_feat_analysis.sh has been written by S Goksan and last edited on 03rd APR 2020. 
#
# Disclaimer:
# We recommend using the information in this file as guidance only.
# All scripts have been written specifically for use with the dataset described in Goksan et al., 2020, in prep. 
# There is no guarantee that it will work on another data set. 
# 
# If you do use this script, please reference Goksan et al., 2020, in prep
#
#############################################################################################

# Setting general variables
BLUE='\033[0;34m'
NC='\033[0m'

### THREE MANUAL EDITS REQUIRED
# the 'home' variable is personalised and must be set to your environment
# path = the highest level directory containing your data (which should be in BIDS format: see https://bids.neuroimaging.io/)
# template = a file registered to MNI space, which corresponds to your template brain

home="/home/<log in name>"
path="/home/goksan/Documents/Data/"
template="/home/goksan/Documents/TemplatePaed/transform/nihpd2MNI"

# List all subjects in path so this script can be run for all your data
# If your data is in BIDS format, this will run for all data where no denoised data exists

cd $path
listfiles="`ls -d sub-*`"

for subdir in $listfiles ; do
	feat="`ls -d $path$subdir/func/*.feat`" 
	
	# Only run this script if a proproc Feat has been run & no denoised file exists
	if [ -d $feat ] && [ ! -e $feat/ICA_AROMA/denoised_func_data_aggr_tempfilt.nii.gz ] ; then 
		echo "Running script `basename $0` for $subdir"
		### 1st step : Complete Registrations
		
		# obtain all non-linear reg files
		if [ ! -e standard_mask.nii.gz ] ; then	
			cd $feat/reg
			cp ${template}.nii.gz standard_head.nii.gz
			cp ${template}_brain.nii.gz standard.nii.gz
			fslmaths standard.nii.gz -bin standard_mask.nii.gz
			echo "--Reg templates copied--";
	 	fi

		# Run linear flirt and non-linear reg using FNIRT
		
		if [ ! -e $feat/reg/highres2standard.mat ] ; then
			echo "Running Flirt"
			flirt -in highres.nii.gz -ref standard.nii.gz -out highres2standard_linear.nii.gz -omat highres2standard.mat -cost corratio -dof 12 -searchrx -90 90 -searchry -90 90 -searchrz -90 90 -interp trilinear
		fi
		if [ ! -e $feat/reg/highres2standard.nii.gz ] ; then
			echo "Running Fnirt"
			fnirt --ref=standard.nii.gz --in=highres.nii.gz --aff=highres2standard.mat --config=$home/Documents/TemplatePaed/T1_2_NIHPD_sym_1mm.cnf --iout=highres2standard.nii.gz --cout=highres2standard_warp.nii.gz --jout=highres2highres_jac --refmask=standard_mask.nii.gz --warpres=10,10,10
		fi
	
		wait
	
		# complete all relevant reg files
		# applywarp -i highres -r standard -o highres2standard -w highres2standard_warp
		if [ ! -e standard2example_func.mat ] ; then	
			convert_xfm -inverse -omat standard2highres.mat highres2standard.mat
			convert_xfm -omat example_func2standard.mat -concat highres2standard.mat example_func2highres.mat
			convertwarp --ref=standard --premat=example_func2highres.mat --warp1=highres2standard_warp --out=example_func2standard_warp
			applywarp --ref=standard --in=example_func --out=example_func2standard --warp=example_func2standard_warp
			convert_xfm -inverse -omat standard2example_func.mat example_func2standard.mat	
			echo "--Relevant Reg files CREATED--"
		else
			echo "--All reg files EXIST--"
		fi
		 

		### 2nd step : Run ICA_AROMA
		
		# create a mask of BOLD SBREF
		if [ ! -e $path$subdir/func/${subdir}_task-rest_aroma_example_mask.nii.gz ] ; then
			cd $path$subdir/func
			echo "--Brain Extracting BOLD SBREF--"
			bet ${subdir}_task-rest_sbref_bc.nii.gz ${subdir}_task-rest_aroma_example.nii.gz -f 0.3 -n -m -R
			wait
		fi

	## AROMA is run within the next loop.
	## NOTE: For the Goksan et al. 2020 project, the mask file in ICA_AROMA folder has been updated so it works better with the PaedTemplate2MNI image
	## NOTE: the code assumes that ICA_AROMA is located in /home/<user>/bin/ICA-AROMA-master

		if [ ! -d $feat/ICA_AROMA ] ; then 
		
			# Below will run by specifying the linear and non-linear warp
			echo "--Running ICA-AROMA on filtered_func_data--"
			python ~/bin/ICA-AROMA-master/ICA_AROMA.py -in $feat/filtered_func_data.nii.gz -out $feat/ICA_AROMA -mc $feat/mc/prefiltered_func_data_mcf.par -affmat $feat/reg/example_func2highres.mat -warp $feat/reg/highres2standard_warp.nii.gz -m $feat/../${subdir}_task-rest_aroma_example_mask.nii.gz -den aggr 

			BACK_PID=$!
			wait $BACK_PID

			if [ -e $feat/ICA_AROMA/denoised_func_data_aggr.nii.gz ] ; then 
				echo "--AROMA done-- for ${subdir}"
			else
				echo "--AROMA did not create a denoised file for ${subdir}--"
				exit 1
			fi

		fi

		### 3rd step : Filtering
		# create a denoised file and filter denoised data
		if [ ! -e denoised_func_data_aggr_tempfilt ] && [ -d $feat/ICA_AROMA ] ; then
			cd $feat
			echo "--Running filtering on denoised data--"
			fslmaths ICA_AROMA/denoised_func_data_aggr.nii.gz -Tmean tempMean
			fslmaths ICA_AROMA/denoised_func_data_aggr.nii.gz -bptf 40.32258064516129 -1 -add tempMean ICA_AROMA/denoised_func_data_aggr_tempfilt
			if [ -e denoised_func_data_aggr_tempfilt ] ; then	
				echo "--Filtering done-- for ${subdir}"
			fi
		fi

	echo $BLUE "--Subject" $subdir "done--" $NC
	
	fi
done

echo "DONE `basename $0`"
