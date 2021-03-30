#!/bin/zsh
# set -x

### Description ###

# FILES
# This program will `mkdir cache' in your working directory.
# cache/json/ is for json files from youtube-dl
# cache/raw/ is for raw files from youtube-dl
# cache/output/ is for processed audio (via ffmpeg)

### Description End ###


local THIS_FILE="$0"
local SESSION_NONCE=$(mktemp -u ytrip.XXXXXXXXXX)
local CACHE=./cache
mkdir -p $CACHE/{json,raw,output}


rip_and_tag() {
	# ARGUMENTS
	id="$1"
	album="$2"
	count="$3"
	total="$4"

	# GET PREFIX
	setopt LOCAL_OPTIONS HIST_SUBST_PATTERN
	width=${#total}
	prefix="${album:gs/[^[:alnum:]]/_/}_${(l:$width::0:)count}"

	# CACHE TAGS
	cache_file=$CACHE/json/"$id".json
	if ! [[ -e $cache_file ]] ; then
		youtube-dl -J -- "$id" > $cache_file
	fi
	typeset -a tag_data=(${(f)"$(
		cat $cache_file \
		| jq -r '[.title, .uploader, .id] | join("\n")'
	)"})

	# CACHE RAW AUDIO
	has_file=($CACHE/raw/"$id".*(N))
	if ! [[ $#has_file -gt 0 ]] ; then
		youtube-dl -f bestaudio -o "$CACHE/raw/%(id)s.%(ext)s" -- "$id"
		# check if video machine 🅱️roke
		# i tried checking on the json attempt but it didnt work?
		[[ $? -ne 0 ]] && return 1
	fi

	# TAG AUDIO
	# this has to be in an array or the star is taken as a literal
	raw_file=($CACHE/raw/"$id".*)
	out_file=$CACHE/output/${prefix}_"$id".ogg
	ffmpeg -i $raw_file \
		-c:a copy \
		-metadata TITLE=$tag_data[1] \
		-metadata ARTIST=$tag_data[2] \
		-metadata ALBUM=$album \
		-metadata DESCRIPTION=$tag_data[3] \
		-metadata TRACKNUMBER=$count \
		-metadata album_artist='ytrip' \
		$out_file
	echo $out_file
}


until_it_is_done() {
	# PARSE OPTIONS
	# local -a o_album=(-A $SESSION_NONCE)
	typeset -a o_album=(-A ytrip)
	zparseopts -D -E -K -help=o_help h=o_help A:=o_album p+:=o_playlists f+:=o_files

	# PRINT HELP
	if [[ -n $o_help ]] ; then
		cat <<-EOM
		Rip and tag, until it is done.
		Usage: $THIS_FILE {-A, -p, -f} [URLS...]
		   -h, --help: Print help and exit.
		   -A   ALBUM
		   -p   PLAYLIST URL
		   -f   BATCH FILE
		   ...  VIDEO URLS
		EOM
		exit
	fi

	# GET VIDEO IDS
	album=$o_album[2]
	typeset -a id_list=(${(f)"$({
		# regex to get ids from urls
		RE_YOUTUBE='(^|(?<=youtube\.com\/watch\?v=)|(?<=youtu\.be/))([\w-]{11})(?=$|[&?#])'
		# get videos from $o_playlists
		for k v in $o_playlists ; do
			youtube-dl --flat-playlist --get-id -- "$v"
		done
		# get videos from $o_files
		for k v in $o_files ; do
			cat $v
		done \
			| grep -Po $RE_YOUTUBE
		# get videos from $@
		print -l "$@" \
			| grep -Po $RE_YOUTUBE
		})"})

	# ITERATE OVER IDS
	typeset -i count=0
	for id in $id_list ; do
		count+=1
		rip_and_tag "$id" "$album" "$count" "$#id_list"
	done
}


until_it_is_done "$@"
