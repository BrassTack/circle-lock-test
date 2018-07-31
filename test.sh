#!/usr/bin/env bats



source do-exclusively

test_data='[{ "build_num": 1, "status": "running", "branch": "foo", "subject": "Has [bar] tag"},
            { "build_num": 2, "status": "pending", "branch": "foo", "subject": "Has [bar] tag"},
            { "build_num": 3, "status": "queued", "branch": "foo", "subject": "Has [bar] tag"},
            { "build_num": 4, "status": "pending", "branch": "foo", "subject": "No tag"},
            { "build_num": 5, "status": "pending", "branch": "not-foo", "subject": "Has [bar] tag"},
            { "build_num": 6, "status": "pending", "branch": "foo", "subject": "Has [bar] tag"}]'

curl() {
    # each time our test-curl gets called, grab the next file, then delete it.
    data=$(ls -1 curl_data/* | sort | head -n1)
    cat $data
    rm $data

    # if [[ -e curl_data/1 ]]; then
    #     cat curl_data/1
    #     rm curl_data/1
    # else
    #     cat curl_data/2
    # fi
}

git() {
    echo $git_data
}

sleep() {
    echo "sleep"
}

export -f curl git sleep

teardown() {
    rm -rf curl_data
}

@test "pargse_args branch" {
    parse_args --branch "crazy branchname"
    [[ "$branch" == "crazy branchname" && -z "${tag+x}" && -z "${rest[0]+x}" ]]
}

@test "pargse_args commit tag" {
    parse_args --tag "crazy tag"
    [[ -z "${branch+x}" && "$tag" == "crazy tag" && -z "${rest[0]+x}" ]]
}

@test "pargse_args branch and tag and rest" {
    parse_args --tag "crazy tag" --branch "crazy branch" foo bar
    [[ "$tag" == "crazy tag" && "$branch" == "crazy branch" && "${rest[0]}" == "foo" && "${rest[1]}" == "bar" && -z "${rest[2]+x}" ]]
}

@test "parse_args empty" {
    parse_args
    [[ -z "${branch+x}" && -z "${tag+x}" && -z "${rest[0]+x}" ]]
}

@test "skip if wrong branch" {
    branch=foo
    CIRCLE_BRANCH=bar
    should_skip
}

@test "don't skip if right branch" {
    branch=foo
    CIRCLE_BRANCH=foo
    ! should_skip
}

@test "skip if wrong tag" {
    tag=foo
    commit_message="No tag"
    should_skip
}

@test "don't skip if right tag" {
    tag=foo
    commit_message="Has [foo] tag"
    ! should_skip
}

@test "don't skip if branch/tag unset" {
    ! should_skip
}

@test "filter on build_num" {
    CIRCLE_BUILD_NUM=6
    make_jq_prog
    result=$(echo $test_data | jq "$jq_prog")
    [[ "$result" == $'1\n2\n3\n4\n5' ]]
}

@test "filter on branch" {
    CIRCLE_BUILD_NUM=6
    branch=foo
    make_jq_prog
    result=$(echo $test_data | jq "$jq_prog")
    [[ "$result" == $'1\n2\n3\n4' ]]
}

@test "filter on tag" {
    CIRCLE_BUILD_NUM=6
    tag=bar
    make_jq_prog
    result=$(echo $test_data | jq "$jq_prog")
    [[ "$result" == $'1\n2\n3\n5' ]]
}

@test "filter on tag and branch" {
    CIRCLE_BUILD_NUM=6
    tag=bar
    branch=foo
    make_jq_prog
    result=$(echo $test_data | jq "$jq_prog")
    [[ "$result" == $'1\n2\n3' ]]
}


@test "circleci cli" {
  CIRCLE_BUILD_NUM="" run ./do-exclusively
    expected=$'Skipping do-exclusively, this appears to be a CLI build, CIRCLE_BUILD_NUM is empty'
    [[ "$output" == "$expected" ]]
}

@test "empty token" {
  CIRCLE_BUILD_NUM=6 CIRCLE_TOKEN="" run ./do-exclusively
    expected=$'ERROR: CIRCLE_TOKEN is unset or empty'
    [[ "$output" == "$expected" ]]
}

@test "unset token" {
  CIRCLE_BUILD_NUM=6 run ./do-exclusively
    expected=$'ERROR: CIRCLE_TOKEN is unset or empty'
    [[ "$output" == "$expected" ]]
}


@test "check permission denied" {
    mkdir curl_data
    # permission denied check curl call
    echo '[{"message":"Permission denied"}]' > curl_data/1
    git_data="Tagged with [bar]"
    export curl_response_1 git_data
    CIRCLE_PROJECT_USERNAME=foo CIRCLE_PROJECT_REPONAME=bar CIRCLE_BUILD_NUM=6 \
                           CIRCLE_TOKEN=abc run ./do-exclusively --tag bar echo foo
    expected=$'Checking for running builds...\nERROR: attempting to use your CIRCLE_TOKEN results in permission denied error'
    rm -rf curl_data
    [[ "$output" == "$expected" ]]
}


## wrap jq to handle faking the version number
jq() {
  if [[ "$1" == "--version" ]] && [[ "x${jq_test_version:=}" != "x" ]]
   then
    echo "${jq_test_version}"
  else
    ## a bash portable which to locate the real jq. `which` on some platforms - like bsd - only uses csh configs.
    $(builtin type -pa jq | head -n1 ) "$@"
  fi
}
export -f jq


## let e2e handle current and newer version
@test "jq old version check" {
    export jq_test_version="jq-1.3"
    CIRCLE_PROJECT_USERNAME=foo CIRCLE_BUILD_NUM=6 CIRCLE_TOKEN=abc run ./do-exclusively
    unset jq_test_version
    expected=$'ERROR: requires jq version [ jq-1.5 ] or newer, you have [ jq-1.3 ]'
    [[ "$output" == "$expected" ]]
}


@test "e2e" {
    mkdir curl_data
    # permission denied check curl call
    echo "[]" > curl_data/1
    # first curl call
    echo "$test_data" > curl_data/2
    # second curl call
    echo "[]" > curl_data/3
    git_data="Tagged with [bar]"
    export curl_response_1 curl_response_2 curl_response_3 git_data
    CIRCLE_PROJECT_USERNAME=foo CIRCLE_PROJECT_REPONAME=bar CIRCLE_BUILD_NUM=6 \
                           CIRCLE_TOKEN=abc run ./do-exclusively --tag bar echo foo
    expected=$'Checking for running builds...\nWaiting on builds:\n1\n2\n3\n5\nRetrying in 5 seconds...\nsleep\nAcquired lock\nfoo'
    echo -e "output:\n$output" > test.out
    echo -e "expected:\n$expected" >> test.out
    echo -e "test data:\n$test_data" >> test.out
    rm -rf curl_data
    [[ "$output" == "$expected" ]]
}

