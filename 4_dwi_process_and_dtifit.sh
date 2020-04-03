#!/bin/bash

###############################################################################################
# A script for running DWI preprocessing and dti model fitting.
# 
# Inputs (all required):
# 1 : Full path to subject directory containing data (no / at end).
#
#
# Requirements for running this script:
# FSL (version 6.0.2 or higher)
# 
# NOTES: 
# Data must be in BIDS format prior to running (see https://bids.neuroimaging.io/).
# You must have a file called acq_params_orig.txt (required for EDDY: see https://fsl.fmrib.ox.ac.uk/fsl/fslwiki/eddy/UsersGuide#A--acqp)
# See below for two manual edits that are required.
#
###############################################################################################


#################### Version log & disclaimer ################################################
#
# Version 4_dwi_process_and_dtifit.sh has been written by S Goksan and last edited on 03rd APR 2020. 
#
# Disclaimer:
# We recommend using the information in this file as guidance only.
# All scripts have been written specifically for use with the dataset described in Goksan et al., 2020, in prep. 
# There is no guarantee that it will work on another data set. 
# 
# If you do use this script, please reference Goksan et al., 2020, in prep
#
##############################################################################################



# This information will be provided if you call the function without any inputs.
Usage() {
 echo "Use this as:"
 echo "./`basename $0` <path to DIR with no / at end>"
}

# Just give usage if no arguments are specified
if [ $# -eq 0 ] ; then Usage; exit 0; fi

# Set the path to the directory containing files
path=$1

N="`basename $path`";
cd ${path}/dwi/



## FIRST MANUAL EDIT REQUIRED: see ## comments

# copy the acquisition parameters text file
if [ ! -e acq_params.txt ] ; then	
	cp ${path}/acq_params_orig.txt acq_params.txt  ## This path should correspond to the location of your acq_params_orig.txt file.
fi 

## SECOND MANUAL EDIT REQUIRED:
## Note: 133 below corresponds to the number of diffusion directions in this data.
## This may need to be edited for other studies.

# create an index file. 

if [ ! -e index.txt ] ; then
	indx=""
	val=1
	for ((i=1; i<=133; i+=1));  do 		## edit 133 to equal the number of diffusion directions in your data.
	indx="${indx}${val}\n"; 
	done
	echo -e ${indx} > index.txt
fi 

## THIRD MANUAL EDIT
## copy OR manually create a file called b0_volumes.txt. 
## This text file will contain a comma separated list of the volumes corresponding to b0 volumes within your data.

b0path=~/Documents/code


# check name of dwi image
if [ ! -e ${path}/dwi/${N}_dwi.nii.gz ] ; then
	echo "rename dwi data files to bids format"
	exit 0
fi 

# select and group the A>>P and P>>A B0 images
if [ ! -e DTI_AP_PA_b0_pair.nii.gz ] ; then 
	fslroi ${N}_dwi.nii.gz DTIb0_AP.nii.gz 0 1
	fslmerge -t DTI_AP_PA_b0_pair DTIb0_AP.nii.gz *b0negPE.nii.gz
	chmod a+x DTI_AP_PA_b0_pair.nii.gz
fi 

# check that bvals and bvecs already exist. ## CHECK THIS - should have been created when prepping data using dcm2niix.
if [ ! -e ${N}_dwi.bval ] ; then
	echo "Check you have the correct .bval file associated with your DWI data."
	exit 0
	
	else if [ ! -e ${N}_dwi.bvec ] ; then	
		echo "Check you have the correct .bvec file associated with your DWI data."
		exit 0
	fi
fi


# Run topup

if [ ! -e topup_AP_PA_b0_iout.nii.gz ] ; then
	topup --imain=DTI_AP_PA_b0_pair.nii.gz --datain=acq_params.txt --config=b02b0.cnf --out=topup_AP_PA_b0 --iout=topup_AP_PA_b0_iout --fout=topup_AP_PA_b0_fout --verbose
fi 

# 'wait' here until topup is finished: although it should automatically wait.
BACK_PID=$!
wait $BACK_PID


# make a mask
if [ ! -e topup_unwarped_mean_brain_mask.nii.gz ] ; then
	fslmaths topup_AP_PA_b0_iout -Tmean topup_unwarped_mean
	bet topup_unwarped_mean topup_unwarped_mean_brain -m -f 0.2
fi 

# Run eddy_openmp
if [ ! -e eddy_corrected_data.nii.gz ] ; then
eddy_openmp 	--imain=${N}_dwi.nii.gz \
		--mask=topup_unwarped_mean_brain_mask.nii.gz \
		--acqp=acq_params.txt \
		--index=index.txt \
		--bvecs=${N}_dwi.bvec \
		--bvals=${N}_dwi.bval \
		--topup=topup_AP_PA_b0 \
		--out=eddy_corrected_data \
 		--data_is_shelled \
		--repol \
		--verbose

	# Note that mporder and cnr_maps were not run as standard for this data
	# You can add these options if you want.
	# --repol runs eddy with outlier replacement
	# --mporder=4  will run slice to volume correction.
fi 

wait

# Once eddy is done, obtain an average of the eddy_corrected b0s

if [ -e eddy_corrected_data.nii.gz ] ; then
	if [ ! -e ${N}_b0_mean.nii.gz ] ; then 
		fslselectvols -i eddy_corrected_data.nii.gz -o b0_vols.nii.gz --vols=`cat ${b0path}/b0_volumes.txt`
		
		fslmaths b0_vols.nii.gz -Tmean b0_mean.nii.gz
		# run fast to get a bias corrected b0 image	
		
		fast -t 2 -B --nopve -o ${N}_b0_mean b0_mean.nii.gz
	fi
fi

wait

############# create registration of b0_restore image to highres 
mkdir dwi_reg
cp ${path}/anat/${N}_T1w.nii.gz dwi_reg/highres_head.nii.gz
cp ${N}_b0_mean_restore.nii.gz dwi_reg/.
cd ${path}/dwi/dwi_reg
cp ${N}_b0_mean_restore.nii.gz dwi_epi.nii.gz

if [ ! -e dwi2highres.mat ] ; then
	flirt -in dwi_epi.nii.gz -ref highres_head.nii.gz -omat dwi2highres.mat -out dwi2highres.nii.gz
	wait
	echo "linear dwi to highres reg complete"	
	convert_xfm -inverse -omat highres2dwi.mat dwi2highres.mat
	echo "inverted matrix created for highres_head to dwi"	
fi


# get QC output report
if [ -e eddy_corrected_data.nii.gz ] ; then
eddy_quad 	eddy_corrected_data \
		-idx index.txt \
		-par eddy_corrected_data.eddy_parameters \
		-m topup_unwarped_mean_brain_mask.nii.gz \
		-b ${N}_dwi.bval \
		-f topup_AP_PA_b0_fout \
		-v
fi

echo "DONE `basename $0`"
