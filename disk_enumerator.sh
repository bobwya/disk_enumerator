#! /bin/bash

script_path=$(readlink -f $0)
script_folder=$( dirname "${script_path}" )
script_name=$( basename "${script_path}" )

verbose=1
volour=0
unknown=0

display_usage ()
{
	printf "Usage: %s [OPTIONS]" "${script_name}" >&2
	if [ $# -gt 0 ]; then
		printf " ... unknown OPTION \"%s\"\n" "$1" >&2
	else
		printf "\n"
	fi
	short_field_width=-5
	long_field_width=-20
	printf "  %*s%*s%s\n  %*s%*s%s\n  %*s%*s%s\n  %*s%*s%s\n  %*s%*s%s\n  %*s%*s%s\n  %*s%*s%s\n  %*s%*s%s\n"		\
			${short_field_width} "-c[=SETTING],"																	\
				${long_field_width}  "--colour[=SETTING]" ""														\
			${short_field_width} ""																					\
				${long_field_width} ""				"enable colourisation"											\
			${short_field_width} ""																					\
				${long_field_width} ""				"SETTING='yes' or SETTING='y' enables colourisation"			\
			${short_field_width} ""																					\
				${long_field_width} ""				"SETTING='no' or SETTING='n' disables colourisation (default)"	\
			${short_field_width} "-v,"																				\
				${long_field_width} "--verbose"	"output additional information"										\
			${short_field_width} "-q,"																				\
				${long_field_width} "--quiet"		"output minimal information"									\
			${short_field_width} "-h,"																				\
				${long_field_width} "--help"		"this help message"												\
			>&2
}


if [[ $(id -u) > 0 ]]; then
	printf "%s: please run as root!\n" "${script_name}" >&2
	exit 1
fi
if ! which gawk &>/dev/null ; then
	printf "%s: this script requires gawk!\n" "${script_name}" >&2
	exit 3
fi
if ! which smartctl &>/dev/null ; then
	printf "%s: this script requires smartctl utility (part of smartmontools package)!\n" "${script_name}" >&2
	exit 3
fi
if ! which lspci &>/dev/null ; then
	printf "%s: this script requires lspci utility (part of pciutils package)!\n" "${script_name}" >&2
	exit 3
fi
if ! which udevadm &>/dev/null ; then
	printf "%s: this script requires udevadm utility!\n" "${script_name}" >&2
	exit 3
fi


for variable in "$@"; do
    case "${variable}" in
	-h|--help)
		display_usage
		exit 0
		;;
	--verbose)
		verbose=$((verbose+1))
		;;
	--quiet)
		verbose=$((verbose-1))
		;;
	--color|--colour)
		colour=1
		;;
	-c=*|--color=*|--colour=*)
		if [[ "${variable}" =~ [Nn][Oo]* ]]; then
			colour=0
		elif [[ "${variable}" =~ [Yy][Ee]*[Ss]* ]]; then
			colour=1
		else
			unknown=1
		fi
		;;
	-*)
		for ((i=1; i<${#variable}; ++i)); do
			if [[ "${variable:${i}:1}" == "v" ]]; then
				verbose=$((verbose+1))
			elif [[ "${variable:${i}:1}" == "q" ]]; then
				verbose=$((verbose-1))
			elif [[ "${variable:${i}:1}" == "c" ]]; then
				colour=1
			else
				unknown=1
			fi
		done
		;;
	*)
		unknown=1
		;;
	esac
	if [[ ${unknown} == 1 ]]; then
		display_usage "${variable}"
		exit 2
	fi
done
	
echo "" | gawk -vverbose=${verbose} -vcolour=${colour} '


function initialise_tty_colour_codes(use_colour,
		command_ttyblue, command_ttycyan, command_ttygreen, command_ttymagenta, command_ttyred, command_ttyreset, command_ttywhite, command_ttyyellow)
{
	ttyred=ttygreen=ttyyellow=ttyblue=ttymagenta=ttycyan=ttywhite=ttywhite=ttyreset=""
	if (! use_colour)
		return
	
	command_ttyred="tput setaf 1"
	command_ttyred | getline ttyred
	close(command_ttyred)
	command_ttygreen="tput setaf 2"
	command_ttygreen | getline ttygreen
	close(command_ttygreen)
	command_ttyyellow="tput setaf 3"
	command_ttyyellow | getline ttyyellow
	close(command_ttyyellow)
	command_ttyblue="tput setaf 4"
	command_ttyblue | getline ttyblue
	close(command_ttyblue)
	command_ttymagenta="tput setaf 5"
	command_ttymagenta | getline ttymagenta
	close(command_ttymagenta)
	command_ttycyan="tput setaf 6"
	command_ttycyan | getline ttycyan
	close(command_ttycyan)
	command_ttywhite="tput setaf 7"
	command_ttywhite | getline ttywhite
	close(command_ttywhite)
	command_ttyreset="tput sgr0"
	command_ttyreset | getline ttyreset
	close(command_ttyreset)
}


function enumerate_disk_devices(array_disk_devices,
		command_smartctl, pci_address, save_FS)
{
	save_FS=FS
	FS=" "
	delete array_disk_devices
	command_smartctl="smartctl --scan"
	while ((command_smartctl | getline) > 0) {
		array_disk_devices[++array_disk_devices[0],"path"]=$1
	}
	close (command_smartctl)
	FS=save_FS
}



function enumerate_pci_devices(array_pci_devices,
		command_lspci, device, save_FS)
{
	save_FS=FS
	FS=" "
	delete array_pci_devices
	command_lspci="lspci"
	while ((command_lspci | getline device) > 0) {
		match(device, "[[:alnum:]]{2}\:[[:alnum:]]{2}\.[[:alnum:]]")
		pci_address=substr(device, RSTART, RLENGTH)
		match(device, "[\:\.[:alnum:]]+[[:blank:]]+")
		device=substr(device, RSTART+RLENGTH)
		array_pci_devices[++array_pci_devices[0],"address"]="0000:" pci_address
		array_pci_devices[array_pci_devices[0],"description"]=device
	}
	close (command_lspci)
	FS=save_FS
}



function detect_pci_controller_path(disk_device, array_disk_attributes,
		array_subpaths, command_udevadm, count_subpaths, i_path, save_FS)
{
	save_FS=FS
	FS="="
	delete array_disk_attributes
	command_udevadm="udevadm info -q all -n \"" disk_device "\""
	while ((command_udevadm | getline) > 0) {
		if ($1 !~ /DEVPATH/)
			continue
		
		pci_address=""
		count_subpaths=split($2, array_subpaths, "/")
		for (i_path=1; i_path<=count_subpaths; ++i_path) {
			if (array_subpaths[i_path] ~ regexp_pci_address)
				array_disk_attributes["pci address"]=array_subpaths[i_path]
			else if (array_subpaths[i_path] ~ regexp_scsi_channel) {
				array_disk_attributes["channel"]=gensub(regexp_scsi_channel, "\\1", "g", array_subpaths[i_path])
				array_disk_attributes["lun"]=gensub(regexp_scsi_channel, "\\2", "g", array_subpaths[i_path])
			}
		}
	}
	close (command_udevadm)
	FS=save_FS
}


function enumerate_disk_device_smart_attributes(disk_device, array_disk_attributes,
		capacity, command_smartctl, field_data, field_type, intel_ssd, samsung_ssd, save_FS)
{
	save_FS=FS
	FS="\:[[:blank:]]+"
	delete array_disk_attributes
	command_smartctl="smartctl -i \"" disk_device "\""
	while ((command_smartctl | getline) > 0) {
		if (NF == 1)
			continue

		field_type=gensub(" is$", "", "g", tolower($1))
		field_data=gensub("^[^\:]+\:[[:blank:]]+", "", "g", $0)
		if (field_type == "model family") {
			if (field_data == "Samsung based SSDs")
				samsung_ssd=1
			else if (field_data ~ "^Intel.+Series.+SSDs$")
				intel_ssd=1
		}
		if (field_type == "user capacity") {
			array_disk_attributes["capacity"]=gensub("^.+[\[]|[\]].*$", "", "g", field_data)
			field_data=gensub("(^[[:blank:]]+|[\[].+[\]]|[[:blank:]]+$)", "", "g", field_data)
		}
			
		if (field_type ~ "^(device model|firmware version|form factor|model family|sata version|serial number|user capacity)$")
			array_disk_attributes[field_type]=field_data
	}
	close (command_smartctl)
	capacity=gensub("[\.][[:digit:]]+", "", "g", array_disk_attributes["capacity"])
	capacity=gensub("[^[:digit:]]", "", "g", capacity)
	if (samsung_ssd) {
		array_disk_attributes["form factor"]=(array_disk_attributes["form factor"] == "") ? "2.5 inches / M2" : array_disk_attributes["form factor"]
		array_disk_attributes["model family"]=gensub("Series$", "", "g", array_disk_attributes["device model"])
		array_disk_attributes["model family"]=gensub("SAMSUNG", "Samsung", "g", array_disk_attributes["model family"])
		array_disk_attributes["model family"]=gensub("(^[[:blank:]]+|[[:blank:]]+$|SSD|ssd)", "", "g", array_disk_attributes["model family"])
		array_disk_attributes["model family"]=array_disk_attributes["model family"] " SSD"
		array_disk_attributes["model family"]=gensub("[[:blank:]]{2,}", " ", "g", array_disk_attributes["model family"])
		array_disk_attributes["device model"]=""
		if (array_disk_attributes["model family"] ~ "(^|[^[:alnum:]])830($|[^[:alnum:]])") {
			array_disk_attributes["device model"]="MZ-7PC" capacity "D"
			array_disk_attributes["form factor"]="2.5 inches"
		}
	}
	else if (intel_ssd) {
		if (array_disk_attributes["device model"] ~ "SSDSC2BB" ((capacity+0 < 100) ? "0" : "") capacity "G4")
			array_disk_attributes["model family"]="Intel DC S3500 SSD"
	}
	if ((array_disk_attributes["device model"] ~ "[^[:alnum:]](WD60|WD50|WD40|WD30|WD20|WD10)EFRX") && (array_disk_attributes["form factor"] == ""))
		array_disk_attributes["form factor"]="3.5 inches"
	else if ((array_disk_attributes["device model"] ~ "[^[:alnum:]](WD10J|WD7500B)FCX") && (array_disk_attributes["form factor"] == ""))
		array_disk_attributes["form factor"]="2.5 inches"
	if ((array_disk_attributes["device model"] != "") && (array_disk_attributes["model family"] ~ array_disk_attributes["device model"])) {
		array_disk_attributes["model family"]=gensub(array_disk_attributes["device model"], "", "g", array_disk_attributes["model family"])
		array_disk_attributes["model family"]=gensub("(^[[:blank:]]+|[[:blank:]]+$)", "", "g", array_disk_attributes["model family"])
	}

	FS=save_FS
}


function display_drive_info(array_disk_devices, i_disk_device,
		indent)
{
	indent=4
	printf("%*s%s%s%s : %s %s%s%s",
					indent, "",  
					ttymagenta, array_disk_devices[i_disk_device,"path"], ttyreset,
					array_disk_devices[i_disk_device,"model family"],
					ttygreen, array_disk_devices[i_disk_device,"capacity"], ttyreset)	
	if ((verbose > 0) && (array_disk_devices[i_disk_device,"serial number"] != ""))
		printf(" (%s%s%s)", ttyred, array_disk_devices[i_disk_device,"serial number"], ttyreset)
	if ((verbose >= 3) && (array_disk_devices[i_disk_device,"channel"] != "") && (array_disk_devices[i_disk_device,"lun"] != ""))
		printf(" (%sChannel: %s; LUN: %s%s)", ttyblue, array_disk_devices[i_disk_device,"channel"], array_disk_devices[i_disk_device,"lun"], ttyreset)
	print
	if (verbose > 0) {
		indent+=length(array_disk_devices[i_disk_device,"path"] " : ")
		if ((verbose >= 2)  &&  (array_disk_devices[i_disk_device,"device model"] != ""))
			printf("%*s%sdrive model%s: %s\n", indent,	"", ttyyellow, ttyreset, array_disk_devices[i_disk_device,"device model"]);
		if (array_disk_devices[i_disk_device,"user capacity"] != "")
			printf("%*s%scapacity%s: %s\n",
					indent,	"", ttyyellow, ttyreset, array_disk_devices[i_disk_device,"user capacity"])
		if ((verbose >= 3) && (array_disk_devices[i_disk_device,"firmware version"] != ""))
			printf("%*s%sfirmware version%s: %s\n",
					indent,	"", ttyyellow, ttyreset, array_disk_devices[i_disk_device,"firmware version"])
		if ((verbose >= 4) && (array_disk_devices[i_disk_device,"sata version"] != ""))
			printf("%*s%sSATA version%s: %s\n",
					indent,	"", ttyyellow, ttyreset, array_disk_devices[i_disk_device,"sata version"])		
		if ((verbose >= 5) && (array_disk_devices[i_disk_device,"form factor"] != ""))
			printf("%*s%sform factor%s: %s\n",
					indent,	"", ttyyellow, ttyreset, array_disk_devices[i_disk_device,"form factor"])
	}
}


function display_pci_device_info(array_pci_devices, i_pci_device,
		controller_description, controller_type)
{
	controller_type=gensub("\:.+$", "", "g", array_pci_devices[i_pci_device, "description"])
	controller_description=gensub("(^[^\:]+\:|^[[:blank:]]+|[[:blank:]]+$)", "", "g", array_pci_devices[i_pci_device, "description"])
	printf("%s%s%s: %s%s%s",
				ttyyellow, controller_type, ttyreset,
				ttycyan, controller_description, ttyreset)
	if (verbose > 0)
		printf("  (%s%s%s)",
				ttyred, array_pci_devices[i_pci_device, "address"], ttyreset)
	print
}


BEGIN{
	initialise_tty_colour_codes(colour)
	regexp_pci_address="[[:digit:]]{4}\:[[:digit:]]{2}\:[[:alnum:]]{2}\.[[:alnum:]]"
	regexp_scsi_channel="([[:digit:]]+)\:([[:digit:]]+)\:([[:alnum:]]+)\:([[:alnum:]]+)"
}

{
	enumerate_disk_devices(array_disk_devices)
	enumerate_pci_devices(array_pci_devices)
	total_disk_devices=array_disk_devices[0]
	for ( i_disk_device=1; i_disk_device<=total_disk_devices; ++i_disk_device ) {
		detect_pci_controller_path(array_disk_devices[i_disk_device,"path"], array_disk_attributes)
		for (attribute in array_disk_attributes)
			array_disk_devices[i_disk_device,attribute]=array_disk_attributes[attribute]
		enumerate_disk_device_smart_attributes(array_disk_devices[i_disk_device,"path"], array_disk_attributes)
		for (attribute in array_disk_attributes)
			array_disk_devices[i_disk_device,attribute]=array_disk_attributes[attribute]
	}
	total_pci_devices=array_pci_devices[0]
	for ( i_pci_device=1; i_pci_device<=total_pci_devices; ++i_pci_device ) {
		is_displayed_pci=0
		for ( i_disk_device=1; i_disk_device<=total_disk_devices; ++i_disk_device ) {
			if (array_disk_devices[i_disk_device,"pci address"] != array_pci_devices[i_pci_device, "address"])
				continue

			if (! is_displayed_pci) {
				is_displayed_pci=1
				display_pci_device_info(array_pci_devices, i_pci_device)
			}
			display_drive_info(array_disk_devices, i_disk_device)
		}
	}
}

' 2>/dev/null