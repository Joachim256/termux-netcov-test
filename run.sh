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

	# run iperf3 speed test
	eval $download_cmd \
		> download.tmp 2> error.tmp &
	pid2=$!

	wait $pid2
	
	eval $upload_cmd \
		> upload.tmp 2> error.tmp &
	pid3=$!

	# wait for both to complete
	wait $pid1
	wait $pid3

	# write to log
	location=$(<location.tmp)
}

check_dependencies;

while :
do
	run_test;
	sleep 30
done
