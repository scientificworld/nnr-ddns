#!/usr/bin/env bash

info() {
	echo -e "`date +"%Y-%m-%d %H:%M:%S"` \033[90mINFO\033[0m $@"
}
warning() {
	echo -e "`date +"%Y-%m-%d %H:%M:%S"` \033[93mWARN\033[0m \033[30;43m$@\033[0m"
}
error() {
	echo -e "`date +"%Y-%m-%d %H:%M:%S"` \033[91mERR\033[0m \033[97;41m$@\033[0m"
	exit 1
}

CONFIG="`[[ -n "$1" ]] && echo "$1" || echo "/etc/nnr-ddns.json"`"
if [[ ! -f "$CONFIG" ]]
then
	error "config file not found"
fi
which jq >/dev/null
if [[ "$?" != "0" ]]
then
	error "jq utility not found"
fi
which curl >/dev/null
if [[ "$?" != "0" ]]
then
	error "curl utility not found"
fi

TOKEN="`cat "$CONFIG" | jq -r .token`"
PROTOCOL="`cat "$CONFIG" | jq -r .protocol`"
INTERFACE="`cat "$CONFIG" | jq .interface`"
RULES="`cat "$CONFIG" | jq -r ".rules[]"`"
CACHE="`cat "$CONFIG" | jq -r .cache`"

OPTION=""
if [[ "$PROTOCOL" = "4" ]] || [[ "$PROTOCOL" = "6" ]]
then
	OPTION="$OPTION -$PROTOCOL"
fi
if [[ "$INTERFACE" != "null" ]]
then
	OPTION="$OPTION --interface `echo "$INTERFACE" | jq -r`"
fi

mkdir -p /var/nnr-ddns

while true
do
	ip="`curl ip.sb -s $OPTION`"
	info "current ip: $ip"
	for rule in $RULES
	do
		if [[ "$CACHE" = "true" ]] && [[ -f "/var/nnr-ddns/$rule" ]]
		then
			remote="`cat "/var/nnr-ddns/$rule"`"
		else
			data="`curl https://nnr.moe/api/rules/get -s -H "Content-Type: application/json" -H "Token: $TOKEN" -X POST -d "{\\\"rid\\\": \\\"$rule\\\"}"`"
			if [[ "`echo "$data" | jq .status`" != "1" ]]
			then
				warning "unable to fetch rule $rule"
				continue
			fi
			remote="`echo "$data" | jq -r .data.remote`"
		fi
		if [[ "$remote" = "$ip" ]]
		then
			info "rule $rule is up to date"
		else
			curl https://nnr.moe/api/rules/edit -s -o /dev/null -H "Content-Type: application/json" -H "Token: $TOKEN" -X POST -d "{\"rid\": \"$rule\", \"remote\": \"$ip\", \"rport\": \"`echo "$data" | jq -r .data.rport`\", \"name\": \"`echo "$data" | jq -r .data.name`\", \"setting\": `echo "$data" | jq -r .data.setting`}"
			echo "$ip" >/var/nnr-ddns/$rule
			info "rule $rule is updated"
		fi
	done
	sleep 300
done
