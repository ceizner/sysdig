#!/bin/bash
set -eu

function stop() {
	docker kill sysdig-agent || true
	docker rm -f sysdig-agent || true
}


function start() {
	sudo docker pull sysdig/agent
        docker run -d --name sysdig-agent --privileged --net host --pid host -e ACCESS_KEY=6fdc4eb4-0984-44ef-b23e-ed19dc819a14 -e TAGS=example_tag:example_value -v /var/run/docker.sock:/host/var/run/docker.sock -v /dev:/host/dev -v /proc:/host/proc:ro -v /boot:/host/boot:ro -v /lib/modules:/host/lib/modules:ro -v /usr:/host/usr:ro sysdig/agent
}

case "$1" in
	start)
		stop
		start
	;;
	stop)
		stop
	;;
esac
