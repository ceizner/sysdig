#!/bin/bash
#Description: simple statsd test suite, it covers the basic functionalities
#Authour: luigi@sysdig.com
#Date: 5/7/15

trap control_c SIGINT
trap control_c SIGTERM
PID_LIST=()

function control_c(){
        for pid in ${PID_LIST[@]}
        do
                echo ${pid}
                kill -9 ${pid}
        done
        exit 0
}

#test g type
function simulate_active_user(){
while true
do 
	echo "sysdig.statsd.page.view:$(shuf -i 2000-65000 -n 1)|g" > /dev/udp/127.0.0.1/8125
	sleep 1
done
}

#test c type
function simulate_deploy(){
while true
do
	echo "sysdig.statsd.deploy:70000|c" > /dev/udp/127.0.0.1/8125
	sleep 10
done
}
#test s type
function simulate_unique_visitors(){
while true
do
	echo -e "sysdig.statsd.unique.visitors:user1|s\nsysdig.statsd.unique.visitors:user1|s\nsysdig.statsd.unique.visitors:user2|s\nsysdig.statsd.unique.visitors:user1|s" > /dev/udp/127.0.0.1/8125
	sleep 1
done
}

#test h type
function simulate_user_access_time(){
while true
do
	echo "sysdig.statsd.user.access.time:$(shuf -i 1-10 -n 1)|h" > /dev/udp/127.0.0.1/8125
	sleep 1
done
}

#test the counter sum and sub
function test_counter_sign(){
while true
do
	echo "sysdig.statsd.sign.counter:20|c" > /dev/udp/127.0.0.1/8125
	echo "sysdig.statsd.sign.counter:+$(shuf -i 1-10 -n 1)|c" > /dev/udp/127.0.0.1/8125
	echo "sysdig.statsd.sign.counter:-$(shuf -i 1-10 -n 1)|c" > /dev/udp/127.0.0.1/8125
	sleep 1
done
}

#simple tag test
function test_tag(){
while true
do
	echo "sysdig.statsd.test.tag#tagKey1=tagValue1:1|c" > /dev/udp/127.0.0.1/8125
	sleep 1
done

}

# stressing tags
function stress_tag(){
while true
do
	TAGS="tagKey0=tagValue0"
	for i in $(seq 1 $(shuf -i 1-10 -n 1))
	do
		tag="tagKey${i}=tagValue${i}"
		TAGS="${TAGS},${tag}"
	done
	echo "sysdig.statsd.test.stress.tag#${TAGS}:1|c" > /dev/udp/127.0.0.1/8125
	sleep 1
done
}

simulate_active_user &
PID_LIST+=("${!}")
simulate_deploy &
PID_LIST+=("${!}")
simulate_unique_visitors &
PID_LIST+=("${!}")
simulate_user_access_time &
PID_LIST+=("${!}")
test_counter_sign &
PID_LIST+=("${!}")
test_tag &
PID_LIST+=("${!}")
stress_tag &
PID_LIST+=("${!}")


wait
