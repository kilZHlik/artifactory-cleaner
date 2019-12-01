FROM python
LABEL name="kilzhlik/artifactory-cleaner"
RUN pip3 install dohq-artifactory yq && \
    apt update && \
    apt -y install curl jq bc && \
    mkdir /opt/artifactory-cleaner
COPY artifacts_list.py processor.sh rescan_loop.sh rm_artifact.py /opt/artifactory-cleaner/
COPY artifactory-cleaner /usr/bin/
CMD /opt/artifactory-cleaner/rescan_loop.sh
