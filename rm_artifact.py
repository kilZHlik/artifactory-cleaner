import os
from artifactory import ArtifactoryPath

JF_USER = os.environ['JF_USER']
JF_USER_TOKEN = os.environ['JF_USER_TOKEN']
ARTIFACT_TO_REMOVE = os.environ['ARTIFACT_TO_REMOVE']

path = ArtifactoryPath(ARTIFACT_TO_REMOVE, auth=(JF_USER, JF_USER_TOKEN))

if path.exists():
    path.unlink()
