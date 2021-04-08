#!/usr/bin/env bash

function array2json {
    local arr=$1
    printf '%s\n' "${arr[@]}" | jq -R . | jq -s . | jq "del(.[] | select (. == \"\"))"
}

export GARLICOIN_NETWORK_NAME=$([ "$GARLICOIN_LIVENET" == 1 ] && echo "livenet" || echo "testnet")
export API_ENABLE_CACHE=$([ "$API_ENABLE_CACHE" == 1 ] && echo "true" || echo "false")

export API_LIMIT_DISABLE=$([ "$API_LIMIT_ENABLE" == 1 ] && echo "false" || echo "true")
export API_LIMIT_WHITELIST_JSON=$(array2json $API_LIMIT_WHITELIST)
export API_LIMIT_BLACKLIST_JSON=$(array2json $API_LIMIT_BLACKLIST)

envsubst < ./garlicore-node.template.json > ./garlicore-node.json
./node_modules/.bin/garlicore-node start
