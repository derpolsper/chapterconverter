#!/bin/bash
#
# generate ogg text files usable in mkvmerge
# from incomplete or incompatible files
#
# usage:
# $0 $1 $2
# or, in case of spaces in file names:
# scriptname "chapter old" 'chapter new'
#

# any time code regex
tc="[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9]"
regex="[[:alnum:][:space:]]+"

# begin reading $chapterold with first line: 0
linecount0=0
linecount1=0

# avoid errors from unset variable
overwrite=""
webvtt_check=""
mp4_check=""
eac3to_check=""
mediainfo_wo_names_check=""
mediainfo_w_names_a_lang_check=""
mediainfo_w_names_wo_lang_check=""

# $3 indicates filenames with spaces
if [[ $3 ]]; then
	echo ""
	echo "looks like you chose a file name with spaces."
	echo "either avoid spaces or (double) quote:"
	echo "\"file name\" or 'file name'"
	echo ""
	echo "now, no quotes neccessary"

	until [[ -e $chapterold ]]; do
		echo "input file with chapter information"
		read -e -p "> " chapterold
	done
	until [[ $chapternew =~ [A-Za-z0-9] ]]; do
		echo
		echo "input new chapter file"
		read -e -p "> " chapternew
	done
fi

# use $1 $2 for old and new chapter file name
# ask for them if not given
if [[ -e $1 ]] && [[ $2 =~ [A-Za-z0-9] ]]; then
	chapterold=$1
	chapternew=$2
elif [[ ! -e $1 ]]; then
	until [[ -e $chapterold ]]; do
		echo "input file with chapter information"
		read -e -p "> " chapterold
	done
	until [[ $chapternew =~ [A-Za-z0-9] ]]; do
		echo "input new chapter file"
		read -e -p "> " chapternew
	done
elif [[ -z $2 ]]; then
	chapterold=$1
	until [[ $chapternew =~ [A-Za-z0-9] ]]; do
		echo "input new chapter file"
		read -e -p "> " chapternew
	done
fi

# check if $chapternew exists
if [[ -e $chapternew ]]; then
	echo "$chapternew already exists. Overwrite?"
	# go on when suitable answer is given
	until [[ $overwrite == @(n|N|y|Y) ]]; do
		read -e -p "y|n > " overwrite
			case $overwrite in
				n|N)
					until [[ ! -e $chapternew ]]; do
						echo "new chapter file"
						read -e -p "> " chapternew
					done
					;;

				y|Y) # overwrite $chapternew
					> "$chapternew"
					;;
			esac
	done
fi

# if $chapterold generated in windows or using windows tools in wine,
# removal of DOS style carriage return necessary
# avoid any change in the original $chapterold
# and avoid race conditions by "unique" *cough* naming with unix time
#echo "$chapterold $chapternew"
cp "$chapterold" "$chapterold"-$(date +%Y%j%H%m)
chapterold1="$chapterold-$(date +%Y%j%H%m)"
sed -i 's/\r//' "$chapterold1"
sed -i '/^\s*$/d' "$chapterold1"

# no strict mode until here
set -e
set -u
set -o pipefail

###
### detect category of chapter mark files
###

function webvtt_detect {
# append new lines to the end of $chapterold
# in case, last chapter name shorter than head -n x
sed -i '$s/$/\n\n\n\n\n/g' "$chapterold1"
# webvtt has to have WEBVTT in line 1
if [[ -n $(cat $chapterold1 | head -n 1 | grep -e WEBVTT) ]]; then
	webvtt_check=0
	echo "webvtt $webvtt_check"
else
	webvtt_check=1
	echo "else webvtt $webvtt_check"
fi
}

function mp4_detect {
# mp4 chapter files contain only
# time code <space> chapter name, like in
# 00:00:00.000 Prologue
while read LINE; do
	# break if $LINE contains ' : ', like mediainfo_w_names or mediainfo_wo_names
	if [[ $(echo "$LINE" | grep ' : ') ]]; then
		mp4_check=2
		echo "mp4 $mp4_check"
		break
	fi
	# break if $LINE does not start with $timecode, does not end with $regex
	# does end as begins (like mediainfo_wo_names)
	if [[ $(echo "$LINE"|cut -d' ' -f1) =~ ^$tc$ ]] && \
	[[ $(echo "$LINE"|cut -d' ' -f2-) =~ ^$regex$ ]] && \
	[[ $(echo "$LINE"|cut -d' ' -f1) != $(echo "$LINE"|cut -d' ' -f2-) ]] || \
 	[[ -z $LINE ]]; then
		mp4_check=0
		echo "mp4 $mp4_check"
	else 
		mp4_check=2
		echo "else mp4 $mp4_check"
		break
	fi
done < "$chapterold1"
}

function eac3to_detect {
# files from eac3to lack chapter names, file begins with CHAPTER
while read LINE; do
	## break if non-empty $LINE does not begin with CHAPTER
	if [[ -n $(echo "$LINE"|grep -E '^CHAPTER') ]] || [[ -z $LINE ]]; then
		eac3to_check=0
		echo "chapter eac3to $eac3to_check"
	else
		eac3to_check=4
		echo "else chapter eac3to $eac3to_check"
		break
 	fi
	# break if non-empty $LINE does not end with $timecode or not with 'NAME='
 	if
	[[ $(echo "$LINE"|cut -d'=' -f2) =~ $tc$ ]] || [[ $(echo "$LINE") =~ NAME=$ ]] || [[ -z $LINE ]]; then
		eac3to_check=0
		echo "tc/name eac3to $eac3to_check"
	else
		echo "$LINE"
		eac3to_check=4
		echo "else tc/name chapter eac3to $eac3to_check"
		break
	fi
done < "$chapterold1"
}

function mediainfo_wo_names_detect {
# each line from mediainfo chapter mark without chapter names
# begins and ends with a time code
# no time code at end of line is interpreted as chapter name given
while read LINE; do
	# break if non-empty $LINE does not begin with tc and does not end with tc
	if [[ $(echo "$LINE"|cut -d' ' -f1) =~ ^$tc$ ]] && \
	[[ $(echo "$LINE"|cut -d' ' -f1) == $(echo "$LINE"|cut -d':' -f5-) ]] || \
	[[ -z $LINE ]]; then
		mediainfo_wo_names_check=0
		echo "mediainfo_wo_names_check $mediainfo_wo_names_check"
	else
		mediainfo_wo_names_check=8
		echo "else mediainfo_wo_names_check $mediainfo_wo_names_check"
		break
	fi
done < "$chapterold1"
}

function mediainfo_w_names_a_lang_detect {
# each line from mediainfo chapter mark with chapter names and language
# begins with a time code an ends with some not-time code
# no time code at end of line is interpreted as chapter name given
while read LINE; do
	# break, if $LINE does not begin with tc, does not contain space and 
	if [[ $(echo "$LINE"|cut -d' ' -f1) =~ ^$tc$ ]] && \
	[[ $(echo "$LINE"|cut -d':' -f5-) != ^$tc$ ]] && \
	[[ $(echo "$LINE"|cut -d':' -f4) =~ ^[[:space:]]*[a-z][a-z]$ ]] && \
	[[ $(echo "$LINE"|cut -d':' -f5) =~ ^[[:print:]]*$ ]] || \
 	[[ -z $LINE ]]; then
		mediainfo_w_names_a_lang_check=0
		echo "mediainfo_w_names_a_lang_check $mediainfo_w_names_a_lang_check"
	else
		mediainfo_w_names_a_lang_check=16
		echo "else mediainfo_w_names_a_lang_check $mediainfo_w_names_a_lang_check"
		break
	fi
done < "$chapterold1"
}

function mediainfo_w_names_wo_lang_detect {
# each line from mediainfo chapter mark with chapter names and language
# begins with a time code an ends with some not-time code
# no time code at end of line is interpreted as chapter name given
while read LINE; do
	# break, if $LINE does not begin with tc, does not contain space and 
	if [[ $(echo "$LINE"|cut -d' ' -f1) =~ ^$tc$ ]] && \
	[[ $(echo "$LINE"|cut -d':' -f4-) != ^$tc$ ]] && \
	[[ $(echo "$LINE"|cut -d':' -f4) =~ ^[[:print:]]*$ ]] && \
	[[ -z $(echo "$LINE"|cut -d':' -f5) ]] || \
 	[[ -z $LINE ]]; then
		mediainfo_w_names_wo_lang_check=0
		echo "mediainfo_w_names_wo_lang_check $mediainfo_w_names_wo_lang_check"
	else
		mediainfo_w_names_wo_lang_check=32
		echo "else mediainfo_w_names_wo_lang_check $mediainfo_w_names_wo_lang_check"
		break
	fi
done < "$chapterold1"
}

###
### how to handle each category of chapter mark files
###

function webvtt_convert {
	while read LINE; do
		linecount0=$(expr 1 + "$linecount0")
		if [[ $(echo "$LINE"|cut -d' ' -f1) =~ ^$tc$ ]]; then
			linecount1=$(printf '%02d\n' $(expr 1 + "$linecount1"))
			# print all text following a line $tc until first empty line
			chaptername=$(cat $chapterold1 |head -n $(expr 4 + $linecount0)|tail -n 4|sed -e '/^$/,$d')
			# write to $chapternew without line break
			echo -n "CHAPTER$linecount1=" >> "$chapternew"
			echo "$LINE"|cut -d' ' -f1 >> "$chapternew"
			# add line CHAPTER<linecount1>, no line break
			echo -n "CHAPTER$linecount1" >> "$chapternew"
			# append 'NAME=' to previous written line, no line break
			echo -n "NAME=" >> "$chapternew"
			echo "$chaptername" >> "$chapternew"
		fi
	done < "$chapterold1"

	#delete all new lines
	sed -i ':a;N;$!ba;s/\n//g' "$chapternew"
	# add new lines before each CHAPTER
	sed -i 's/CHAPTER/\nCHAPTER/g' "$chapternew"
	# delete first (now ewmpty) line
	sed -i '1{/^$/d}' "$chapternew"
}

function mp4_convert {
	while read LINE; do
		# ignore empty $LINEs
		if [[ -n $LINE ]]; then
			# count linenumbers
			linecount1=$(printf '%02d\n' $(expr 1 + "$linecount1"))

			# write to $chapternew without line break
			echo -n "CHAPTER$linecount1=" >> "$chapternew"
			echo "$LINE"|cut -d' ' -f1 >> "$chapternew"

			# append CHAPTER<linecount1> to previous written line, no line break
			echo -n "CHAPTER$linecount1" >> "$chapternew"
			# append 'NAME=' to previous written line, no line break
			echo -n "NAME=" >> "$chapternew"
			echo "$LINE"|cut -d' ' -f2- >> "$chapternew"
		fi
	done < "$chapterold1"
}

function eac3to_convert {
	#delete lines ending with "NAME=" or "NAME=" plus white
	#space from $chapterold
	sed -i '/NAME=\s*$/d' "$chapterold1"
	sed -i '/^\s*$/d' "$chapterold1"
	# read $chapterold line by line
 	while read LINE; do
		# count linenumbers
 		linecount1=$(printf '%02d\n' $(expr 1 + "$linecount1"))

 		# write each line to $chapternew
		echo "$LINE" >> "$chapternew"

		# write to $chapternew without line break
		echo -n "CHAPTER$linecount1" >> "$chapternew"
		# append to previous written line
		echo "NAME=Chapter $linecount1" >> "$chapternew"
	done < "$chapterold1"
}

function mediainfo_wo_names_convert {
	while read LINE; do
		if [[ -n $LINE ]]; then
			# count linenumbers
			linecount1=$(printf '%02d\n' $(expr 1 + "$linecount1"))

			# write to $chapternew without line break
			echo -n "CHAPTER$linecount1=" >> "$chapternew"
			# and append time code to previous written line
			echo "$LINE"|cut -d' ' -f1 >> "$chapternew"

			# write to $chapternew without line break
			echo -n "CHAPTER$linecount1" >> "$chapternew"
			# append 'NAME=' to previous written line, no line break
			echo "NAME=Chapter $linecount1" >> "$chapternew"
		fi
	done < "$chapterold1"
}

function mediainfo_w_names_a_lang_convert {
	while read LINE; do
		if [[ -n $LINE ]]; then
			# count linenumbers
			linecount1=$(printf '%02d\n' $(expr 1 + "$linecount1"))

			# write to $chapternew without line break
			echo -n "CHAPTER$linecount1=" >> "$chapternew"
			# and append time code to previous written line
			echo "$LINE"|cut -d' ' -f1 >> "$chapternew"

			# write CHAPTER<linecount> without line break
			echo -n "CHAPTER$linecount1" >> "$chapternew"
			# append 'NAME=' to previous written line, no line break
			echo -n "NAME=" >> "$chapternew"
			# append chapter name to that line (all from field 5ff)
			echo "$LINE"|cut -d':' -f5- >> "$chapternew"
		fi
	done < "$chapterold1"
}

function mediainfo_w_names_wo_lang_convert {
	while read LINE; do
		if [[ -n $LINE ]]; then
			# count linenumbers
			linecount1=$(printf '%02d\n' $(expr 1 + "$linecount1"))

			# write to $chapternew without line break
			echo -n "CHAPTER$linecount1=" >> "$chapternew"
			# and append time code to previous written line
			echo "$LINE"|cut -d' ' -f1 >> "$chapternew"

			# write CHAPTER<linecount> without line break
			echo -n "CHAPTER$linecount1" >> "$chapternew"
			# append 'NAME=' to previous written line, no line break
			echo -n "NAME=" >> "$chapternew"
			# append chapter name to that line (all from field 5ff)
			echo "$LINE"|cut -d':' -f4- >> "$chapternew"
		fi
	done < "$chapterold1"
}
###
### execute detection
###

webvtt_detect
mp4_detect
eac3to_detect
mediainfo_wo_names_detect
mediainfo_w_names_a_lang_detect
mediainfo_w_names_wo_lang_detect

###
### execute conversion
###

echo ""
echo "zero executes:"
echo "webvtt_check $webvtt_check"
echo "mp4_check $mp4_check"
echo "eac3to_check $eac3to_check"
echo "mediainfo_wo_names_check $mediainfo_wo_names_check"
echo "mediainfo_w_names_a_lang_check $mediainfo_w_names_a_lang_check"
echo "mediainfo_w_names_wo_lang_check $mediainfo_w_names_wo_lang_check"
echo ""

# webvtt
if [[ $webvtt_check -eq 0 ]]; then
	webvtt_convert
	echo "webvtt_convert"

# mp4
elif [[ $mp4_check -eq 0 ]]; then
	mp4_convert
	echo "mp4_convert"

# eac3to
elif [[ $eac3to_check -eq 0 ]]; then
	eac3to_convert
	echo "eac3to_convert"

# mediainfo_wo_names
elif [[ $mediainfo_wo_names_check -eq 0 ]]; then
	mediainfo_wo_names_convert
	echo "mediainfo_wo_names_convert"

# mediainfo_w_names_a_lang
elif [[ $mediainfo_w_names_a_lang_check -eq 0 ]]; then
	mediainfo_w_names_a_lang_convert
	echo "mediainfo_w_names_a_lang_convert"

# mediainfo_w_names_wo_lang
elif [[ $mediainfo_w_names_wo_lang_check -eq 0 ]]; then
	mediainfo_w_names_wo_lang_convert
	echo "mediainfo_w_names_wo_lang_convert"

# none of the above
elif [[ $(echo $webvtt_check) -gt 0 && $(echo $mp4_check) -gt 0 && $(echo eac3to_check) -gt 0 && $(echo $mediainfo_wo_names_check) -gt 0 && $(echo $mediainfo_w_names_a_lang_check) -gt 0 && $(echo $mediainfo_w_names_wo_lang_check) -gt 0 ]]; then
	error=$( expr $webvtt_check + $mp4_check + $eac3to_check + $mediainfo_wo_names_check + $mediainfo_w_names_a_lang_check + $mediainfo_w_names_wo_lang_check )
	echo "$chapterold seems not to be a valid chapter mark file."
	echo "error code: $error."
	echo "please PM @derpolsper and send your chapter file and error code. thanks!"
else
	echo "huh? surprise."
fi

# delete the original's copy
#rm "$chapterold1"
exit
