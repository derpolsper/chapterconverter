#!/bin/bash
#
# generate chapter files usable in mkvmerge
# from incomplete or incompatable files
#
# usage:
# $0 $1 $2
# or, in case of spaces in file names:
# scriptname "chapter old" 'chapter new'
#

# begin reading $chapterold with first line: 0
linenumber=0

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
	read -e -p "y|n > " overwrite
	
		case $overwrite in
			n|N) #
				until [[ ! -e $chapternew ]]; do
					echo "new chapter file"
					read -e -p "> " chapternew
				done
                ;;

			y|Y) # $chapternew will be overwritten
				> "$chapternew"
				;;

			*)
				echo "nah! not the best answer. begin again."
				exit
				;;
		esac
fi

# if generated in windows or using windows tools in wine,
# removal of DOS style carriage return necessary
sed -i 's/\r//' "$chapterold"

# files from eac3to lack chapter names, file begins with CHAPTER
if [[ -n $(cat $chapterold | head -n 1 | grep -e ^CHAPTER) ]]; then
	echo "from eac3to"
	
	# delete lines ending with "NAME=" or "NAME=" and white
	# space from $chapterold
	sed -i '/NAME=\s*$/d' "$chapterold"

	# read $chapterold line by line
 	cat "$chapterold" | while read LINE; do

		# count linenumbers
 		linenumber=$(printf '%02d\n' $(expr 1 + "$linenumber"))

 		# write each line to $chapternew
		echo "$LINE" >> "$chapternew"
		# write to $chapternew without line break
		echo -n "CHAPTER$linenumber" >> "$chapternew"
		# append to previous written line
		echo "NAME=Chapter $linenumber" >> "$chapternew"
	done
fi

# files from mediainfo chapter mark begins with time code
# of first chapter, always 00:00:00.000
if [[ -n $(cat $chapterold | head -n 1 | grep -e ^00:00:00.000) ]]; then
	# if no chapter name is given, first line also ends with
	# this time code
	if [[ -n $(cat $chapterold | head -n 1 | grep -e 00:00:00.000$) ]]; then
		echo "mediainfo without names"
		# read $chapterold line by line
		cat "$chapterold" | while read LINE; do

			# count linenumbers
			linenumber=$(printf '%02d\n' $(expr 1 + "$linenumber"))

			# write to $chapternew without line break
			echo -n "CHAPTER$linenumber=" >> "$chapternew"
			# and append time code to previous written line
			echo $(echo "$LINE"|cut -d' ' -f1) >> "$chapternew"
			
			# write to $chapternew without line break
			echo -n "CHAPTER$linenumber" >> "$chapternew"
			# append 'NAME=' to previous written line, no line break
			echo "NAME=Chapter $linenumber" >> "$chapternew"
		done
	else # assume, no time code at end of line means chapter name given
		# read $chapterold line by line
		echo "mediainfo with names"
		cat "$chapterold" | while read LINE; do

			# count linenumbers
			linenumber=$(printf '%02d\n' $(expr 1 + "$linenumber"))
			
			# write to $chapternew without line break
			echo -n "CHAPTER$linenumber=" >> "$chapternew"
			# and append time code to previous written line
			echo $(echo "$LINE"|cut -d' ' -f1) >> "$chapternew"
			
			# append CHAPTER<linenumber> to previous written line, no line break
			echo -n "CHAPTER$linenumber" >> "$chapternew"
			# append 'NAME=' to previous written line, no line break
			echo -n "NAME=" >> "$chapternew"
			# append chapter name to that line (all from field 5ff)
			echo $(echo "$LINE"|cut -d: -f5-) >> "$chapternew"
		done
	fi
fi

# webvtt files begin with WEBVTT
#if [[ -n $(grep -e ^WEBVTT < $chapterold |head -n 1) ]]; then
	# do something
#fi

exit