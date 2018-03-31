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
find -L ${dir} -name "manifest.xml" -exec grep -H -e "<disk.*href=" {} \; | sed -E "s/^([^:]*)\/manifest\.xml:.*href=\"([^\"]*)\".*/\1;\2/" > disks
while read line; do
	srcFile=`echo ${line} | sed -E "s/.*;(.*)/\1/"`
	echo "checking ${srcFile}..."
	tmpFile=`echo ${srcFile} | sed -E "s/.*\/pcx86\/(.*)/\1/"`
	if [[ ${srcFile} == http* ]]; then
		if [ ! -f "${tmpFile}" ]; then
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
	if [ ! -d "${archiveFolder}" ]; then
		mkdir ${archiveFolder}
		if [ $? -ne 0 ]; then
			echo "unable to create folder: ${archiveFolder}"
			break
		fi
	fi
	diskName=$(basename "${jsonFile}" ".json")
	diskFolder=${archiveFolder}/${diskName}
	if [ ! -d "${diskFolder}" ]; then
		mkdir ${diskFolder}
		if [ $? -ne 0 ]; then
			echo "unable to create folder: ${diskFolder}"
			break
		fi
	fi
	diskImage=${archiveFolder}/${diskName}.img
	if [ ! -f "${diskImage}" ]; then
		node ../../modules/diskdump/bin/diskdump --disk="${jsonFile}" --format=img --output="${diskImage}" >> ${log}
		if [ $? -ne 0 ]; then
			echo "unable to create disk image: ${diskImage}"
			break
		fi
		chmod a-w ${diskImage}
	fi
	if [ -z "$(ls -A ${diskFolder})" ]; then
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
		echo "disk image already dumped: ${diskImage}"
		continue
	fi
done < disks
rm disks
