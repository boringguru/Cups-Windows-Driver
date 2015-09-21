#!/bin/bash

#ver 1
#This script will scan installed printers and assign printers without a driver
#to one listed in defaultdriver variable.

#### User variables::

domain=DOMAIN
user=svcCups
password=$( cat /root/svcCups.password )
defaultdriver='HP Universal Printing PCL 6'
#Default print driver that this script will assign to driver-less printers.
#Case sensitive. Don't screw it up. You won't know until clients try to use.

#### END User variables

userstring=$domain\\$user%$password

if [[ $( rpcclient -U "$userstring" -c 'enumprinters' localhost ) = *"Error"* ]]; then
	echo Error calling rpcclient:
	rpcclient -U "$userstring" -c 'enumprinters' localhost
	exit 0
fi

#IFS prevents the forloop from breaking on spaces (in printer/driver names)
IFS=$( echo -en "\n\b" )


#Verify that Samba is sharing all of CUPS printers
numCupsPrinters=$( lpstat -p | grep '^printer ' | wc -l )
numSMBPrinters=$( rpcclient -U "$userstring" -c 'enumprinters' localhost | \
	grep -F 'description:[\\' | wc -l )
if [ $numCupsPrinters -ne $numSMBPrinters ]; then
	echo =====================================
	date #for logging
	echo Cups=$numCupsPrinters / SMB=$numSMBPrinters
	echo Restarting SMB due to missing printers
	systemctl restart smb cups
fi

#after restarting SMB, the server needs a few seconds before rpcclient works
i=0 #going to give up after five tries
while [ $i -lt 5 ]; do
	if [ $( rpcclient -U "$userstring" -c 'enumprinters' localhost | wc -l ) -eq 1 ]; then
		sleep 1
	fi
	i=$[$i + 1]
done

#update printers that don't have a Windows driver assigned to them
for line in $( rpcclient -U "$userstring" -c 'enumprinters' localhost | \
	grep -F 'description:[\\' ); do

	driver=$( echo $line | cut -d',' -f2 )
	if [ "$driver" == '' ]; then
		echo =====================================
		date #for logging
		echo old:$line
		printer=$( echo $line | sed -e 's/.*\\//' -e 's/,.*//' )
		rpcclient -U "$userstring" -c "setdriver \"$printer\" \"$defaultdriver\"" localhost
		echo new:$( rpcclient -U "$userstring" -c 'enumprinters' localhost | \
			grep -F 'description:[\\' | \
			grep "$printer" )
	fi
	
done
