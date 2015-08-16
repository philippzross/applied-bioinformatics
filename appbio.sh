#!/usr/bin/env bash

# catch errors
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo -e "\nusage: $(basename $0) <cmd>\n"
	echo -e "Starts and stops applied bioinformatics course containers\n"
	echo -e "-r         start rstudio container"
	echo -e "-g         start galaxy container"
	echo -e "-c         start ubuntu container"
	echo -e "-s         stop and remove all containers"
	exit
fi

cmd=$1

if [[ "${cmd}" == "-r" ]]; then

	docker run -d -p 8787:8787 \
		--name="appbio-rstudio" \
		-m 1g \
		-e USER=${USER} -e USERID=${UID} \
		-v $HOME/applied-bioinformatics:/home/rstudio/applied-bioinformatics \
		thephilross/hadleybioverse

elif [[ "${cmd}" == "-g" ]]; then

	docker run -d \
		-p 8080:80 -p 8021:21 -p 8800:8800 -p 9001:9001 \
		--name="appbio-galaxy" \
		-m 1g \
		-v $HOME/applied-bioinformatics/:/applied-bioinformatics/ \
		bgruening/galaxy-stable

elif [[ "${cmd}" == "-c" ]]; then

	docker run -i -t \
	--name="appbio-ubuntu" \
	-m 1g \
	-v $HOME/applied-bioinformatics/:/applied-bioinformatics/ \
	thephilross/appbio \
	/bin/bash

elif [[ "${cmd}" == "-s" ]]; then
	docker stop appbio-galaxy appbio-rstudio appbio-ubuntu
	docker rm appbio-galaxy appbio-rstudio appbio-ubuntu

else
	echo -e "Not a valid flag."
	exit
fi

exit
