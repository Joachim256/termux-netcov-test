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
}

function run_test {
	# get location
	termux-location | \
		jq -r '(.latitude | tostring) + "," + (.longitude | tostring)' \
		> location.tmp
	pid1=$!

	# run iperf3 speed test
	

	# wait for both to complete
	wait $pid1
	#wait $pid2

	# write to log
	location=$(<location.tmp)
}

check_dependencies;

while :
do
	run_test;
	sleep 30
done
