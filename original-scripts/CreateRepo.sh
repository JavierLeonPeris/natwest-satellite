#!/bin/bash
###########################################################################################################
#                              CreateRepo.sh
#
#                              Author : Martyn Sidaway
#
#                              Date   : 25 November 2021
#
#                              Version : 2.12
#
#                              Description :
#                              Script to add custom product to satellite , create initial CV and add to CCV
#
#
#                              Parameters : -d - to set debug mode
#                              Changes:
#                              16/12/2021 MJS Changed format of record in repo.conf
#                              02/03/2022 MJS added loop to add subscription for new product
#                              to each activation key defined in versions.conf
#                              Changed while loops to use temp files , prevent child processes
#                              07/03/2022 : Corrected adding subscriptions ( was missing GA key )
#                              07/07/2022 : Change in options not available for satellite 6.10 -ignore-global-proxy true
#
##############################################################################################################

# Script to create custom products for application repos
# adding for use directly in satellite or using repo server
# name will be cp_rhel<version_<application name>
# -d debug set

# check if repo already exists or not
# if not create

#### Initialise
getopts "d" debug
export CONFFILE=/usr/local/etc/repo.conf
export VERSIONS=/usr/local/etc/versions.conf

LINE=------------------------------------------------------------------------------------------------------
Debug()
{
[[ ${debug} = "d" ]] && set -x
}
#---------------------------------------------------------------------------------------------------------
Debug
grep -vE "^#|^$"  ${CONFFILE} > $$loop # get the lines that are not commented out or blank
while read AK OSVERSION ARCH CINAME ADGROUP RECORD
do
PRODUCTNAME=cp_rhel${OSVERSION}_${ARCH}_${CINAME}
REPONAME=r_rhel${OSVERSION}_${ARCH}_${CINAME}
CVNAME=$(echo ${PRODUCTNAME/#cp/cv}-repositories)
CCVNAME=$( hammer --no-headers activation-key list \
--name ${AK}  \
--organization-id 1 \
--fields "Content View")

#---------------------------------------------------------------------------------------------------------

# check if repo exists already
# do nothing if exists
if  [[ $(hammer --no-headers product list \
--organization-id 1 \
--search ${PRODUCTNAME} | wc -l) -gt 0 ]]
then

        echo ${PRODUCTNAME} exists - skipping
        continue

fi

#---------------------------------------------------------------------------------------------------------
# modify PRODUCTNAME to drop every character up to and including x8664_  ${PRODUCTNAME#*x8664_} will leave just CI name
echo Creating Product for ${PRODUCTNAME}
echo $LINE
echo "hammer product create \
--name "${PRODUCTNAME}" \
--description "${RECORD}: Custom product for ${PRODUCTNAME#*x8664_} packages for RHEL ${OSVERSION} x86_64" \
--organization-id "1""
hammer product create \
--name "${PRODUCTNAME}" \
--description "${RECORD}: Custom product for ${PRODUCTNAME#*x8664_} packages for RHEL ${OSVERSION} x86_64" \
--organization-id "1"


#---------------------------------------------------------------------------------------------------------
echo Creating Repo $REPONAME
echo $LINE
hammer repository create \
--organization-id 1 \
--product "${PRODUCTNAME}" \
--name "${REPONAME}" \
--content-type "yum" \
--verify-ssl-on-sync false \
--url "${URL:=""}"
#--mirror-on-sync true \
#--ignore-global-proxy true

#---------------------------------------------------------------------------------------------------------
# get repo id
echo Get Repo ID for ${REPONAME}
echo $LINE
REPOID=$(hammer --no-headers repository  list \
--fields Id \
--search ${REPONAME})

echo $LINE
echo ${REPOID}

#---------------------------------------------------------------------------------------------------------
# create content view for this
echo Create content view ${CVNAME}
echo $LINE
hammer content-view create \
--name  ${CVNAME} \
--repository-ids ${REPOID} \
--organization-id 1

#---------------------------------------------------------------------------------------------------------
# add repo to content view
hammer content-view add-repository \
--name ${CVNAME} \
--organization-id 1 \
--product ${PRODUCTNAME} \
--repository ${REPONAME}

#---------------------------------------------------------------------------------------------------------

# Publish new cv
echo Publish content view ${CVNAME}
echo $LINE
hammer content-view publish \
--name ${CVNAME} \
--description "Initial content view promotion for ${CVNAME#*4_} " \
--organization-id 1

#---------------------------------------------------------------------------------------------------------
# have to get content view id first
echo Get Content view id
echo $LINE

CVID=$(hammer --no-headers content-view list \
--fields "Content View ID" \
--search ${CVNAME})

echo $LINE
echo ${CVID}
CVVERSIONID=$( hammer  content-view info \
--id $CVID  \
--fields Versions  | awk -F: '/ID/ {print $2}' | sort -n | tail -1)

#---------------------------------------------------------------------------------------------------------

echo Add new CV to composite ${CCVNAME}
echo $LINE
#
# add to existing composite view
# content-view-id = CVID for new repo

hammer content-view component add \
--component-content-view-id ${CVID} \
--latest \
--composite-content-view ${CCVNAME} \
--organization-id 1
# add subscription to activation key for new product
# hammer subscription list --organization-id 1
# need to ignore lines below if using Simple Content Access , check how to do that
# will use command below for now - based on SCA has no valid subscriptions

# need to check if we should subscriptuion and attach for existing servers
# hammer host subscription attach --host <hostname> --subscription-id <subscription id for new repo>
# or will just be for new builds  - status of valid means subscribed
# or disabled means using SCA
SUBCOUNT=$( hammer  --no-headers host list \
--organization-id 1 \
--search "subscription_status = valid"  | wc -l)

        if [[ ${SUBCOUNT} -gt 0 ]]
        then



                SUBID=$(hammer --no-headers subscription list \
                --organization-id 1 \
                --search ${PRODUCTNAME} \
                --fields Id)

                # need to add subscription to each activation key in versions.conf
                # add loop to get activation keys
                # AK is set to the GA activation key already from repo.conf , so need to
                # add ones from versions.conf also
                grep   "^${OSVERSION}" ${VERSIONS} | sort -k8  > $$tmp   ## get the correct OS and sort
                (
                # GA line should be last ( sort -k8 , sort revers on field 8 )
                # next line just add the GA to end of loop ( cludge OSVERSION.0 as base justr so loop will work)
                echo ${OSVERSION}.0 GA SUB FOR ACK  ${CCVNAME} ${AK} >> $$tmp # add the ga activation key into loop from repo.conf
                 while read MINOR LE COMPONENTID VERSION VERSIONID CVNAME ACTKEY GA
                do
                        [[ ${MINOR%.*} -ne ${OSVERSION} ]] && continue
                        echo  running loop with $MINOR $LE $COMPONENTID $VERSION $VERSIONID $CVNAME $ACTKEY $GA
                        echo adding subscriptions to activation keys for key : ${ACTKEY}
                        # add the subcription for the new custom, product to Activation key
                        hammer --no-headers activation-key add-subscription \
                        --name ${ACTKEY}  \
                        --organization-id 1 \
                        --subscription-id ${SUBID}
                done < $$tmp
                )
        rm -f $$tmp
        fi

#---------------------------------------------------------------------------------------------------------

done < $$loop
rm -f $$loop