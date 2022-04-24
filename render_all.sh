#!/usr/bin/env bash


function encode() {
	filename=${@: -1}
	if [ -f $filename ] ; then
		rm $filename
	fi
	$@
	if [ -f $filename ] ; then
		touch -a -m -t ${timestamp} ${filename}
	else
		return 1
	fi
}


SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

cd ${SCRIPT_DIR}

remote_server=pi@octopi
remote_folder=.octoprint/data/octolapse/snapshot_archive

remote_zip_files=$(ssh ${remote_server} ls ${remote_folder})

for zip_file in ${remote_zip_files} ; do
	echo "Found ${zip_file} on the server"

	if ! grep "$zip_file" done.txt ; then
		echo " -> treating"
		
		title="${zip_file%.*}"
		local_zip_file=./snapshot_archive/${zip_file}
		local_extracted=./images/${title}

		if [ ! -d ${local_extracted} ] ; then
			mkdir -p ${local_extracted}
			echo "Need to extract zip file locally"
			if [ ! -f ${local_zip_file} ] ; then
				echo "Downloading zip file"
				rsync -azv --progress ${remote_server}:${remote_folder}/${zip_file} ./snapshot_archive/
			else
				echo "Zip file already downloaded"
			fi
			echo "Extracting"
			unzip ${local_zip_file} -d ${local_extracted}
		fi
		
		rename "s/ /_/g" ${local_extracted}/*/*/*.jpg
		cd ${local_extracted} && ls */*/*.jpg | sort -V | xargs -I {} echo "file '{}'" > list.txt
		cd ${SCRIPT_DIR}

		dimensions=$(file $(ls ${local_extracted}/*/*/*.jpg | head -1) | sed -n 's/.* \([0-9]*x[0-9]*\).*/\1/p')

		width=$(echo $dimensions | cut -d x -f1)
		height=$(echo $dimensions | cut -d x -f2)

		target_height=2160
		target_folder=videos/$(echo ${zip_file} | sed -n "s/\(.*_[0-9]\{14\}\).*/\1/p")
		timestamp=$(echo ${zip_file} | sed -n "s/.*_\([0-9]\{12\}\)\([0-9]\{2\}\).*/\1.\2/p")

		preset=medium
		CRF=24

		echo "JPG dimensions: ${width}x${height}"

		base_encode_command="ffmpeg -f concat -i ${local_extracted}/list.txt -c:v libx265 -crf ${CRF} -preset ${preset} -pix_fmt yuv420p"

		encode_OK=true

		mkdir -p ${target_folder}

		if [ ${height} -gt ${target_height} ] ; then
			let target_width=$width*${target_height}/${height}/2*2
			echo " -> Reducing to 4k: ${target_width}x${target_height}"

			for resize_method in scale crop ; do
				target_file=${target_folder}/${title}_4k_${resize_method}.mp4
				encode ${base_encode_command} -vf ${resize_method}=${target_width}:${target_height} ${target_file}
				if [ $? != 0 ] ; then
					encode_OK=false
				fi
			done
		else
			target_file=${target_folder}/${title}_${width}x${height}.mp4
			encode ${base_encode_command} ${target_file}
			if [ $? != 0 ] ; then
				encode_OK=false
			fi
		fi
		
		if [ $encode_OK = true ] ; then
			echo ${zip_file} >> done.txt
		else
			echo "ERROR: could not render $title, check the logs above."
		fi
	else
		echo " -> already treated"
	fi

done
