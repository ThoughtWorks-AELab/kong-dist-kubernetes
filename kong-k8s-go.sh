#!/bin/bash

DIR_OF_ME=$(dirname $0)
DNS_ROOT=$1

cmd () {
	if [[ -z $SUB_ACCOUNT_ID ]]; then
		echo "FATAL: \$SUB_ACCOUNT_ID not set"
		exit 1
	fi
	echo "_______________"
	echo "CMD     : $1"
	OUTPUT=$( $1 2>&1 )
	RC=$?
	echo "$OUTPUT" | while read line; do echo "OUTPUT  : $line"; done
	echo "RC      : $RC"
	echo "---------------"
	return $RC
}

if [[ -z $SUB_ACCOUNT_ID ]]; then
    echo "FATAL: \$SUB_ACCOUNT_ID not set"
    exit 1
fi

if [[ -z $DNS_ROOT ]]; then
    echo "FATAL: \$DNS_ROOT not set"
    exit 1
fi
CLUSTER=k8.$DNS_ROOT
echo "cluster is->$CLUSTER"

# # setup kubectl
echo "Setup kubectl"
CONTEXT_RESULT=$($DIR_OF_ME/assume_sub_account.sh $SUB_ACCOUNT_ID "kops export kubecfg $CLUSTER --state s3://di_tf_user_bucket")
RC=$?
if [[ $RC == 0 ]]; then
  echo "Context setup"
else
  echo "context failed"
  return $RC
fi;

##################
# Cassandra
##################
cmd "kubectl apply -f cassandra.yaml"
TIME=0
TIMEOUT=60
while [[ $TIME -ne ${TIMEOUT} ]]; do
	sleep ${INTERVAL:=5}
	((TIME+=$INTERVAL))
	echo "TIME(/$TIMEOUT): $TIME"
	echo "Waiting for cassandra-0 to be up" #we can assume -0 given its a statefulset
	RESPONSE=`kubectl get pods -n default cassandra-0 -o jsonpath="{.status.phase}"`
	if [[ $RESPONSE == "Running" ]]; then
		break
	fi
	if [[ $TIME -eq $TIMEOUT ]]; then
		echo "TIMEOUT EXPIRED"
		exit 1
	fi
done

##################
# Migrations
##################
cmd "kubectl apply -f kong_migration_cassandra.yaml"
TIME=0
TIMEOUT=120
while [[ $TIME -ne ${TIMEOUT} ]]; do
	sleep ${INTERVAL:=5}
	((TIME+=$INTERVAL))
	echo "TIME(/$TIMEOUT): $TIME"
	echo "Waiting for job kong-migrations to succeed"
	RESPONSE=`kubectl get jobs -n default kong-migration -o jsonpath="{.status.succeeded}"`
	if [[ ! -z $RESPONSE && $RESPONSE == "1" ]]; then
		break
	fi
	if [[ $TIME -eq $TIMEOUT ]]; then
		echo "TIMEOUT EXPIRED"
		exit 1
	fi
done
cmd "kubectl delete -f kong_migration_cassandra.yaml" #cleanup job

##################
# Deploy the Kong
##################
cmd "kubectl apply -f kong_cassandra.yaml"
TIME=0
TIMEOUT=120
while [[ $TIME -ne ${TIMEOUT} ]]; do
	sleep ${INTERVAL:=5}
	((TIME+=$INTERVAL))
	echo "TIME(/$TIMEOUT): $TIME"
	echo "Waiting for kong-admin-ssl ELB to instantiate"
	ADMIN_SSL_ELB=`kubectl get svc/kong-admin-ssl -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"`
	if [[ ! -z $ADMIN_SSL_ELB ]]; then
		break
	fi
	if [[ $TIME -eq $TIMEOUT ]]; then
		echo "TIMEOUT EXPIRED"
		exit 1
	fi
done
