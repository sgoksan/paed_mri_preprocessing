#!/bin/sh

#############################################################################################
# This script will:
# (a) Run FAST segmentation and bias correction of the T1 weighted structural.
# (b) Apply the bias field correction to the functional sbref image.
# 
# Input (required):
# 1 : Full path to subject directory containing data. (No '/' at end of path).
#
# Requirements for running this script:
# FSL (version 6.0.2 or higher)
#
#############################################################################################


#################### Version log & disclaimer ###############################################
#
# Version 2_fast_anat_field_correct.sh has been written by S Goksan and last edited on 03rd APR 2020.  
#
# This script has specifically been written to work on T1 structural resting state functional data. 
# You may have to edit the code for it to work on other data.
#
# Disclaimer:
# We recommend using the information in this file as guidance only.
# All scripts have been written specifically for use with the dataset described in Goksan et al., 2020, in prep. 
# There is no guarantee that it will work on another data set. 
# 
# If you do use this script, please reference Goksan et al., 2020, in prep
#
#############################################################################################


# This information will be provided if you call the function without any inputs.
Usage() {
 echo "Use this as:"
 echo "./`basename $0` <path to DIR without / at end>"
}

# Just give usage if no arguments are specified
if [ $# -eq 0 ] ; then Usage; exit 0; fi

# Set all the variables 
path="`dirname $1`"
BLUE='\033[0;34m'
NC='\033[0m'

# Run FAST for the specified subject (this script is not general, meaning there may be aspects that need editting in order to identify the correct files).

cd $path
sub="`basename $1`"

# check if a structural_brain exists (created by script 1 using BET)
if [ ! -e $path/$sub/anat/${sub}_T1w_brain.nii.gz ] ; then
	echo "You must have a brain extracted structural"
	echo "This script could not run for ${sub}"
	exit 0;
fi

# Obtain date of brain extracted image for subsequent check if bias correction has been done.
cd $path/$sub/anat/
date_a=`stat -c%y ${sub}_T1w_brain.nii.gz`
date_A=`echo $date_a | tr -d [:space:]-[:punct:]`

	# If a restored structural does not exist then FAST has not been run yet so Run FAST & create a fast.log
	if [ ! -e $path/$sub/anat/${sub}_T1w_brain_restore.nii.gz ] ; then
		cd $path/$sub/anat
		fast -t 1 -n 3 -H 0.1 -b -B -o $path/$sub/anat/${sub}_T1w_brain $path/$sub/anat/${sub}_T1w_brain

		if [ $? != 0 ] ; then	# $? logs any errors in the most recent function
			echo "An error occured in fast";	
			exit 1
		else	
			# copy restored image to replace the t1w_brain for feat
			cp ${sub}_T1w_brain_restore.nii.gz ${sub}_T1w_brain.nii.gz		
			echo $BLUE "--Subject" $sub "FAST done--" $NC
			echo $BLUE "--Subject" $sub "FAST done--" $NC > fast.log
		fi

	else
		# compare dates of files to check that FAST was run on the correct T1w_brain image

		# get the date of T1w_brain and fast.log
		cd $path/$sub/anat
		date_b=`stat -c%y fast.log`
		date_B=`echo $date_b | tr -d [:space:]-[:punct:]`

		# check if the fast.log is "less than" i.e. created BEFORE the T1w_brain image.
		# If this is the case then it is likely that fast needs to be rerun so RUN FAST.

		if [ "$date_B" \< "$date_A" ] ; then 
			echo $BLUE "--Subject" $sub "FAST has to be redone--" $NC; >> fast.log
			fast -t 1 -n 3 -H 0.1 -b -B -o $path/$sub/anat/${sub}_T1w_brain $path/$sub/anat/${sub}_T1w_brain

			if [ $? != 0 ] ; then	
				echo "An error occured in fast";	
				exit 1
			else	
				# copy restored image to replace the t1w_brain for feat
				cp ${sub}_T1w_brain_restore.nii.gz ${sub}_T1w_brain.nii.gz		
				echo $BLUE "--Subject" $sub "FAST done again--" $NC
				echo $BLUE "--Subject" $sub "FAST done--" $NC >> fast.log
				date_b=`stat -c%y fast.log`
				date_B=`echo $date_b | tr -d [:space:]-[:punct:]`
			fi
		fi

	fi

# Obtain bias field from the rest-bold_sbref image
	if [ ! -e $path/$sub/func/${sub}_task-rest_sbref_bias.nii.gz ] ; then	
		cd $path/$sub/func
		fast -t 2 -n 3 -H 0.1 -I 4 -l 20.0 --nopve -b -o $path/$sub/func/${sub}_task-rest_sbref $path/$sub/func/${sub}_task-rest_sbref
		date_d=`stat -c%y ${sub}_task-rest_sbref_bias.nii.gz`
		date_D=`echo $date_D | tr -d [:space:]-[:punct:]`
	fi 

# apply bias correction to rest-bold-sbref
# Again IF the bias.log file exists, test that it was created AFTER the sbref_bias.

if [ -e $path/$sub/func/bias.log ] ; then
	cd $path/$sub/func
	date_c=`stat -c%y bias.log`
	date_C=`echo $date_C | tr -d [:space:]-[:punct:]`
fi

if [ ! -e $path/$sub/func/bias.log ] || [ "$date_C" \> "$date_D" ] ; then        # NOTE: greater date means OLDER than. DO NOT CHANGE SIGN.
	if [ -e $path/$sub/func/${sub}_task-rest_sbref_bias.nii.gz ] ; then
		cd $path/$sub/func
		fslmaths ${sub}_task-rest_sbref.nii.gz -div ${sub}_task-rest_sbref_bias.nii.gz ${sub}_task-rest_sbref_bc.nii.gz
		if [ $? != 0 ] ; then	
			echo "An error occured during bias correction of sbref";	# note $? is the error output from the most recent function.
			exit 1
		else			
			echo $BLUE "--Subject" $sub "BIAS CORRECTION done--" $NC
			echo $BLUE "--Subject" $sub "BIAS CORRECTION done--" $NC > bias.log
		fi
	else
		echo "No sbref_bias_image was found for $sub"
		exit 0
	fi
fi

echo "DONE `basename $0`"

