#!/bin/bash
set -x

ADMIN_SSL_ELB=`kubectl get svc/kong-admin-ssl -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"`
echo "Hit kong-admin-ssl endpoint"
TIME=0
while [[ $TIME -ne ${TIMEOUT:=300} ]]; do
	sleep ${INTERVAL:=10}
	((TIME+=$INTERVAL))
	echo "TIME(/$TIMEOUT): $TIME"
	OUTPUT=$(curl -I -k https://$ADMIN_SSL_ELB:8444 2>&1)
	RC=$?
	if [[ $RC -eq 0 ]]; then
    echo "Kong Admin endpoint returned 200"
		break
	fi
	if [[ $TIME -eq $TIMEOUT ]]; then
		echo "TIMEOUT EXPIRED "
		exit 1
	fi
done

