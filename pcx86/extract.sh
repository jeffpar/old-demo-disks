#!/usr/bin/env bash
#
# The purpose of 'extract' is to identify all the JSON-encoded disk images listed in the manifest(s) in the
# specified directory, convert them to BINARY disk images (.img files) inside 'archive' folders, then mount the
# binary disk images and dump their contents into sub-folders of the parent 'archive' folder.
#
# extract.sh must be run in *this* directory.  It accepts one argument:
#
#	$1 is the sub-directory to search for manifests containing disk images; the default is "."
#
dir=.
if [ ! -z "$1" ]; then
	dir=$1
fi
if [ ! -d "$dir" ]; then
	echo "directory ${dir} does not exist"
	exit 1
fi
log=./extract.log
verify=true
master=false
if [ -d "archive" ]; then
	master=true
fi
find -L ${dir} -name "manifest.xml" -exec grep -H -e "<disk.*href=" {} \; > disks
while read line; do
	manFolder=`echo ${line} | sed -E "s/^([^:]*)\/manifest\.xml:.*/\1/"`
	srcFile=`echo ${line} | sed -E "s/.*href=\"([^\"]*)\".*/\1/"`
	echo "checking ${srcFile}..."
	tmpFile=`echo ${srcFile} | sed -E "s/.*\/pcx86\/(.*)/\1/"`
	if [[ ${srcFile} == http* ]]; then
		if [ ! -f "${tmpFile}" ]; then
			if [[ ${verify} == true ]]; then
				echo "missing json file: ${tmpFile}"
				continue
			fi
			tmpFolder=$(dirname "${tmpFile}")
			if [ ! -d "${tmpFolder}" ]; then
				mkdir -p ${tmpFolder}
				if [ $? -ne 0 ]; then
					echo "unable to create json folder: ${tmpFolder}"
					break
				fi
			fi
			echo "downloading ${srcFile} as ${tmpFile}..."
			curl "${srcFile}" -o ${tmpFile} -s
			if [ $? -ne 0 ]; then
				echo "unable to download file: ${srcFile}"
				break
			fi
		fi
	fi
	jsonFile=${tmpFile}
	archiveFolder=$(dirname "${jsonFile}")/archive
	diskName=$(basename "${jsonFile}" ".json")
	diskFolder=${archiveFolder}/${diskName}
	diskImage=${diskFolder}.img
	if [[ ${master} == true ]]; then
		if [[ ${line} == *img=* ]]; then
			imgFile=`echo ${line} | sed -E "s/.*img=\"([^\"]*)\".*/\1/"`
			archiveFolder=${manFolder}/$(dirname "${imgFile}")
			diskName=$(basename "${imgFile}" ".img")
			diskFolder=${archiveFolder}/${diskName}
		elif [[ ${line} == *dir=* ]]; then
			diskFolder=${manFolder}/`echo ${line} | sed -E "s/.*dir=\"([^\"]*)\".*/\1/"`
			archiveFolder=$(dirname "${diskFolder}")
			diskName=$(basename "${diskFolder}")
			if [[ ${verify} == true ]]; then
				diskImage=
			else
				diskImage=${diskFolder}.img
			fi
		fi
	fi
	if [ ! -d "${archiveFolder}" ]; then
		if [[ ${verify} == true ]]; then
			echo "missing archive folder: ${archiveFolder}"
			continue
		fi
		mkdir ${archiveFolder}
		if [ $? -ne 0 ]; then
			echo "unable to create folder: ${archiveFolder}"
			break
		fi
	fi
	if [ ! -d "${diskFolder}" ]; then
		if [[ ${verify} == true ]]; then
			echo "missing disk folder: ${diskFolder}"
			continue
		fi
		mkdir ${diskFolder}
		if [ $? -ne 0 ]; then
			echo "unable to create folder: ${diskFolder}"
			break
		fi
	fi
	if [ ! -z "${diskImage}" ]; then
		if [ ! -f "${diskImage}" ]; then
			if [[ ${verify} == true ]]; then
				echo "missing disk image: ${diskImage}"
				continue
			fi
			node ../../modules/diskdump/bin/diskdump --disk="${jsonFile}" --format=img --output="${diskImage}" >> ${log}
			if [ $? -ne 0 ]; then
				echo "unable to create disk image: ${diskImage}"
				break
			fi
			chmod a-w ${diskImage}
		fi
	fi
	if [ -z "$(ls -A ${diskFolder})" ]; then
		if [[ ${verify} == true ]]; then
			echo "empty disk folder: ${diskFolder}"
			continue
		fi
		echo "mounting ${diskImage}..."
		hdiutil mount "$diskImage" > disk
		if grep -q -e "^/dev" disk; then
			echo "dumping ${diskImage}..."
			vol=`grep -o -e "/Volumes/.*" disk`
			cp -Rp "${vol}/" "${diskFolder}"
			chmod a-w "${diskFolder}"
			hdiutil unmount "${vol}" > /dev/null
			rm disk
		else
			echo "WARNING: unable to mount ${diskImage}" >> ${log}
		fi
	else
		if [[ ${verify} != true ]]; then
			echo "disk image already dumped: ${diskImage}"
		fi
	fi
done < disks
rm disks
