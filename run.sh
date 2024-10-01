#!/bin/bash

function check_dependencies {
	if ! which termux-location > /dev/null 2>&1; then
		echo "Termux tools aren't installed" >> /dev/stderr
		exit 1
	fi
	if ! which iperf3 > /dev/null 2>&1; then
		echo "iperf3 isn't installed" >> /dev/stderr
		exit 1
	fi
	
	source .env
	if [ -z "$IPERF3_SERVER" ]; then
		printf "Iperf3 server wasn't specified.\n Use the IPERF3_SERVER and IPERF3_SERVER_PORT environment variables.\n" >> /dev/stderr
		exit 1
	fi
}

function run_test {
	# get location
	termux-location | \
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

	if [[ -n "$IPERF3_USERNAME" && -n "$IPERF3_PASSWORD"]]; then
		if [ ! -f server-public-key.pem ]; then
			printf "No public key was found.\niperf3 requires the public key of the server. Put it in this directory under the name 'server-public-key.pem' or try disabling authentication.\n" >> /dev/stderr
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
		printf "No server-public-key.pem present.\nYou need to put the public key of the server into this directory." >> /dev/stderr
		exit 1
	fi
	if [[ "$(<error.tmp)" == "iperf3: error:1E08010C:DECODER routines::unsupported"* ]]; then
		printf "Invalid server-public-key.pem.\nMake sure you specified a valid public key for the server." >> /dev/stderr
		exit 1
	fi

	if [ "$(cat download.tmp | jq -r '.error')" == "test authorization failed" ]; then
		printf "Authorization failed.\nMake sure you provided correct username, password and server public key." >> /dev/stderr
		exit 1
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
}

check_dependencies;

while :
do
	run_test;
	sleep 30
done
