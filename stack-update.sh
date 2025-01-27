#!/usr/bin/env bash
P_USER=${P_USER:-"root"}
P_PASS=${P_PASS:-"rootroot"}
P_URL=${P_URL:-"http://10.11.9.200:9000"}
P_PRUNE=${P_PRUNE:-"false"}
P_ENDPOINT=${P_ENDPOINT:-""}

if [ -z ${1+x} ]; then
  echo "Parameter #1 missing: stack name "
  exit 1
fi
TARGET="$1"

if [ -z ${2+x} ]; then
  echo "Parameter #2 missing: path to yml"
  exit
fi
TARGET_YML="$2"

echo "Updating $TARGET"

echo "Logging in..."
P_TOKEN=$(curl -s -X POST -H "Content-Type: application/json;charset=UTF-8" -d "{\"username\":\"$P_USER\",\"password\":\"$P_PASS\"}" "$P_URL/api/auth")
if [[ $P_TOKEN = *"jwt"* ]]; then
  echo " ... success"
else
  echo "Result: failed to login"
  exit 1
fi
T=$(echo $P_TOKEN | awk -F '"' '{print $4}')
echo "Token: $T"

if [[ $P_ENDPOINT != "" ]]; then
  echo "Getting endpoint..."
  P_ENDPOINT_ENC=$(printf %s "$P_ENDPOINT" | jq -sRr @uri)
  ENDPOINTS=$(curl -s -H "Authorization: Bearer $T" "$P_URL/api/endpoints?type=1&search=$P_ENDPOINT_ENC")
  if [[ $ENDPOINTS = "[]" ]]; then
    ENDPOINTS=$(curl -s -H "Authorization: Bearer $T" "$P_URL/api/endpoints?type=2&search=$P_ENDPOINT_ENC")
  fi
  if [[ $ENDPOINTS = "[]" ]]; then
    echo "Result: Endpoint not found."
    exit 1
  fi
  endpoint=$(echo "$ENDPOINTS"|jq --arg TARGET "$P_ENDPOINT" -jc '.[] | select(.Name == $TARGET)')
  if [[ "$endpoint" = "" ]]; then
    echo "Result: Endpoint not found."
    exit 1
  fi
  eid="$(echo "$endpoint" |jq -j ".Id")"
fi

eid=${eid:-"1"}

echo "Using Endpoint ID: $eid"

INFO=$(curl -s -H "Authorization: Bearer $T" "$P_URL/api/endpoints/$eid/docker/info")
CID=$(echo "$INFO" | awk -F '"Cluster":{"ID":"' '{print $2}' | awk -F '"' '{print $1}')
echo "Cluster ID: $CID"

echo "Getting stacks..."
STACKS=$(curl -s -H "Authorization: Bearer $T" "$P_URL/api/stacks")

#echo "/---" && echo $STACKS && echo "\\---"

stack=$(echo "$STACKS"|jq --arg TARGET "$TARGET" -jc '.[]| select(.Name == $TARGET)')

if [ ! -z "$stack" ]; then
  # Updating existing
  sid="$(echo "$stack" |jq -j ".Id")"
  name=$(echo "$stack" |jq -j ".Name")
  echo "Identified stack: $sid / $name"

  existing_env_json="$(echo -n "$stack"|jq ".Env" -jc)"
  data_prefix="{\"Id\":\"$sid\",\"StackFileContent\":\""
  method="PUT"
  add_url="/$sid?endpointId=$eid"
  echo "Updating stack..."
else
  # Creating new
  sid=""
  existing_env_json="[]"
  data_prefix="{\"Name\":\"$TARGET\",\"SwarmID\":\"$CID\",\"StackFileContent\":\""
  method="POST"
  add_url="?endpointId=$eid&method=string&type=1"
  echo "Creating stack..."
fi

dcompose=$(cat "$TARGET_YML")
dcompose="${dcompose//$'\r'/''}"
dcompose="${dcompose//$'"'/'\"'}"
echo "/-----READ_YML--------"

echo "$dcompose"
echo "\---------------------"
dcompose="${dcompose//$'\n'/'\n'}"
data_suffix="\",\"Env\":"$existing_env_json",\"Prune\":$P_PRUNE}"
sep="'"
echo "/~~~~CONVERTED_JSON~~~~~~"
echo "$data_prefix$dcompose$data_suffix"
echo "\~~~~~~~~~~~~~~~~~~~~~~~~"
echo "$data_prefix$dcompose$data_suffix" > json.tmp

UPDATE=$(curl -s \
"$P_URL/api/stacks$add_url" \
-X $method \
-H "Authorization: Bearer $T" \
-H "Content-Type: application/json;charset=UTF-8" \
            -H 'Cache-Control: no-cache'  \
            --data-binary "@json.tmp"
        )
rm json.tmp
echo "Got response: $UPDATE"
if [ -z ${UPDATE+x} ]; then
  echo "Result: failure to create/update"
  exit 1
else
  echo "Result: successfully created/updated"
  exit 0
fi
