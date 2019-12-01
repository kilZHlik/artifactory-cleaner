import os
from artifactory import ArtifactoryPath

JF_USER = os.environ['JF_USER']
JF_USER_TOKEN = os.environ['JF_USER_TOKEN']
JF_ADDRESS = os.environ['JF_ADDRESS']
JF_REPOSITORY_PATH = os.environ['JF_REPOSITORY_PATH']

for p in ArtifactoryPath(JF_ADDRESS + '/' + JF_REPOSITORY_PATH, auth=(JF_USER, JF_USER_TOKEN)):
    print(p)
