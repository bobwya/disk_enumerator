#! /bin/bash

script_path=$(readlink -f $0)
script_folder=$( dirname "${script_path}" )
script_name=$( basename "${script_path}" )

verbose=2
colour=1
unknown=0
partitions_enabled=0

display_usage ()
{
	printf "Usage: %s [OPTIONS]" "${script_name}" >&2
	if [ $# -gt 0 ]; then
		printf "\n ... unknown OPTION \"%s\"\n" "$1" >&2
	else
		printf "\n"
	fi
	short_field_width=-5
	long_field_width=-20
	printf "  %*s%*s%s\n  %*s%*s%s\n  %*s%*s%s\n  %*s%*s%s\n  %*s%*s%s\n  %*s%*s%s\n  %*s%*s%s\n  %*s%*s%s\n  %*s%*s%s\n" \
			${short_field_width} "-c[=SETTING],"																	\
				${long_field_width}  "--colour[=SETTING]" ""														\
			${short_field_width} ""																					\
				${long_field_width} ""				"disable colourisation"											\
			${short_field_width} ""																					\
				${long_field_width} ""				"SETTING='yes' or SETTING='y' enables colourisation (default)"	\
			${short_field_width} ""																					\
				${long_field_width} ""				"SETTING='no' or SETTING='n' disables colourisation"			\
			${short_field_width} "-v,"																				\
				${long_field_width} "--verbose"	"output additional information"										\
			${short_field_width} "-q,"																				\
				${long_field_width} "--quiet"		"output minimal information"									\
			${short_field_width} "-p,"																				\
				${long_field_width} "--partitions"	"output partition table information for each drive"				\
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
	printf "%s: this script requires the smartctl utility (part of smartmontools package)!\n" "${script_name}" >&2
	exit 3
fi
if ! which lspci &>/dev/null ; then
	printf "%s: this script requires the lspci utility (part of pciutils package)!\n" "${script_name}" >&2
	exit 3
fi
if ! which udevadm &>/dev/null ; then
	printf "%s: this script requires the udevadm utility!\n" "${script_name}" >&2
	exit 3
fi
if ! which parted &>/dev/null ; then
	printf "%s: this script requires the parted utility!\n" "${script_name}" >&2
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
	-p*|--partition*)
		partitions_enabled=1
		;;
	--color|--colour)
		colour=0
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
				colour=0
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
	
echo "" | gawk -vpartitions_enabled=${partitions_enabled} -vverbose=${verbose} -vcolour=${colour} '

# Uppercase first letter of each word. Uses heuristics to guess words that are not acronyms!
function convert_to_title_case(text_string,
		array_words, i, word_count)
{
	word_count=split(text_string, array_words, " ")
	text_string=""
	for (i=1; i<=word_count; ++i) {
		if ((array_words[i] ~ "^[[:alpha:]].+") && (array_words[i] ~ "(A|E|I|O|U|a|e|i|o|u)") && (length(array_words[i]) > 2))
			text_string=text_string " " toupper(substr(array_words[i],1,1)) tolower(substr(array_words[i],2))
		else
			text_string=text_string " " toupper(array_words[i])
	}
	text_string=substr(text_string, 2)
	return (text_string)
}

# Remove disk size information from model names
function strip_size_information(text_string,
                array_words, i, word_count)
{
        word_count=split(text_string, array_words, " ")
        text_string=""
        for (i=1; i<=word_count; ++i) {
                if (array_words[i] !~ "^[\,\.[:digit:]]+(M|G|T)(b|B)$")
                        text_string=text_string " " array_words[i]
        }
        text_string=substr(text_string, 2)
        return (text_string)
}

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
	command_smartctl="smartctl --scan 2>/dev/null"
	while ((command_smartctl | getline) > 0) {
		array_disk_devices[++array_disk_devices[0],"path"]=$1
	}
	close (command_smartctl)
	FS=save_FS
}



function enumerate_pci_devices(array_pci_devices,
		capability_open, command_lspci, lspci_line, pci_address, pcie_capability, save_FS)
{
	save_FS=FS
	FS=" "
	delete array_pci_devices
	array_pci_devices[0]=1
	command_lspci="lspci -vvv"
	while ((command_lspci | getline lspci_line) > 0) {
		if (lspci_line == "") {
			++array_pci_devices[0]
			capability_open=0
			continue
		}
		match(lspci_line, regexp_pci_device_node)
		if (RSTART > 0) {
			pci_address=substr(lspci_line, RSTART, RLENGTH)
			match(lspci_line, "[\:\.[:alnum:]]+[[:blank:]]+")
			device=substr(lspci_line, RSTART+RLENGTH)
			array_pci_devices[array_pci_devices[0],"address"]="0000:" pci_address
			array_pci_devices[array_pci_devices[0],"description"]=gensub(regexp_pci_device_node, "", "g", lspci_line)
			array_pci_devices[array_pci_devices[0],"description"]=gensub(regexp_leading_trailing_whitespace, "", "g", array_pci_devices[array_pci_devices[0],"description"])
			continue
		}
		
		match(lspci_line, regexp_pcie_capability)
		if (RSTART > 0) {
			array_pci_devices[array_pci_devices[0],"pcie capability"]=gensub(regexp_pcie_capability, "\\1", "g", lspci_line)
			capability_open=1
			continue
		}

		if (! capability_open)
			continue
			
		match(lspci_line, regexp_pcie_link_capability)
		if (RSTART > 0) {
			array_pci_devices[array_pci_devices[0],"pcie port"]=gensub(regexp_pcie_link_capability, "\\1", "g", lspci_line)
			array_pci_devices[array_pci_devices[0],"speed theoretical"]=gensub(regexp_pcie_link_capability, "\\2", "g", lspci_line)
			array_pci_devices[array_pci_devices[0],"width theoretical"]=gensub(regexp_pcie_link_capability, "\\3", "g", lspci_line)
			continue
		}
		match(lspci_line, regexp_pcie_link_status)
		if (RSTART > 0) {
			array_pci_devices[array_pci_devices[0],"speed status"]=gensub(regexp_pcie_link_status, "\\1", "g", lspci_line)
			array_pci_devices[array_pci_devices[0],"width status"]=gensub(regexp_pcie_link_status, "\\2", "g", lspci_line)
			continue
		}
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
	command_udevadm="udevadm info -q all \"" disk_device "\""
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
				array_disk_attributes["port"]=gensub(regexp_scsi_channel, "\\3", "g", array_subpaths[i_path])
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
	command_smartctl="smartctl -i \"" disk_device "\" 2>/dev/null"
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
	if (array_disk_attributes["model family"] == "")
		array_disk_attributes["model family"]=array_disk_attributes["device model"]
	if (array_disk_attributes["device model"] ~ "^[ [:alpha:]]+$") {
		array_disk_attributes["device model"]=convert_to_title_case(array_disk_attributes["device model"])
		array_disk_attributes["device model"]=strip_size_information(array_disk_attributes["device model"])
	}
	array_disk_attributes["model family"]=convert_to_title_case(array_disk_attributes["model family"])
	array_disk_attributes["model family"]=strip_size_information(array_disk_attributes["model family"])
	FS=save_FS
}


function get_filesystem_information(disk_device, partition_number, array_filesystem_attributes,
		command_udevadm, save_FS, value)
{
	command_udevadm=("udevadm info -x -q \"property\" \"" disk_device partition_number "" "\" 2>/dev/null")
	save_FS=FS
	FS="="
	delete array_filesystem_attributes
	while ((command_udevadm | getline) > 0) {
		value=$2
		gsub("(^'\''|'\''$)", "", value)
		gsub("\\\\x20", " ", value)
		if ($1 == "ID_FS_LABEL_ENC")
			array_filesystem_attributes["label"]=value
		else if ($1 == "ID_FS_UUID")
			array_filesystem_attributes["uuid"]=value
		else if ($1 == "ID_FS_TYPE") {
			sub("^ntfs\-3g$", "ntfs", value)
			array_filesystem_attributes["type"]=toupper(value)
			sub("^EXFAT$", "exFAT", array_filesystem_attributes["type"])
			sub("^EXT", "ext", array_filesystem_attributes["type"])
		}
	}
	close (command_udevadm)
	FS=save_FS
}


function enumerate_partition_information(disk_device, array_partition_attributes,
		array_parted_data, command_parted, parted_data, partition_flags, partition_number)
{
	delete array_partition_attributes
	array_partition_attributes[0]=0
	array_partition_attributes["partition table"]=""
	command_parted="parted -m \"" disk_device "\" unit B -s print 2>/dev/null"
	while ((command_parted | getline parted_data) > 0) {
		if (split(parted_data, array_parted_data, ":") < 6)
			continue

		if ((array_parted_data[1] == disk_device) && (array_partition_attributes["partition table"] == "")) {
			if (array_parted_data[6] == "unknown")
				break
			
			array_partition_attributes["partition table"]=toupper(array_parted_data[6])
		}
		else if (array_parted_data[1] ~ /[[:digit:]]+/) {
			partition_number=array_parted_data[1]
			array_partition_attributes[++array_partition_attributes[0], "number"]=partition_number
			array_partition_attributes[array_partition_attributes[0], "start"]=array_parted_data[2]
			array_partition_attributes[array_partition_attributes[0], "end"]=array_parted_data[3]
			array_partition_attributes[array_partition_attributes[0], "size"]=convert_size_to_readable_si(array_parted_data[4])
			array_partition_attributes[array_partition_attributes[0], "FS-type"]=array_parted_data[5]
			array_partition_attributes[array_partition_attributes[0], "partition-type"]=array_parted_data[6]
			partition_flags=gensub(";$", "", "g", array_parted_data[7])
			array_partition_attributes[array_partition_attributes[0], "flags"]=(partition_flags== "") ? "" : (" (" partition_flags ")")
			get_filesystem_information(disk_device, partition_number, array_filesystem_attributes)
			array_partition_attributes[array_partition_attributes[0], "FS-type"]=array_filesystem_attributes["type"]
			array_partition_attributes[array_partition_attributes[0], "FS-label"]=array_filesystem_attributes["label"]
			array_partition_attributes[array_partition_attributes[0], "FS-UUID"]=array_filesystem_attributes["uuid"]
		}
	}
	close (command_parted)
}


function convert_size_to_readable_si(size,
	array_si_sizes, base_size, entry, printable_si_size)
{
	split("B,KiB,MiB,GiB,TiB,PiB,EiB,ZiB,YiB", array_si_sizes, ",")
	base_size=1024
	entry=1
	for (base_size=1024; base_size<size+0; base_size*=1024)
		++entry
	
	printable_si_size=sprintf("%.2f %s", size/(base_size/1024.0), array_si_sizes[entry])
	return (printable_si_size)
}


function display_drive_info(array_disk_devices, i_disk_device)
{
	printf("%*s%s%s%s : %s %s%s%s",
					global_indent, "",  
					ttymagenta, array_disk_devices[i_disk_device,"path"], ttyreset,
					array_disk_devices[i_disk_device,"model family"],
					ttygreen, array_disk_devices[i_disk_device,"capacity"], ttyreset)	
	if ((verbose > 0) && (array_disk_devices[i_disk_device,"serial number"] != ""))
		printf(" (%s%s%s)", ttyred, array_disk_devices[i_disk_device,"serial number"], ttyreset)
	if ((verbose >= 3) 												\
		&& (array_disk_devices[i_disk_device,"channel"] != "")		\
		&& (array_disk_devices[i_disk_device,"lun"] != "")			\
		&& (array_disk_devices[i_disk_device,"port"] != ""))
		printf(" (%sChannel: %s; LUN: %s; Port %s%s)",
				ttyblue, array_disk_devices[i_disk_device,"channel"],
				array_disk_devices[i_disk_device,"lun"],
				array_disk_devices[i_disk_device,"port"], ttyreset)
	printf("\n")
	if (verbose == 0)
		return 0
		
	global_indent+=length(array_disk_devices[i_disk_device,"path"] " : ")
	if ((verbose >= 2)  &&  (array_disk_devices[i_disk_device,"device model"] != ""))
		printf("%*s%sdrive model%s: %s\n", global_indent,	"", ttyyellow, ttyreset, array_disk_devices[i_disk_device,"device model"]);
	if (array_disk_devices[i_disk_device,"user capacity"] != "")
		printf("%*s%scapacity%s: %s\n",
				global_indent,	"", ttyyellow, ttyreset, array_disk_devices[i_disk_device,"user capacity"])
	if ((verbose >= 3) && (array_disk_devices[i_disk_device,"firmware version"] != ""))
		printf("%*s%sfirmware version%s: %s\n",
				global_indent,	"", ttyyellow, ttyreset, array_disk_devices[i_disk_device,"firmware version"])
	if ((verbose >= 4) && (array_disk_devices[i_disk_device,"sata version"] != ""))
		printf("%*s%sSATA version%s: %s\n",
				global_indent,	"", ttyyellow, ttyreset, array_disk_devices[i_disk_device,"sata version"])		
	if ((verbose >= 5) && (array_disk_devices[i_disk_device,"form factor"] != ""))
		printf("%*s%sform factor%s: %s\n",
				global_indent,	"", ttyyellow, ttyreset, array_disk_devices[i_disk_device,"form factor"])
}


function display_partitions(display, array_partition_attributes, array_column_width,
		array_index, display_column, icolumn, ipartition, total_columns, total_indices, width)
{
	total_columns=split("number size start end FS-type FS-label FS-UUID partition-type flags", array_index, " ")
	for (ipartition=1; ipartition<=array_partition_attributes[0]; ++ipartition) {
		for (icolumn=1; icolumn<=total_columns; ++icolumn) {
			if (array_index[icolumn] ~ "^(number|start|end)$")
				display_column=sprintf("%d", array_partition_attributes[ipartition, array_index[icolumn]])
			else if (array_index[icolumn] ~ "^(size|partition\-type|flags)$")
				display_column=array_partition_attributes[ipartition, array_index[icolumn]]
			else if (array_index[icolumn] ~ "^FS\-.+$")
				display_column=("\"" array_partition_attributes[ipartition, array_index[icolumn]] "\"")
			if (! display) {
				width=length(display_column)
				if ((ipartition == 1) || (width > array_column_width[array_index[icolumn]]))
					array_column_width[array_index[icolumn]]=width
				continue
			}
			
			if (array_index[icolumn] == "number")
				printf("%*s[%s%*d%s] ", global_indent, "", ttygreen, array_column_width[array_index[icolumn]], display_column, ttyreset)
			else if (array_index[icolumn] == "size")
				printf("%s%*s%s", ttycyan, array_column_width[array_index[icolumn]], display_column, ttyreset)
			else if ((array_index[icolumn] == "start") && (verbose > 4))
				printf(" %s(%0*d", ttyblue, array_column_width[array_index[icolumn]], display_column)
			else if ((array_index[icolumn] == "end") && (verbose > 4))
				printf("-%0*d)%s ", array_column_width[array_index[icolumn]], display_column, ttyreset)
			else if (array_index[icolumn] ~ "^FS\-.+$")
				printf(" %s=%s%-*s%s", array_index[icolumn], ttygreen, array_column_width[array_index[icolumn]], display_column, ttyreset)
			else if ((array_index[icolumn] ~ "^(partition\-type|flags)$") && (verbose > 3))
				printf(" %-*s", array_column_width[array_index[icolumn]], display_column)
		}
		if (display)
			printf("\n")
	}
}

		
function display_disk_partition_table_info(array_partition_attributes,
		array_column_width)
{
	if (! partitions_enabled)
		return 0

	if (array_partition_attributes["partition table"] == "") {
		printf("%*s%sno partition table%s\n", global_indent, "", ttyred, ttyreset)
		return 0
	}
	
	printf("%*s%spartition table: %s%s\n",
			global_indent, "", ttywhite, ttygreen, toupper(array_partition_attributes["partition table"]), ttyreset)
	if (verbose < 2)
		return 0

	display_partitions(0, array_partition_attributes, array_column_width)
	display_partitions(1, array_partition_attributes, array_column_width)
}


function display_pci_device_info(array_pci_devices, i_pci_device,
		controller_description, controller_type, pcie_information)
{
	controller_type=gensub("\:.+$", "", "g", array_pci_devices[i_pci_device, "description"])
	controller_description=gensub("(^[^\:]+\:|^[[:blank:]]+|[[:blank:]]+$)", "", "g", array_pci_devices[i_pci_device, "description"])
	printf("%s%s%s: %s%s%s",
				ttyyellow, controller_type, ttyreset,
				ttycyan, controller_description, ttyreset)
	if (verbose > 0)
		printf("  (%s%s%s)",
				ttyred, array_pci_devices[i_pci_device, "address"], ttyreset)
	printf("\n")
	if (verbose >= 2) {
		if ((array_pci_devices[i_pci_device,"pcie port"] != "") && (array_pci_devices[i_pci_device,"pcie capability"] != "")) {
			printf("%*s%sPCIe Version %s%s %sport %s%s:  ",
					length(controller_type)+3, "",
					ttycyan, array_pci_devices[i_pci_device,"pcie capability"], ttyreset, 
					ttymagenta, array_pci_devices[i_pci_device,"pcie port"], ttyreset)
			pcie_information=1
		}
		if ((array_pci_devices[i_pci_device,"speed status"] != "") && (array_pci_devices[i_pci_device,"width status"] != "")) {
			printf("%sspeed%s: %s%s%s ; %slanes%s: %sx%s%s",
					ttymagenta, ttyreset, ttycyan, array_pci_devices[i_pci_device,"speed status"], ttyreset,
					ttymagenta, ttyreset, ttycyan, array_pci_devices[i_pci_device,"width status"], ttyreset)
			pcie_information=1
		}
		if ((array_pci_devices[i_pci_device,"speed theoretical"] != "") && (array_pci_devices[i_pci_device,"width theoretical"] != "")) {
			printf("   %s[ speed%s: %s%s%s ; %slanes%s: %sx%s%s %s(maximum) ]%s",
					ttymagenta, ttyreset,  ttycyan, array_pci_devices[i_pci_device,"speed theoretical"], ttyreset,
					ttymagenta, ttyreset,  ttycyan, array_pci_devices[i_pci_device,"width theoretical"], ttyreset,
					ttymagenta, ttyreset)
			pcie_information=1
		}
		if (pcie_information)
			printf("\n")
	}
}


BEGIN{
	initialise_tty_colour_codes(colour)
	regexp_leading_trailing_whitespace="(^[[:blank:]]+|[[:blank:]]+$)"
	regexp_pci_device_node="^([[:alnum:]]{2}\:[[:alnum:]]{2}\.[[:alnum:]])"
	regexp_pci_address="[[:digit:]]{4}\:[[:digit:]]{2}\:[[:alnum:]]{2}\.[[:alnum:]]"
	regexp_scsi_channel="([[:digit:]]+)\:([[:digit:]]+)\:([[:alnum:]]+)\:([[:alnum:]]+)"
	regexp_pcie_capability="^[[:blank:]]+Capabilities\:[[:blank:]]+[\[][[:alnum:]]{2}[\]][[:blank:]]Express[[:blank:]]+[\(]v([[:digit:]]+)[\)].+Endpoint.+$"
	regexp_pcie_link_capability="^[[:blank:]]+LnkCap\:[[:blank:]]+Port[[:blank:]]+(\#[[:digit:]]+)\,[[:blank:]]+Speed[[:blank:]]+([\.\/[:alnum:]]+)\,[[:blank:]]+Width[[:blank:]]+x([[:digit:]]+)\,.+$"
	regexp_pcie_link_status="^[[:blank:]]+LnkSta\:[[:blank:]]+Speed[[:blank:]]+([\.\/[:alnum:]]+)\,[[:blank:]]+Width[[:blank:]]+x([[:digit:]]+)\,.+$"
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
				printf("\n")
				display_pci_device_info(array_pci_devices, i_pci_device)
			}
			global_indent=4
			display_drive_info(array_disk_devices, i_disk_device)
			enumerate_partition_information(array_disk_devices[i_disk_device, "path"], array_partition_attributes)
			display_disk_partition_table_info(array_partition_attributes)
		}
	}
}

' 2>/dev/null
