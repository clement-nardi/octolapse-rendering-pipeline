#!/usr/bin/env bash

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

cd ${SCRIPT_DIR}

rsync -azv -h --progress pi@octopi:.octoprint/data/octolapse/snapshot_archive .


for zip_file in $(cd snapshot_archive; ls *.zip) ; do

	if ! grep "$zip_file" done.txt ; then
	
		title="${zip_file%.*}"
		
		rm -rf workdir
		mkdir workdir

		unzip ./snapshot_archive/${zip_file} -d ./workdir/
		
		rename "s/ /_/g" workdir/*/*/*.jpg
		cd workdir && ls */*/*.jpg | sort -V | xargs -I {} echo "file '{}'" > list.txt
		cd ${SCRIPT_DIR}

		dimensions=$(file $(ls workdir/*/*/*.jpg | head -1) | sed -n 's/.* \([0-9]*x[0-9]*\).*/\1/p')

		width=$(echo $dimensions | cut -d x -f1)
		height=$(echo $dimensions | cut -d x -f2)

		target_height=2160

		preset=medium
		CRF=24

		echo "JPG dimensions: ${width}x${height}"

		if [ ${height} -gt ${target_height} ] ; then
			let target_width=$width*${target_height}/${height}/2*2
			echo " -> Redusing to 4k: ${target_width}x${target_height}"

			ffmpeg -f concat -i workdir/list.txt -vf scale=${target_width}:${target_height} -c:v libx265 -crf ${CRF} -preset ${preset} -pix_fmt yuv420p ${title}_4k.mkv
			ffmpeg -f concat -i workdir/list.txt -vf crop=${target_width}:${target_height} -c:v libx265 -crf ${CRF} -preset ${preset} -pix_fmt yuv420p ${title}_4k_crop.mkv
		else
			
			ffmpeg -f concat -i workdir/list.txt -c:v libx265 -crf ${CRF} -preset ${preset} -pix_fmt yuv420p ${title}_${width}x${height}.mkv
		fi
		
		if ls ${title}*.mkv ; then
			echo ${zip_file} >> done.txt
		else
			echo "ERROR: could not render $title, check the logs above."
		fi
	fi

done
