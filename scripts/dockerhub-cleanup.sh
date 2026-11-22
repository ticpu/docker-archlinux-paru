#!/bin/bash
# Six-month retention for the Docker Hub repositories, keyed on the
# YYYYMMDD-HHMMSS tag every build carries; the tag string sorts by time, so
# a plain string comparison against the cutoff selects expired builds.
#
# Docker Hub documents listing tags but not deleting them, and its registry
# refuses to delete a manifest that is still tagged. The tag is therefore
# removed through the undocumented endpoint the Hub UI uses. The index and
# every manifest it references (platform images, attestations) are then
# deleted through the documented registry API: deleting only the index
# would leave its children behind as untagged orphans nothing can list.
#
# Docker Hub rate-limits API calls, so the first failure ends the run and
# nothing is retried: a failed tag delete with a warning and exit 0, any
# other failure (listing, tokens, a registry delete) with exit 1.
#
# Usage: DOCKERHUB_USERNAME=... DOCKERHUB_TOKEN=... dockerhub-cleanup.sh repo...
# DRY_RUN=1 prints every action without taking it. RETENTION is a GNU date
# relative time, default "6 months".
set -euo pipefail

cutoff=$(date -u -d "${RETENTION:-6 months} ago" +%Y%m%d-%H%M%S)
accept='application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json'
deleted=0

# Reads tag names on stdin, prints those that are build tags older than $1.
expired_tags() {
	{ grep -E '^[0-9]{8}-[0-9]{6}$' || [ $? = 1 ]; } | awk -v cutoff="$1" '$0 < cutoff'
}

summary() {
	echo "${DRY_RUN:+dry-run }cutoff $cutoff: $deleted manifests deleted"
}

run() {
	if [ -n "${DRY_RUN:-}" ]; then
		echo "dry-run: $*"
		return 0
	fi
	"$@"
}

hub_token() {
	jq -n --arg u "$ns" --arg p "$DOCKERHUB_TOKEN" '{identifier: $u, secret: $p}' |
		curl -fsS -H 'Content-Type: application/json' -d @- https://hub.docker.com/v2/auth/token |
		jq -er .access_token
}

registry_token() {
	curl -fsS -u "$ns:$DOCKERHUB_TOKEN" \
		"https://auth.docker.io/token?service=registry.docker.io&scope=repository:$ns/$1:pull,push,delete" |
		jq -er .token
}

list_tags() {
	local url="https://hub.docker.com/v2/namespaces/$ns/repositories/$1/tags?page_size=100"
	while [ -n "$url" ] && [ "$url" != null ]; do
		page=$(curl -fsS -H "Authorization: Bearer $hub" "$url")
		jq -r '.results[].name' <<<"$page"
		url=$(jq -r .next <<<"$page")
	done
}

manifest_digest() {
	curl -fsS -I -H "Authorization: Bearer $reg" -H "Accept: $accept" \
		"https://registry-1.docker.io/v2/$ns/$1/manifests/$2" |
		tr -d '\r' | awk -F': ' 'tolower($1) == "docker-content-digest" {print $2}'
}

child_digests() {
	curl -fsS -H "Authorization: Bearer $reg" -H "Accept: $accept" \
		"https://registry-1.docker.io/v2/$ns/$1/manifests/$2" |
		jq -r '(.manifests // [])[].digest'
}

delete_tag() {
	curl -fsS -X DELETE -H "Authorization: Bearer $hub" \
		"https://hub.docker.com/v2/repositories/$ns/$1/tags/$2/" >/dev/null
}

delete_manifest() {
	curl -fsS -X DELETE -H "Authorization: Bearer $reg" \
		"https://registry-1.docker.io/v2/$ns/$1/manifests/$2" >/dev/null
}

cleanup_repo() {
	local repo=$1 tag tags index latest
	tags=$(list_tags "$repo")
	reg=$(registry_token "$repo")
	latest=$(manifest_digest "$repo" latest)
	for tag in $(expired_tags "$cutoff" <<<"$tags"); do
		reg=$(registry_token "$repo")
		index=$(manifest_digest "$repo" "$tag")
		if [ "$index" = "$latest" ]; then
			echo "$repo:$tag is also latest, keeping it"
			continue
		fi
		local children
		children=$(child_digests "$repo" "$index")
		if ! run delete_tag "$repo" "$tag"; then
			echo "::warning::$repo:$tag: legacy tag delete failed, stopping with the build kept"
			summary
			exit 0
		fi
		for digest in $index $children; do
			if ! run delete_manifest "$repo" "$digest"; then
				echo "::error::$repo:$tag: registry delete of $digest failed, stopping"
				summary
				exit 1
			fi
			deleted=$((deleted + 1))
		done
		echo "$repo:$tag: deleted with $(wc -w <<<"$children") child manifests"
	done
}

if [ "${1:-}" = --selftest ]; then
	printf '%s\n' latest 20250101-000000 20990101-000000 2025-01-01 20250101-00000 |
		expired_tags 20260101-000000
	exit 0
fi

ns=$DOCKERHUB_USERNAME
hub=$(hub_token)
for repo in "$@"; do
	cleanup_repo "$repo"
done
summary
