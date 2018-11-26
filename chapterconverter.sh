#!/bin/bash
#
# generate ogg text files usable in mkvmerge
# from incomplete or incompatible files
#
# usage:
# $0 $1 $2
# or, in case of spaces in file names:
# scriptname "chapter old" 'chapter new'

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
mediainfo_wo_named_chapters_check=""
mediainfo_w_names_w_lang_ind_check=""
mediainfo_w_names_wo_lang_ind_check=""

# $3 indicates filenames with spaces
if [[ $3 ]]; then
	echo -e "\nLooks like you chose a file name with spaces."
	echo "Either avoid spaces or (double) quote:"
	echo -e "\"file name\" or 'file name'\n"
	echo -e "Now, no quotes neccessary.\n"

	until [[ -e $chapterold ]]; do
		echo "Input file with chapter information."
		read -e -p "> " chapterold
	done
	until [[ $chapternew =~ [A-Za-z0-9] ]]; do
		echo -e "\nInput new chapter file."
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
		echo -e "\nInput file with chapter information."
		read -e -p "> " chapterold
	done
	until [[ $chapternew =~ [A-Za-z0-9] ]]; do
		echo -e "\nInput new chapter file."
		read -e -p "> " chapternew
	done
elif [[ -z $2 ]]; then
	chapterold=$1
	until [[ $chapternew =~ [A-Za-z0-9] ]]; do
		echo -e "\nInput new chapter file."
		read -e -p "> " chapternew
	done
fi

# check if $chapternew exists
if [[ -e $chapternew ]]; then
	echo -e "\n$chapternew already exists. Overwrite?"
	# go on when suitable answer is given
	until [[ $overwrite == @(n|N|y|Y) ]]; do
		read -e -p "y|n > " overwrite
			case $overwrite in
				n|N)
					until [[ ! -e $chapternew ]]; do
						echo -e "\nInput new chapter file."
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
cp "$chapterold" "$chapterold"-$(date +%Y%j%H%m)
chapterold1="$chapterold-$(date +%Y%j%H%m)"
sed -i 's/\r//' "$chapterold1"
sed -i '/^\s*$/d' "$chapterold1"

# no strict mode until here
set -e
set -u
set -o pipefail

### detect chapter mark files

function webvtt_detect {
# webvtt has to have WEBVTT in line 1:
# WEBVTT FILE
#
# 1
# 00:00:01.000 --> 00:00:05.000
# Prologue

if [[ -n $(cat $chapterold1 | head -n 1 | grep -e WEBVTT) ]]; then
	webvtt_check=0
else
	webvtt_check=1
fi
}

function mp4_detect {
# mp4 chapter files contain only time code <space> chapter name
# without spaces around the colons, like in
# 00:00:00.000 Prologue
# 00:00:19.987 Chapter 02

while read LINE; do
	# break if $LINE contains ' : ', like mediainfo_w_names_wo_lang_ind or mediainfo_wo_named_chapters
	if [[ $(echo "$LINE" | grep ' : ') ]]; then
		mp4_check=2
		break
	fi
	# break if $LINE does not start with $timecode, does not end with $regex
	# does end as begins (like mediainfo_wo_names)
	if [[ $(echo "$LINE"|cut -d' ' -f1) =~ ^$tc$ ]] && \
	[[ $(echo "$LINE"|cut -d' ' -f2-) =~ ^$regex$ ]] && \
	[[ $(echo "$LINE"|cut -d' ' -f1) != $(echo "$LINE"|cut -d' ' -f2-) ]] || \
 	[[ -z $LINE ]]; then
		mp4_check=0
	else 
		mp4_check=2
		break
	fi
done < "$chapterold1"
}

function eac3to_detect {
# files from eac3to lack chapter names, file begins with CHAPTER
# like in:
# CHAPTER01=00:00:00.000
# CHAPTER01NAME=
# CHAPTER02=00:08:52.490
# CHAPTER02NAME=

while read LINE; do
	## break if non-empty $LINE does not begin with CHAPTER
	if [[ -n $(echo "$LINE"|grep -E '^CHAPTER') ]] || [[ -z $LINE ]]; then
		eac3to_check=0
	else
		eac3to_check=4
		break
 	fi
	# break if non-empty $LINE does not end with $timecode or not with 'NAME='
 	if
	[[ $(echo "$LINE"|cut -d'=' -f2) =~ $tc$ ]] || [[ $(echo "$LINE") =~ NAME=$ ]] || [[ -z $LINE ]]; then
		eac3to_check=0
	else
		echo "$LINE"
		eac3to_check=4
		break
	fi
done < "$chapterold1"
}

function mediainfo_wo_named_chapters_detect {
# each line from mediainfo chapter mark without chapter names
# begins and ends with a time code:
# 00:00:00.000 : en:00:00:00.000
# 00:02:29.149 : en:00:02:29.149

# no time code at end of line is interpreted as chapter name given
while read LINE; do
	# break if non-empty $LINE does not begin with tc and does not end with tc
	if [[ $(echo "$LINE"|cut -d' ' -f1) =~ ^$tc$ ]] && \
	[[ $(echo "$LINE"|cut -d' ' -f1) == $(echo "$LINE"|cut -d':' -f5-) ]] || \
	[[ -z $LINE ]]; then
		mediainfo_wo_named_chapters_check=0
	else
		mediainfo_wo_named_chapters_check=8
		break
	fi
done < "$chapterold1"
}

function mediainfo_w_names_w_lang_ind_detect {
# each line from mediainfo chapter mark with chapter names and language
# indicator begins with a time code and ends with some not-time code:
# 00:00:00.000 : en:01. Imperial Orders
# 00:08:57.454 : en:02. Family Ambitions

# no time code at end of line is interpreted as chapter name given
while read LINE; do
	# break, if $LINE does not begin with tc, does not contain space and 
	if [[ $(echo "$LINE"|cut -d' ' -f1) =~ ^$tc$ ]] && \
	[[ $(echo "$LINE"|cut -d':' -f5-) != ^$tc$ ]] && \
	[[ $(echo "$LINE"|cut -d' ' -f3|cut -d ':' -f1) =~ ^[a-z][a-z]$ ]] && \
	[[ $(echo "$LINE"|cut -d':' -f5) =~ ^[[:print:]]*$ ]] || \
 	[[ -z $LINE ]]; then
		mediainfo_w_names_w_lang_ind_check=0
	else
		mediainfo_w_names_w_lang_ind_check=16
		break
	fi
done < "$chapterold1"
}

function mediainfo_w_names_wo_lang_ind_detect {
# each line from mediainfo chapter mark with chapter names but without language
# indicator begins with a time code an ends with some not-time code at end of line,
# which is interpreted as chapter name given, like:
# 00:00:00.000 : :Opening Credits
# 00:08:17.497 : :Skyway Motel
# 00:12:44.514 : :New York City

while read LINE; do
	# break, if $LINE does not begin with tc, does not contain space and 
	if [[ $(echo "$LINE"|cut -d' ' -f1) =~ ^$tc$ ]] && \
	[[ $(echo "$LINE"|cut -d':' -f5-) != ^$tc$ ]] && \
	[[ $(echo "$LINE"|cut -d':' -f4) =~ ^[[:space:]]$ ]] && \
	[[ $(echo "$LINE"|cut -d':' -f5) =~ ^[[:print:]]*$ ]] || \
 	[[ -z $LINE ]]; then
		mediainfo_w_names_wo_lang_ind_check=0
	else
		mediainfo_w_names_wo_lang_ind_check=32
		break
	fi
done < "$chapterold1"
}

### handle each category of chapter mark files

function webvtt_convert {
	while read LINE; do
		linecount0=$(expr 1 + "$linecount0")
		if [[ $(echo "$LINE"|cut -d' ' -f1) =~ ^$tc$ ]]; then
			linecount1=$(printf '%02d\n' $(expr 1 + "$linecount1"))
			# print line following a line containing $tc
			chaptername=$(cat $chapterold1 |head -n $(expr 1 + $linecount0)|tail -n 1)
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

function mediainfo_wo_named_chapters_convert {
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

function mediainfo_w_names_w_lang_ind_convert {
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

function mediainfo_w_names_wo_lang_ind_convert {
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

### execute detection

webvtt_detect
mp4_detect
eac3to_detect
mediainfo_wo_named_chapters_detect
mediainfo_w_names_w_lang_ind_detect
mediainfo_w_names_wo_lang_ind_detect

### execute conversion

# webvtt
if [[ $webvtt_check -eq 0 ]]; then
	webvtt_convert

# mp4
elif [[ $mp4_check -eq 0 ]]; then
	mp4_convert

# eac3to
elif [[ $eac3to_check -eq 0 ]]; then
	eac3to_convert

# mediainfo_wo_names
elif [[ $mediainfo_wo_named_chapters_check -eq 0 ]]; then
	mediainfo_wo_named_chapters_convert

# mediainfo_w_names_w_lang
elif [[ $mediainfo_w_names_w_lang_ind_check -eq 0 ]]; then
	mediainfo_w_names_w_lang_ind_convert

# mediainfo_w_names_wo_lang
elif [[ $mediainfo_w_names_wo_lang_ind_check -eq 0 ]]; then
	mediainfo_w_names_wo_lang_ind_convert

# none of the above
elif [[ $(echo $webvtt_check) -gt 0 && $(echo $mp4_check) -gt 0 && $(echo eac3to_check) -gt 0 && $(echo $mediainfo_wo_named_chapters_check) -gt 0 && $(echo $mediainfo_w_names_w_lang_ind_check) -gt 0 && $(echo $mediainfo_w_names_wo_lang_ind_check) -gt 0 ]]; then
	error=$( expr $webvtt_check + $mp4_check + $eac3to_check + $mediainfo_wo_named_chapters_check + $mediainfo_w_names_w_lang_ind_check + $mediainfo_w_names_wo_lang_ind_check )
	echo "Either there is nothing to do here, or $chapterold seems not to be a valid chapter mark file."
	echo "Error code: $error."
	echo "Please PM @derpolsper and send your chapter file and error code. Thanks!"
else
	echo "Huh? Surprise."
fi

# delete the original's copy
rm "$chapterold1"
exit
