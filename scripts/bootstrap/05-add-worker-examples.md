# Add worker node for intelligence workloads
./scripts/bootstrap/04-add-worker-node.sh --node-name worker01 --node-ip 95.216.151.243 --node-role intelligence --server-password 'gmdpnHi9qCJb'

# Add worker node for database workloads
./scripts/bootstrap/04-add-worker-node.sh --node-name worker02 --node-ip 95.216.151.244 --node-role database --server-password 'gmdpnHi9qCJb'

# Add general worker node
./scripts/bootstrap/04-add-worker-node.sh --node-name worker03 --node-ip 95.216.151.245 --node-role worker --server-password 'gmdpnHi9qCJb'
