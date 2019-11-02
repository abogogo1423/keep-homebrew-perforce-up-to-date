#!/bin/sh

set -ex

url=https://cdist2.perforce.com/perforce/r19.1/bin.macosx1010x86_64/helix-core-server.tgz

test -n "$LAST_MODIFIED" ||
LAST_MODIFIED="Fri, 11 Oct 2019 20:53:44 GMT"

curl -I --silent --header "If-Modified-Since: $LAST_MODIFIED" $url | tr -d '\r' >out
first_line=$(head -n 1 <out)
case "$first_line" in
"HTTP/1.1 304 Not Modified")
    ;; # still up to date; nothing needs to be changed
"HTTP/1.1 200 OK")
    # not up to date
    new_last_modified="$(sed -n 's/^Last-Modified: //p' <out)"

    file=helix-core-server.tgz
    if test ! -f $file ||
        case "$(uname -s)" in
	Darwin)
	    test $(date -j -f "%a, %d %B %Y %H:%M:%S GMT" "$new_last_modified" +%s) -gt $(stat -f %m $file)
	    ;;
	*)
	    test $(date -d "$new_last_modified" +%s) -gt $(stat -c %Y $file)
	    ;;
	esac
    then
	curl --silent -o helix-core-server.tgz $url
    fi

    new_version="$(tar Oxvf $file Versions.txt | sed -n 's/^Rev\. P4D\/[^\/]*\/20\([^\/]*\)\/\([^ ]*\).*/\1-\2/p')"
    new_sha256="$(openssl dgst -sha256 $file)"
    new_sha256="${new_sha256##* }"

    file=Casks/perforce.rb
    if test ! -d homebrew-cask/.git
    then
        git init homebrew-cask
        echo "/$file" >homebrew-cask/.git/info/sparse-checkout
        git -C homebrew-cask config core.sparseCheckout true
    fi
    git -C homebrew-cask fetch --depth=1000 https://github.com/Homebrew/homebrew-cask/ master
    git -C homebrew-cask reset --hard FETCH_HEAD

    old_version=$(sed -n "s/^ *version '\\(.*\\)'$/\1/p" <homebrew-cask/$file)
    commit_message="Update perforce from $old_version to $new_version"
    sed -e "s/^\( *version '\)[^']*/\1$new_version/" \
        -e "s/^\( *sha256 '\)[^']*/\1$new_sha256/" \
        <homebrew-cask/$file >homebrew-cask/$file.new
    mv homebrew-cask/$file.new homebrew-cask/$file
    git -C homebrew-cask commit -m "$commit_message" $file

    echo "TODO: open a PR like https://github.com/Homebrew/homebrew-cask/pull/70981" >&2
    exit 1

    # Update the last.modified variable in this build definition
    if test -n "$SYSTEM_ACCESSTOKEN"
    then
        auth_header="Authorization: Bearer $SYSTEM_ACCESSTOKEN"
        url="$SYSTEM_TEAMFOUNDATIONSERVERURI$SYSTEM_TEAMPROJECTID/_apis/build/definitions/$SYSTEM_DEFINITIONID?api-version=5.0"
        original_json="$(curl --silent -H "$auth_header" -H "Accept: application/json; api-version=5.0; excludeUrls=true" "$url")"
        json="$(echo "$original_json" | sed 's/\("last.modified":{"value":"\)[^"]*/\1'"$new_last_modified"/)"
        curl --silent -X PUT -H "$auth_header" -H "Content-Type: application/json" -d "$json" "$url"
    fi
    ;;
*)
    echo "Unexpected curl result:" >&2
    cat out >&2
    exit 1
    ;;
esac
