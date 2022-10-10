#!/usr/bin/env bash

# Copyright 2022 The Pipeline Service Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

init() {
  # fetching values from env vars
  username="$username"
  password="$password"
  registry="$registry"
  image="$image"
  image_path="$registry"/"$image"

  if [[ -z "$username" || -z "$password" || -z "$registry" || -z "$image" ]]; then
    printf "Error while fetching one of more env variables. Exiting.\n" >&2
    exit 1
  fi
}

fetch_commits() {
  for i in {1..3}; do
    latest_commit_status=$(
      curl -sw '%{http_code}' -o /tmp/latest_commit.json \
      -H "Accept: application/vnd.github.VERSION.sha" \
      "https://api.github.com/repos/openshift-pipelines/pipeline-service/commits/main"
    )
    if [[ "$latest_commit_status" == "200" ]]; then
      latest_commit=$(cut -c -7 < /tmp/latest_commit.json)
    else
      if [[ "$i" -lt 3 ]]; then
        printf "Unable to fetch the latest commit. Retrying...\n"
        sleep 20
      else
        printf "Error while fetching the latest commit from GitHub. Status code: %s\n" "${latest_commit_status}" >&2
        exit 1
      fi
    fi
  done
}

tag_and_push() {
  podman login -u="$username" -p="$password" quay.io
  latest_tag_on_quay=""
  for i in {1..3}; do
    latest_tag_on_quay_resp=$(curl -sw '%{http_code}' -o /tmp/tags.json \
     -H "Authorization: Bearer $password" \
     -X GET "https://quay.io/api/v1/repository/$image_path/tag/")

    if [[ "$latest_tag_on_quay_resp" == "200" ]]; then
      latest_tag_on_quay=jq .tags[].name < /tmp/tags.json | head -1 | sed "s/\"//g"
    else
      if [[ "$i" -lt 3 ]]; then
        printf "Unable to fetch the image tags. Retrying...\n"
        sleep 10
      else
        printf "Error while fetching the image tags. Status code: %s\n" "${latest_tag_on_quay_resp}" >&2
        exit 1
      fi
    fi
  done
  podman pull -q "$image_path":"$latest_tag_on_quay"
  # verify that the image is actually pulled

  image=$(podman images "$image_path":"$latest_tag_on_quay" --format json | jq '.[0].Names')

  if [[ "$image" == "null" ]]; then
    printf "Image was not pulled due to some issue. Exiting.\n" >&2
    exit 1
  else
    printf "Image pull was successful.\n"
  fi

  podman tag "$image_path":"$latest_tag_on_quay" "$image_path":"$latest_commit"
  podman push "$image_path":"$latest_commit"
}

main() {
  init
  fetch_commits
  tag_and_push
}

if [ "${BASH_SOURCE[0]}" == "$0" ]; then
  main "$@"
fi