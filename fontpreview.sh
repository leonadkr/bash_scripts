#!/bin/bash

set_font_file_metric_text()
{
	local char_code16_start
	local char_code16_end
	local char_code10_start
	local char_code10_end
	local char_code10
	local uni_char_code
	local uni_char_code_list

	for char_code16_range in $($FC_QUERY --format="%{charset}\n" "$FONT_FILE")
	do
		IFS="-" read char_code16_start char_code16_end <<< "$char_code16_range"
		if [ -z "$char_code16_end" ]
		then
			printf -v uni_char_code '\\U%08x' "$char_code10_end"
			uni_char_code_list="$uni_char_code_list$uni_char_code"
		else
			char_code10_start=$(( 16#$char_code16_start ))
			char_code10_end=$(( 16#$char_code16_end ))

			char_code10=$char_code10_start
			while [ $char_code10 -le $char_code10_end ]
			do
				printf -v uni_char_code '\\U%08x' "$char_code10"
				uni_char_code_list="$uni_char_code_list$uni_char_code"

				char_code10=$(( $char_code10 + 1 ))
			done
		fi
	done

	FONT_FILE_METRIC_TEXT=$( printf "%b" "$uni_char_code_list" | $TR -d '\0' )
}

set_metric_text()
{
	local remove_char_list

	set_font_file_metric_text

	if [ "$METRIC_TEXT_FROM_FONT_FILE" == "TRUE" ]
	then
		METRIC_TEXT="$FONT_FILE_METRIC_TEXT"
	else
		remove_char_list="${INPUT_METRIC_TEXT//[$FONT_FILE_METRIC_TEXT]/}"
		METRIC_TEXT="${INPUT_METRIC_TEXT//[$remove_char_list]/}"
	fi
}

generate_html()
{
	local font_file_count=1
	local fontfamilyset

	$CAT > "$OUTPUT_FILE" << __HEADER
<!DOCTYPE html>
<html>

	<head>
		<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
		<title>Sample of fonts</title>
	</head>

	<body>
__HEADER

	while IFS="" read -r FONT_FILE
	do
		set_metric_text
		fontfamilyset=$( $FC_QUERY --format="%{family}\n" "$FONT_FILE" )

		if [ "$OPTION_VERBOSE" == "TRUE" ]
		then
			printf "\033[K(%d/%d) font file is proceeded\r" "$font_file_count" "$N_FONT_FILES"
			font_file_count=$(( $font_file_count + 1 ))
		fi

		$CAT >> "$OUTPUT_FILE" << __BODY

		<hr>

		<div>
			<h1>${fontfamilyset/,/<br>}</h1>
			<h2>$FONT_FILE</h2>
			<p style="font-family: '${fontfamilyset%%,*}'; border: none; width: 100%; resize: none; word-wrap: break-word" >
				$METRIC_TEXT
			</p>
		</div>
__BODY
	done <<< "$FONT_FILE_LIST"

	$CAT >> "$OUTPUT_FILE" << __FOOTER

		<hr>

	</body>
</html>
__FOOTER

	printf "\033[K%s is created\n" "$OUTPUT_FILE"
}

set_globals()
{
	readonly CAT=$( which cat ) || exit 1
	readonly SORT=$( which sort ) || exit 1
	readonly TR=$( which tr ) || exit 1
	readonly FC_LIST=$( which fc-list ) || exit 1
	readonly FC_QUERY=$( which fc-query ) || exit 1
	readonly GETOPT=$( which getopt ) || exit 1

	FONT_FILE_LIST=$( $FC_LIST --format="%{file}\n" | $SORT -u )
	read -d '' -r INPUT_METRIC_TEXT << __METRIC_TEXT
ABCDEFGHIJKLMNOPQRSTUVWXYZ
abcdefghijklmnopqrstuvwxyz
АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ
абвгдеёжзийклмнопрстуфхцчшщъыьэюя
0123456789,.:;_?!/|\\<=>-+'"\`[]{}()~@#$%^&*
゠ァアィイゥウェエォオカガキギク
ァアィイゥウェエォオカガキギク
グケゲコゴサザシジスズセゼソゾタ
ダチヂッツヅテデトドナニヌネノハ
バパヒビピフブプヘベペホボポマミ
ムメモャヤュユョヨラリルレロヮワ
ヰヱヲンヴヵヶヷヸヹヺ・ーヽヾヿ
ぁあぃいぅうぇえぉおかがきぎく
ぐけげこごさざしじすずせぜそぞた
だちぢっつづてでとどなにぬねのは
ばぱひびぴふぶぷへべぺほぼぽまみ
むめもゃやゅゆょよらりるれろゎわ
ゐゑをんゕゖ゛゜ゝゞゟ
__METRIC_TEXT
	OUTPUT_FILE="fontpreview.html"
	OPTION_VERBOSE="FALSE"
	N_FONT_FILES=0
}

print_help()
{
	$CAT << __USAGE
$0 [-f, --font font_file_list] [[-d, default] | -a, --all | -t, --text metric_text] [-o, --output output_filename]

$0 creates HTML file representing font family, path to font file and a sample text. It can use all fonts attended by fontconfig.

metric_text is used as a sample text for printing to output_filename.
If metric_text is not set or -d, --default is set, built-in default one is used, but prints only glyphs contained in the font.
font_file_list indicates comma-separated font list to preceed, otherwise uses all system fonts.
If -a or --all is set, metric_text set to all glyphs in a font.
If output_filename is not set, output to ./fontpreview.html.
If no options set, prints this text.

-h, --help:	print this text
-d, --default: use built-in default metric_text
-f, --font:	set comma-separated font list
-a, --all:	set all glyphs in a font to metric_text
-t, --text:	set metric text
-o, putput:	set output file
__USAGE
}

print_summary()
{
	if [ "$METRIC_TEXT_FROM_FONT_FILE" == "TRUE" ]
	then
		printf "Metric text is from a font file.\n\n"
	else
		printf "Metric text:\n%s\n\n" "$INPUT_METRIC_TEXT"
	fi
	printf "Output file:\n%s\n\n" "$OUTPUT_FILE"
	printf "Number of font files to proceed: %d\n\n" "$N_FONT_FILES"
}

parser()
{
	local options
	local longoptions
	local parsed_options
	local font_file

	[ $# -eq 0 ] && print_help && exit 0

	options="vhdf:at:o:"
	longoptions="verbose,help,default,font:,all,text:,output:"
	parsed_options=$( getopt --options "$options" --longoptions "$longoptions" --name "$0" -- "$@" ) || exit 1
	eval set -- "$parsed_options"
	
	while true
	do
		case "$1" in
			-v|--verbose)
				OPTION_VERBOSE="TRUE"
				shift
			;;
			-h|--help)
				print_help
				exit 0
			;;
			-d|--default)
				# use global defaults
				shift
			;;
			-f|--font)
				FONT_FILE_LIST="${2//,/$'\n'}"
				shift 2
			;;
			-a|--all)
				METRIC_TEXT_FROM_FONT_FILE="TRUE"
				shift
			;;
			-t|--text)
				INPUT_METRIC_TEXT="$2"
				shift 2
			;;
			-o|--output)
				OUTPUT_FILE="$2"
				shift 2
			;;
			--)
				shift
				break
			;;
			*)
				exit 1
			;;
		esac
	done

	while IFS="" read -r font_file
	do
		[ ! -r "$font_file" ] && printf "Error: cannot read %s\n" "$font_file" 1>&2 && exit 1
		N_FONT_FILES=$(( $N_FONT_FILES + 1 ))
	done <<< "$FONT_FILE_LIST"
}

#
#	main
#
set_globals
parser "$@"
[ "$OPTION_VERBOSE" == "TRUE" ] && print_summary
generate_html
