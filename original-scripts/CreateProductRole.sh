#!/bin/bash -x
###########################################################################################################
#                              CreateProductRole.sh
#
#                              Author : Martyn Sidaway
#
#                              Date   : 30 November 2021
#
#                              Version : 2.12
#
#                              Description :
#                              Script to new product role and filters for that
#
#
#                              Parameters : -d - to set debug mode
#
#
#                              Changes: 03/03/2022
#                              changed to add AD groups rather than users
#                               24/03/2022 - changed format of user group cg_CINAME
#                               rather than same user group mapped to AD group name
#                               08/07/2022 : user-group create dropped --organization-id in 6.10 !
##############################################################################################################

#
# -d debug set

# look at using  conf file
# check if repo already exists or not
# if not create

#### Initialise
getopts "d" debug
export CONFFILE=/usr/local/etc/repo.conf
LINE=------------------------------------------------------------------------------------------------------
Debug()
{
[[ ${debug} = "d" ]] && set -x
}
#---------------------------------------------------------------------------------------------------------
Debug
# activation_key OSVERSION ARCH CINAME ADGROUP RECORD_No
grep -vE "^#|^$"  ${CONFFILE} | while read AK OSVERSION ARCH CINAME  GROUP RECORD
do
ROLE=${CINAME}-rhel${OSVERSION}
PRODUCTNAME=cp_rhel${OSVERSION}_${ARCH}_${CINAME}
USERGROUP=cg_${CINAME}
#format for usergroup name is cg_CINAME

[[ -z ${ROLE} || -z ${GROUP}  ]] \
&&  (echo no ROLENAME or GROUP values set for ${PRODUCTNAME} )\
&& continue

#---------------------------------------------------------------------------------------------------------
# check if role exists already
if [[ $(hammer --no-headers role list  --search ${ROLE} | wc -l ) -ne 0 ]]
then

        echo role ${ROLE} already exists

else

        echo creating product role ${ROLE}
        echo ${LINE}

        # create role
        hammer role create \
        --description "Repoadmin for ${PRODUCTNAME}" \
        --name ${ROLE} \
        --organization-id  1

        # create filters for product
        #Need to get permission id's for view product and edit product
        # get view product first
        echo Getting Permission ID for View Products
        echo ${LINE}
        hammer --no-headers filter available-permissions \
        --search view_products \
        --fields Id

        VP=$(hammer --no-headers filter available-permissions \
        --search view_products \
        --fields Id)
        # get edit products next
        echo Getting Permission ID for Edit Products
        echo ${LINE}
        hammer --no-headers filter available-permissions \
        --search edit_products \
        --fields Id
        EP=$(hammer --no-headers filter available-permissions \
        --search edit_products \
        --fields Id)
        echo Adding role ${ROLE} with view_products and edit_products pmerissions
        echo ${LINE}
        hammer filter create --role ${ROLE}  \
        --permission-ids ${VP},${EP} \
        --search ${PRODUCTNAME}
fi

#---------------------------------------------------------------------------------------------------------
# add group to role
# add group , and then add external group
# get external auth-source-id first
AUTHSOURCEID=$(hammer --no-headers auth-source external list --fields Id)

# check if group exists in satellite first
        if [[ $(hammer --no-headers user-group list --search ${USERGROUP} | wc -l ) -eq 0 ]]
        then

                echo Group ${USERGROUP} does not exist - cannot add them to role ${ROLE}
                echo Creating group ${USERGROUP}
                hammer user-group create  --name ${USERGROUP}  ##--organization-id 1
                echo Creating external group of ${GROUP} mapped to ${USERGROUP}
                hammer user-group external create --name ${GROUP} \
                --user-group ${USERGROUP}  \
                --auth-source-id ${AUTHSOURCEID}
        fi

   echo adding group ${USERGROUP} to role ${ROLE}
   echo ${LINE}
   hammer user-group add-role --name ${USERGROUP}  --role ${ROLE}
done
#---------------------------------------------------------------------------------------------------------