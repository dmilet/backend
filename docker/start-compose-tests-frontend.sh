#!/bin/bash

. ./common-sudo-fix.sh

if [[ "X$1" = "X" ]]
then
    TEST_GROUP=match2
	echo TEST_GROUP default: $TEST_GROUP
else
    TEST_GROUP=$1
fi

# useful info here
# https://hharnisc.github.io/2016/06/19/integration-testing-with-docker-compose.html
# 
# good error checks and colour use here
# 

# http://bencane.com/2016/01/11/using-travis-ci-to-test-docker-builds/
# https://mike42.me/blog/how-to-set-up-docker-containers-in-travis-ci
# https://blog.codeship.com/orchestrate-containers-for-development-with-docker-compose/

# http://tldp.org/LDP/Bash-Beginners-Guide/html/sect_07_01.html
# http://www.tldp.org/LDP/abs/html/exit-status.html
# http://bencane.com/2014/09/02/understanding-exit-codes-and-how-to-use-them-in-bash-scripts/

echo start compose tests - frontend

# pwd

# ls ./s*.sh

# build specific machines
# docker-compose -f ./compose/full-stack-test/docker-compose-test-frontend.yml build --build-arg REPO=https://github.com/voteamerica/backend.git --build-arg BRANCH_NAME=docker-test --build-arg CACHEBUST=$(date +%s) cp-test-runner

$DOCKERCOMPOSE -f ./compose/full-stack-test/docker-compose-test-frontend.yml up -d

sleep 60

$DOCKER exec -it $(docker ps | grep nigh | cut -c 1-4) /run-tests.sh $TEST_GROUP
# docker logs $ (docker ps | grep nigh | cut -c 1-4)
# docker wait fullstacktest_cp-test-runner_1
EXIT_CODE=$?

$DOCKER logs fullstacktest_cp-test-runner_1

$DOCKERCOMPOSE -f ./compose/full-stack-test/docker-compose-test-frontend.yml down

echo exit code: $EXIT_CODE

if [[ $EXIT_CODE -eq 0 ]]
then
    echo "tests succeeded"
    exit 0
else 
    echo "tests failed"
    exit $EXIT_CODE
fi

