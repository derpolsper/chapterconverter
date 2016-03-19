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

set -e
set -u
set -o pipefail

# any time code regex
tc="[0-9]{2}:[0-9]{2}:[0-9]{2}.[0-9]{3}"

# begin reading $chapterold with first line: 0
linecount0=0
linecount1=0

# $3 indicates filenames with spaces
if [[ $3 ]]; then
	echo ""
	echo "looks like you chose a file name with spaces."
	echo "either avoid spaces or (double) quote:"
	echo "\"file name\" or 'file name'"
	echo ""
	echo "now, no quotes neccessary"

	echo "file with chapter information"
	read -e -p "> " chapterold

	echo "new chapter file"
	read -e -p "> " chapternew
fi

# either use $1 $2 for old and new chapter file name or ask for them
if [[ -z $1 ]]; then
	echo "file with chapter information"
	read -e -p "> " chapterold

	echo "new chapter file"
	read -e -p "> " chapternew
elif [[ -z $2 ]]; then
	chapterold=$1
	echo "new chapter file"
	read -e -p "> " chapternew
else
	chapterold=$1
	chapternew=$2
fi

# check if $chapterold exists
until [[ -e $chapterold ]]; do
	echo "$chapterold not found"
	echo "file with chapter information"
	read -e -p "> " chapterold
done

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

# if generated in windows or using windows tools in wine,
# removal of DOS style carriage return necessary
# avoid any change in the original $chapterold
# and avoid race conditions by "unique" *cough* naming with unix time
cp "$chapterold" "$chapterold"-$(date +%Y%j%H%m)
chapterold="$chapterold"-$(date +%Y%j%H%m)
sed -i 's/\r//' "$chapterold"

# append new lines to the end of $chapterold
# in case, last chapter name shorter than head -n x
sed -i '$s/$/\n\n\n\n\n/g'  >> "$chapterold"

###
### from eac3to ###
###
# files from eac3to lack chapter names, file begins with CHAPTER
if [[ -n $(cat $chapterold | head -n 1 | grep -e ^CHAPTER) ]]; then

	# delete lines ending with "NAME=" or "NAME=" and white
	# space from $chapterold
	sed -i '/NAME=\s*$/d' "$chapterold"

	# read $chapterold line by line
 	cat "$chapterold" | while read LINE; do

		# count linenumbers
 		linecount1=$(printf '%02d\n' $(expr 1 + "$linecount1"))

 		# write each line to $chapternew
		echo "$LINE" >> "$chapternew"

		# write to $chapternew without line break
		echo -n "CHAPTER$linecount1" >> "$chapternew"
		# append to previous written line
		echo "NAME=Chapter $linecount1" >> "$chapternew"
	done
fi


###
### from mediainfo###
###
# files from mediainfo chapter mark begins with time code
# of first chapter, always 00:00:00.000
if [[ -n $(cat $chapterold | head -n 1 | grep -e ^00:00:00.000) ]]; then
	# if no chapter name is given, first line also ends with
	# this time code
	if [[ -n $(cat $chapterold | head -n 1 | grep -e 00:00:00.000$) ]]; then
		# read $chapterold line by line
		cat "$chapterold" | while read LINE; do

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
		done
	else # assume, no time code at end of line means chapter name given
		# read $chapterold line by line
		cat "$chapterold" | while read LINE; do

			# count linenumbers
			linecount1=$(printf '%02d\n' $(expr 1 + "$linecount1"))

			# write to $chapternew without line break
			echo -n "CHAPTER$linecount1=" >> "$chapternew"
			# and append time code to previous written line
			echo "$LINE"|cut -d' ' -f1 >> "$chapternew"

			# append CHAPTER<linecount> to previous written line, no line break
			echo -n "CHAPTER$linecount1" >> "$chapternew"
			# append 'NAME=' to previous written line, no line break
			echo -n "NAME=" >> "$chapternew"
			# append chapter name to that line (all from field 5ff)
			echo "$LINE"|cut -d: -f5- >> "$chapternew"
		done
	fi
fi

###
### from webvtt
###
# webvtt files begin with WEBVTT
if [[ -n $(cat $chapterold | head -n 1 | grep -e ^WEBVTT) ]]; then
	cat "$chapterold" | while read LINE; do
		linecount0=$(expr 1 + "$linecount0")

		if [[ $(echo "$LINE"|cut -d' ' -f1) =~ ^$tc$ ]]; then

			linecount1=$(printf '%02d\n' $(expr 1 + "$linecount1"))

			# print all text following a line $tc until first empty line
			chaptername=$(cat $chapterold |head -n $(expr 4 + $linecount0)|tail -n 4|sed -e '/^$/,$d')

			# write to $chapternew without line break
			echo -n "CHAPTER$linecount1=" >> "$chapternew"
			echo "$LINE"|cut -d' ' -f1 >> "$chapternew"

			# append CHAPTER<linecount1> to previous written line, no line break
			echo -n "CHAPTER$linecount1" >> "$chapternew"
			# append 'NAME=' to previous written line, no line break
			echo -n "NAME=" >> "$chapternew"
			echo "$chaptername" >> "$chapternew"
		fi
	done

	#remove all new lines
	sed -i ':a;N;$!ba;s/\n//g' "$chapternew"
	# add new lines before each CHAPTER
	sed -i 's/CHAPTER/\nCHAPTER/g' "$chapternew"
fi

# delete the original's copy
rm "$chapterold"
exit
