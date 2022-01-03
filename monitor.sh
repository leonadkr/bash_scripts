#!/bin/bash

#
#	external binaries
#
readonly TPUT=$( which tput ) || exit 1
readonly SEQ=$( which seq ) || exit 1
readonly EXPAND=$( which expand ) || exit 1


#
#	print
#
printf_and_count_lines()
{
	local term_cols=$( $TPUT cols )
	local text=$( printf "$@" | $EXPAND )
	local text_len=${#text}

	$TPUT el
	printf "$text\n"

	OUTPUT_LINE_COUNT=$(( $OUTPUT_LINE_COUNT + $text_len / ( $term_cols + 1 ) + 1 ))
}

move_cursor_to_begin()
{
	local br_text=""
	OUTPUT_LINE_COUNT=$(( $OUTPUT_LINE_COUNT ))
	for i in $( $SEQ $OUTPUT_LINE_COUNT )
	do
		br_text="$br_text\b\r"
	done
	printf "$br_text"
	OUTPUT_LINE_COUNT=0
}


#
#	CPU temperature
#
cpu_temp_prepare()
{
	local sys_class_hwmon="/sys/class/hwmon"
	[ ! -d "$sys_class_hwmon" ] && CPU_TEMP_ERROR="No directory $sys_class_hwmon" && return

	for hwmon in $sys_class_hwmon/hwmon*
	do
		[ ! -d "$hwmon" ] && CPU_TEMP_ERROR="No directory $hwmon" && return
		[ "$(<$hwmon/name)" == "coretemp" ] && SYS_CLASS_HWMON_HWMON_CORETEMP=$hwmon && return
	done
	CPU_TEMP_ERROR="No coretemps in $sys_class_hwmon" && return
}

cpu_temp_print()
{
	local cpu_sensor_label_file
	local cpu_sensor_temp_file
	local cpu_sensor_label
	local cpu_sensor_temp

	if [ -z "$CPU_TEMP_ERROR" ]
	then
		for cpu_sensor_label_file in $SYS_CLASS_HWMON_HWMON_CORETEMP/temp*_label
		do
			cpu_sensor_temp_file="${cpu_sensor_label_file/_label/_input}"

			cpu_sensor_label=$(<"$cpu_sensor_label_file")
			cpu_sensor_temp=$(( $(<"$cpu_sensor_temp_file") / 1000 ))

			printf_and_count_lines "%s: %s°C" "$cpu_sensor_label" "$cpu_sensor_temp"
		done
	else
		printf_and_count_lines "CPU temperature: %s" "$CPU_TEMP_ERROR"
	fi
}


#
#	NVIDIA GPU temperature
#
nvidia_gpu_temp_prepare()
{
	local nvidia_smi_prog_name="nvidia-smi"
	NVIDIA_SMI=$( which "$nvidia_smi_prog_name" 2> /dev/null ) || { NVIDIA_GPU_TEMP_ERROR="$nvidia_smi_prog_name is not found" && return; }
	$NVIDIA_SMI --query > /dev/null || NVIDIA_GPU_TEMP_ERROR="$nvidia_smi_prog_name error occured"
}

nvidia_gpu_temp_print()
{
	if [ -z "$NVIDIA_GPU_TEMP_ERROR" ]
	then
		local nvidia_gpu_temp=$( $NVIDIA_SMI --query-gpu=temperature.gpu --format=csv,noheader )
		printf_and_count_lines "NVidia GPU temperature: %s°C" "$nvidia_gpu_temp"
	else
		printf_and_count_lines "NVidia GPU temperature: %s" "$NVIDIA_GPU_TEMP_ERROR"
	fi
}


#
#	net traffic speed
#
net_traffic_speed_prepare()
{
	local sys_class_net="/sys/class/net"

	[ ! -d "$sys_class_net" ] && NET_TRAFFIC_SPEED_ERROR="No directory $sys_class_net" && return

	INTERFACE_ARRAY=()
	SYS_CLASS_NET_INTERFACE_STATISTICS_RX_BYTES_ARRAY=()
	SYS_CLASS_NET_INTERFACE_STATISTICS_TX_BYTES_ARRAY=()
	RX_BYTES_ARRAY=()
	TX_BYTES_ARRAY=()
	for sys_class_net_interface in $sys_class_net/*
	do
		interface="${sys_class_net_interface##*/}"
		INTERFACE_ARRAY+=( "$interface" )

		SYS_CLASS_NET_INTERFACE_STATISTICS_RX_BYTES_ARRAY+=( "$sys_class_net_interface/statistics/rx_bytes" )
		SYS_CLASS_NET_INTERFACE_STATISTICS_TX_BYTES_ARRAY+=( "$sys_class_net_interface/statistics/tx_bytes" )

		RX_BYTES_ARRAY+=( $(<"$sys_class_net_interface/statistics/rx_bytes") )
		TX_BYTES_ARRAY+=( $(<"$sys_class_net_interface/statistics/tx_bytes") )
	done

	INTERFACES_COUNT_LIST="${!INTERFACE_ARRAY[@]}"
	[ -z "$INTERFACES_COUNT_LIST" ] && NET_TRAFFIC_SPEED_ERROR="No net interfaces"
}

net_traffic_speed_print()
{
	if [ -z "$NET_TRAFFIC_SPEED_ERROR" ]
	then
		for i in $INTERFACES_COUNT_LIST
		do
			local rx_bytes=$( <"${SYS_CLASS_NET_INTERFACE_STATISTICS_RX_BYTES_ARRAY[i]}" )
			local tx_bytes=$( <"${SYS_CLASS_NET_INTERFACE_STATISTICS_TX_BYTES_ARRAY[i]}" )
			
			local rx_speed="$(( ( rx_bytes - ${RX_BYTES_ARRAY[i]} ) / 1024 ))"
			local tx_speed="$(( ( tx_bytes - ${TX_BYTES_ARRAY[i]} ) / 1024 ))"

			RX_BYTES_ARRAY[i]=$rx_bytes
			TX_BYTES_ARRAY[i]=$tx_bytes

			printf_and_count_lines "%s RX speed: %s Kb/s; TX speed: %s Kb/s" "${INTERFACE_ARRAY[i]}" "$rx_speed" "$tx_speed"
		done
	else
		printf_and_count_lines "Net traffic speed: %s" "$NET_TRAFFIC_SPEED_ERROR"
	fi
}


#
#	main loop
#
cpu_temp_prepare
nvidia_gpu_temp_prepare
net_traffic_speed_prepare

printf "Press q to quit\n"
until [ "$INPUTCHAR" == "q" ]
do
	move_cursor_to_begin

	cpu_temp_print
	nvidia_gpu_temp_print
	net_traffic_speed_print

	read -s -t 1 -n 1 INPUTCHAR
done
printf "Quit\n"
