#!/bin/bash

function check_dependencies {
	if ! which termux-location > /dev/null 2>&1; then
		>&2 echo "Termux tools aren't installed"
		exit 1
	fi
	if ! which iperf3 > /dev/null 2>&1; then
		>&2 echo "iperf3 isn't installed"
		exit 1
	fi
	
	source .env
	if [ -z "$IPERF3_SERVER" ]; then
		>&2 printf "Iperf3 server wasn't specified.\n Use the IPERF3_SERVER and IPERF3_SERVER_PORT environment variables.\n"
		exit 1
	fi
}

function run_test {
	# get location
	timeout 30 termux-location | \
		jq -r '(.latitude | tostring) + "," + (.longitude | tostring)' \
		> location.tmp &
	pid1=$!

	# prepare command
	download_cmd="iperf3 -c $IPERF3_SERVER -t 15 -i0 -R -J"
	upload_cmd="iperf3 -c $IPERF3_SERVER -t 15 -i0 -J"

	if [[ -n "$IPERF3_SERVER_PORT" ]]; then
		download_cmd+=" -p $IPERF3_SERVER_PORT"
		upload_cmd+=" -p $IPERF3_SERVER_PORT"
	fi

	if [[ -n "$IPERF3_USERNAME" && -n "$IPERF3_PASSWORD" ]]; then
		if [ ! -f server-public-key.pem ]; then
			>&2 printf "No public key was found.\niperf3 requires the public key of the server. Put it in this directory under the name 'server-public-key.pem' or try disabling authentication.\n"
			exit 1
		fi

		download_cmd+=" --username $IPERF3_USERNAME"
		upload_cmd+=" --username $IPERF3_USERNAME"
		
		download_cmd+=" --rsa-public-key-path server-public-key.pem"
		upload_cmd+=" --rsa-public-key-path server-public-key.pem"
	fi

	# run iperf3 speed test
	eval $download_cmd \
		> download.tmp 2> error.tmp &
	pid2=$!

	wait $pid2
	
	# check for authentication errors
	if [[ "$(<error.tmp)" == "iperf3: error:80000002:system library::No such file or directory"* ]]; then
		>&2 printf "No server-public-key.pem present.\nYou need to put the public key of the server into this directory."
		exit 1
	fi
	if [[ "$(<error.tmp)" == "iperf3: error:1E08010C:DECODER routines::unsupported"* ]]; then
		>&2 printf "Invalid server-public-key.pem.\nMake sure you specified a valid public key for the server."
		exit 1
	fi

	if [ "$(cat download.tmp | jq -r '.error')" == "test authorization failed" ]; then
		>&2 printf "Authorization failed.\nMake sure you provided correct username, password and server public key."
		exit 1
	fi
	if [ "$(cat download.tmp | jq -r '.error')" == "the server is busy running a test. try again later" ]; then
		>&2 printf "The specified iperf3 server is busy.\nTry a different server. Use a private server for maximum reliability.\n"
		exit 2
	fi
	
	eval $upload_cmd \
		> upload.tmp 2> error.tmp &
	pid3=$!

	# wait for both to complete
	wait $pid1
	wait $pid3

	download=$(cat download.tmp | jq -r '.end.sum_received.bits_per_second')
	upload=$(cat upload.tmp | jq -r '.end.sum_sent.bits_per_second')

	# write to log
	location=$(<location.tmp)

	if [ -z "$location" ]; then
		>&2 printf "Unable to get location data.\nMake sure you have location enabled and set up.\n"
		exit 1
	fi

	download_mb=$(awk "BEGIN {printf \"%.1f\", $download / 1000000}")
	upload_mb=$(awk "BEGIN {printf \"%.1f\", $upload / 1000000}")

	echo "$location: $download_mb Mb/s download, $upload_mb Mb/s upload"
}

check_dependencies;

while :
do
	run_test;
	sleep 30
done
