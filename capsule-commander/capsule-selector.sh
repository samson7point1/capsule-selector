#!/bin/bash

CAPLIST=/opt/capsule-commander/capsule-ip-list
#CAPDNSNAME=satellite.lab.samsonwick.com
CAPDNSNAME=$(cat /etc/rhsm/rhsm.conf | grep ^hostname | awk '{print $3}')
TESTFILENAME=transfer_test
TESTFILEMD5=50fd3e7c66e9900750732913bee2ea40
TS=`date +%m%d%Y-%H%M%S`

# Unset variables
unset best_speed best_capsule_ip

# Make sure the file with the list of capsule IPs exists and is not empty
if [[ ! -f $CAPLIST ]] || [[ ! -s $CAPLIST ]]; then
   echo "Unable to find a list of capsule IPs to check at ${CAPLIST}"
   exit 1
fi


for cip in $(cat $CAPLIST); do
   echo "Evaluating $cip"

   # Each time through the loop unset the "reachable" variable
   unset reachable

   #Ensure we can reach the host
   ping -qc4 $cip 2>&1 >/dev/null
   reachable=$?
   if [[ $reachable != "0" ]]; then
      echo "$cip is not reachable!"
   else
      # If the host is reachable, pull the test file.
      curl -sk https://${cip}/pub/${TESTFILENAME} > /dev/null
      this_speed=$((time -p curl -sk https://${cip}/pub/${TESTFILENAME} > /tmp/${TESTFILENAME}) 2>&1 | grep real | awk '{print $2}')

      # Use MD5 to ensure that the test file was actually pulled rather than an error message
      this_md5=$(md5sum /tmp/${TESTFILENAME} | awk '{print $1}')
      if [[ $this_md5 != $TESTFILEMD5 ]]; then
         echo "Transfer test file not found or corrupted during transfer, skipping $cip"
      else
         echo "Transfer speed for $cip is $this_speed seconds"
         if [[ -z ${best_speed+x} ]]; then
            echo "Best speed is not yet set, initializing with speed of ${cip} (${this_speed})"
            best_speed=$this_speed
            best_capsule_ip=$cip
         else
            echo "Checking the speed of ${cip} against ${best_capsule_ip}" 
            if (( $(echo "${this_speed} < ${best_speed}" | bc -l) )); then 
               echo "${this_speed} is faster than ${best_speed}, setting $cip as the fastest capsule."
               best_capsule_ip=$cip
	       best_speed=$this_speed
            else
               echo "${best_capsule_ip} is still the fastest responder($best_speed)"
            fi
         fi
      fi
   fi
done   

if [[ -n ${best_capsule_ip+x} ]]; then
   echo "Designatig $best_capsule_ip as the closest capsule."

   # Remove any existing "hosts" entry for the capsule
   sed -i.${TS} "/${CAPDNSNAME}/d" /etc/hosts

   # Create a hosts entry for the capsule hostname
   echo "${best_capsule_ip}	${CAPDNSNAME}" >> /etc/hosts

else
   echo "Unable to select a capsule, falling back to DNS."
   # Remove any existing "hosts" entry for the capsule
   sed -i.${TS} "/${CAPDNSNAME}/d" /etc/hosts
fi
