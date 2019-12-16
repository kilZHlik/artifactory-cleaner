FROM python:alpine
LABEL name="kilzhlik/artifactory-cleaner"
RUN pip3 install --no-cache-dir dohq-artifactory yq && \
    apk add --no-cache bash curl jq bc coreutils && \
    mkdir /opt/artifactory-cleaner
COPY artifacts_list.py processor.sh rescan_loop.sh rm_artifact.py /opt/artifactory-cleaner/
COPY artifactory-cleaner /usr/bin/
CMD /opt/artifactory-cleaner/rescan_loop.sh
