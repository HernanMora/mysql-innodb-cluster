#!/bin/bash

set -e

if [ -f "$MYSQL_PASSWORD" ]; then
    PASSWORD=$(cat $MYSQL_PASSWORD)
else
    PASSWORD=$MYSQL_PASSWORD
fi

IFS=',' read -r -a NODES <<< "$CLUSTER_NODES"

printf -v GROUP_SEEDS "%s:33061," "${NODES[@]}"
GROUP_SEEDS="${GROUP_SEEDS%,}"

cat > /tmp/init-cluster.js <<EOF
try {
    print('\nInitializing the InnoDB cluster...\n');
    const clusterGroupSeeds = '$GROUP_SEEDS';
    const clusterUser = '$MYSQL_USER';
    const clusterPassword = '$PASSWORD';
    const clusterName = '$MYSQL_CLUSTER_NAME';
    const cluster = dba.createCluster(clusterName, {localAddress: '${NODES[0]}:33061', groupSeeds: clusterGroupSeeds, autoRejoinTries: 20});
EOF

for NODE in ${NODES[@]:1}
do
    cat >> /tmp/init-cluster.js <<EOF
    cluster.addInstance({user: clusterUser, password: clusterPassword, host: '$NODE'}, {waitRecovery: 0, localAddress: '$NODE:33061', recoveryMethod: 'clone', groupSeeds: clusterGroupSeeds, autoRejoinTries: 20});
EOF
done

cat >> /tmp/init-cluster.js <<EOF
} catch(e) {
    print('\nThe InnoDB cluster could not be created.\n\nError: ' + e.message + '\n');
}
EOF

for NODE in ${NODES[@]}
do
    /sbin/wait-for-it.sh $NODE:3306 -t 60
done

sleep 10

mysqlsh \
    --user=$MYSQL_USER \
    --password=$PASSWORD \
    --host=${NODES[0]} \
    --port=3306 \
    --interactive \
    --file=/tmp/init-cluster.js
