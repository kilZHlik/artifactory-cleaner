# Manual of Artifactory-cleaner v.0.3

Artifactory-cleaner is a software for automatically cleaning Jfrog Artifactory from irrelevant artifacts. Artifactory-cleaner interprets working with the API of any Jfrog Artifactory repositories as an interaction with a model of hierarchical file system. This model of interaction with the API and the implementation of flexible search parameters make Artifactory-cleaner a universal tool for cleaning irrelevant artifacts of any type. Artifactory-cleaner uses the dohq-artifactory Python library to interact with Jfrog Artifactory: https://github.com/devopshq/artifactory .

Keep in mind that Artifactory-cleaner is the result of the author’s free creative enthusiasm, and not some official Jfrog Artifactory tool. All possible responsibility for the consequences of any damage from the use of this software lies only with its users. You are free to use or not use this software. Your freedom is your responsibility! :)

#### 1. Description of Variables Used


Artifactory-cleaner requires authorization in Jfrog Artifactory using the username and token of the user to complete operations.
Authorization data is reported by Artifactory-cleaner by passing variables to the container.
The presence of variables required for authorization is a prerequisite for starting Artifactory-cleaner:

`JF_USER:` < user Jfrog Artifactory >

`JF_USER_TOKEN:` < user Token  >


##### 1.1. Optional variables

* `EMULATION_MODE:` < true/false >  (default: `true`)
If this variable is not explicitly declared with the value `false`, then Artifactory-cleaner will perform all actions to find artifacts, but the actual removal will not be performed.

* `VERBOSE_MODE:` < true/false > (default: `false`)
If this variable is declared with the value` true`, then every response from the Artifactory API will be logged when scanning artifacts.


#### 2. Description of the Artifactory-cleaner config

Artifactory-cleaner uses a configuration file to determine operation and search parameters.

##### 2.1. Example configuration file

```
jfrog_artifactory_address: "https://artifactory.local"
timeout_rescan: "1"
repositories:
  - repo: "my-repo"
    name: "qa-build"
    name_ignore: ""
    size: [ ">1mb", "<20mb" ]
    age: [ ">30", "<900" ]
    rm_non_empty_dirs: "false"
    recursive: "true"

  - repo: "docker-local/product"
    name: [ "dev-buil", "034-5" ]
    name_ignore: ""
    size: "<211kb"
    age: "=30"
    recursive:
      coefficient: "2"
```

The config has the format YAML.
A similar configuration file should be connected to the container as a volume in the following path: `/opt/artifactory-cleaner/artifactory-cleaner.yml`
When manually starting a scan, Artifactory-cleaner allows you to override the config used.
To be able to manually start searching and cleaning artifacts with a different configuration file, you also need to connect it to the container as an additional volume, or test the config created inside the container (not recommended if you are not familiar with Docker). Manually launching Artifactory-cleaner in emulation mode with an alternative config is a true way approach for selecting and testing the search config before entering the parameters from it into the default configuration file used in the container.
*For more details, see 3. Manual start of artifact cleaning.*


##### 2.2. Description of configuration file parameters


* `jfrog_artifactory_address:` `<protocol://address:port>` - the address of the Jfrog Artifactory service (required config parameter). If required, the connection port can be specified via a colon from the address.

* `timeout_rescan:` `<numbers>` - The length of the intervals in days between automatic search and removal of irrelevant artifacts. (optional config parameter). Format: integers.
If the` timeout_rescan` parameter is not defined in the configuration file, then when the container starts, Artifactory-cleaner will perform an initial scan of the repositories according to the config data, but will not be scannig repeatedly until the value of the `timeout_rescan` parameter in the config is determined. If the value of the` EMULATION_MODE` variable is defined as `false` when the container starts, then the found artifacts will not be deleted in this case. If the` timeout_rescan` parameter is missing, the configuration file is re-read automatically with a frequency of 30 seconds - for the convenience of updating the config without restarting the container.
When the value of the` timeout_rescan` parameter is set, the Artifactory-cleaner re-reads its value and the parameters from the `repositories` list before each scan of the repositories according to the specified timeout. Thus, when updating the search parameters in the config, there is no need to restart the container. The parameter` timeout_rescan` sets the number of days during which only one scan will be performed, but does not determine the time of its execution. The start time of the scan is always determined randomly. This behavior of the Artifactory-cleaner scheduler is intended for ease of configuration and to combat load spikes during possible scanning in organizations of one common Artifactory service from multiple containers.
*The ability to set a specific start-up time for cleaning is described in Section 3, Manual Start of Artifact Cleaning*


* `repositories:` -  a list that contains repository sections (required config element).
The number of sections with repositories in the list repositoriescan be indicated by more than one (see 2.1. Example configuration file).


##### 2.3. Description of the repository list section


* `repo:` < path > - repository (required parameter). Using the Jfrog Artifactory API, Artifactory-cleaner presents the repository as directory properties. This allows you to specify as a repository the path with subdirectories in the repository (see 2.1. Example configuration file). This provides additional flexibility in determining the search terms.

* `rm_non_empty_dirs:` < true/false > (default: `false`) - delete directories with artifacts (optional parameter).
######Caution: use this option with caution!
When adding a parameter `rm_non_empty_dirs` with a value `true`, in order for the directory to be deleted, the search parameter must also be specified `name`(see description of the parameter `name`). This condition is a specially introduced restriction aimed at reducing the risk of mistakenly deleting non-empty directories.

  *Note: when deleting various artifacts, for example, when deleting Docker images, empty directories may be formed. All empty directories that Artifactory-cleaner detects according to the search parameters will be automatically deleted during subsequent scanning, regardless of the parameter value `rm_non_empty_dirs`*

  *Note: for directories, the `size` parameter is ignored.*

* `recursive:` < true/false > (default: `false`) - scan subdirectories (optional parameter).
For the parameter `recursive`, a sub-parameter ` coefficient` with a numerical value can be defined (see 2.1. Example configuration file). The `coefficient` subparameter sets the maximum nesting of directories in which the search will be performed from the initial directory defined in the` repo` parameter.

* `age:` is the age of the artifact in days (optional parameter). Format: `<(>, <, =)> <number>`. Only integers are supported. The value can be one or several with different conditions. Several conditions are be combined into a list (see 2.1. Example configuration file). The conditions `(>, <, =)` in the list must be unique. No more than one list per parameter is supported.

  *Note: for a correct search using the “age” parameter, the correct time must be indicated on the Jfrog Artifactory server and on the machine on which the container with Artifactory-cleaner is running.*

* `name:` - matching name (optional parameter). Part of the name on the way to the artifact from the repository directory, including the name of the artifact itself. The value of this parameter is case sensitive. As a value, a list of names can be specified in the sequence in which they are expected to be present in the path from the repository directory to the name of the artifact itself. Supported not more than one list per parameter . Also in the field `name` it is allowed to use regexps.

  *Note: When building regexps and using backslashes, do not forget that in yaml format the ackslash must be escaped by the second backslash.*

  Please note that the final artifact (by analogy with the file system: the final search file) can be written in the API of Jfrog Artifactory view to an object whose name is stored as a hash of the sum. That is, it can be stored in a file whose name may have nothing to do with the name of the artifact expected for a person - for example, with the name of a Docker image or archive file. For this reason, the search for the name of the artifact is carried out all the way to it from the repository directory set in the `repo` parameter. This, on the one hand, is not quite the traditional behavior for the usual search tools, but it also allows you to more flexibly configure filtering by name. On the other hand, this behavior is a technical limitation in favor of universality and support for all types of repositories. If you are confused by information about hash sums, then do not pay attention to it, just keep in mind that the artifact will be searched not only by its name but also all the way from the beginning of the specified repository directory.


* `name_ignore:` - excluded name (optional parameter). Similar to the name parameter, but the path to the artifact that matches the value of `name_ignore` will, on the contrary, be excluded from deletion.

* `size:` - artifact size (optional parameter). Format: `<condition (>, <, =)> <number> <dimension (gb, mb, kb)>` Only integers are supported. The value can be either one or several combined into a list. Supported not more than one list per parameter . If the dimension is not defined, then the size will be considered in bytes. The conditions `(>, <, =)` in the list must be unique. When the `rm_non_empty_dirs` parameter is used with the value` true`, for directories the parameter `size` is ignored. It is recommended that you use this parameter in conjunction with the `recursive` parameter, because real files can be stored in the Jfrog Artifactory API view behind human-readable directory names.

---
The parameters `name`,` size` and `age` are properties of the artifact, which together it must correspond in order for the artifact to fall under the conditions of deletion. At least one of these three parameters must be defined to search artifacts, otherwise the search configuration is considered invalid.



#### 3. Manual start of artifact cleaning


As mentioned above, manually starting Artifactory-cleaner in emulation mode with an alternative config is a true way approach for selecting and testing a search config before entering parameters from it into the default configuration file used in the container.

It is also possible to use the commands constituted for manual launch (but without the `-t` attribute) to run the search for artifacts at a specific time by adding them to tasks for cron on the Docker host or adding them to your CI/CD pipeline.

*More information on working with cron can be found here: https://www.cyberciti.biz/faq/how-do-i-add-jobs-to-cron-under-linux-or-unix-oses*

However, in large organizations where the Jfrog Artifactory service is usual shared, it is recommended to use the scheduler built into the "Artifactory-cleaner" controlled by the `timeout_rescan` parameter. (see the description of the `timeout_rescan` parameter in Section 2.3).

An example of running a manual scan command inside an already running container with the `--help` attribute:
```
docker exec -it <container name> artifactory-cleaner --help
```

You can do the same by creating a new container:
```
docker run --name artifactory-cleaner --env JF_USER=user --env JF_USER_TOKEN=token \
-v $PWD/artifactory-cleaner.yml:/opt/artifactory-cleaner/artifactory-cleaner.yml \
-it --rm artifactory-cleaner artifactory-cleaner --help
```

*For more information on working with Docker, refer to its documentation:
docker run  - https://docs.docker.com/engine/reference/run
docker exec - https://docs.docker.com/engine/reference/commandline/exec command*

As a result of running these commands, the current variable values used in the container will be displayed: `EMULATION_MODE` and `VERBOSE_MODE`, and help on available startup options:
```
The following launch arguments are available:
-c — Specify the path of an alternative configuration file.
+e — Enable emulation mode.
-e — Disable emulation mode.
-i — Show application information and startup options.
+v — Enable verbose mode.
-v — Disable verbose mode.
```

As already clear from the help, when manually starting a scan, Artifactory-cleaner allows you to override the config used.
To be able to manually start searching and cleaning artifacts with a different configuration file, you need to connect it to the container as an additional volume, or used the config created inside the container (not recommended if you are not familiar with Docker).

Example config to run artifactory-cleaner using docker-compose:

```
version: '2'
services:
  task:
    image: kilzhlik/artifactory-cleaner
    container_name: artifactory-cleaner
    user: root
    restart: unless-stopped
    volumes:
      - "$PWD/artifactory-cleaner.yml:/opt/artifactory-cleaner/artifactory-cleaner.yml"
      - "$PWD/artifactory-cleaner_test.yml:/opt/artifactory-cleaner/artifactory-cleaner_test.yml"
    environment:
      JF_USER: "USER"
      JF_USER_TOKEN: "USER_TOKEN"
      EMULATION_MODE: "true"
      VERBOSE_MODE: "false"
```

This example connects two configuration files to the artifactory-cleaner container. The configuration file `artifactory-cleaner_test.yml` will not be used when the container starts automatically. It will come in handy for a test run of a scan manually.


After that, accessing an alternative configuration file in the attribute of the `artifactory-cleaner` command for an already running container looks like this:
```
docker exec -it <container name> artifactory-cleaner -e \
-c /opt/artifactory-cleaner/artifactory-cleaner_test.yml
```


To run from an image, this command looks logically a little different:
```
docker run --name artifactory-cleaner --env JF_USER=user --env JF_USER_TOKEN=token \
-v $PWD/artifactory-cleaner_test.yml:/opt/artifactory-cleaner/artifactory-cleaner.yml \
-it --rm artifactory-cleaner artifactory-cleaner
```
In it, the config is not redefined in the launch attribute of the artifactory-cleaner command, but at the connection stage. And the `-e` attribute is omitted because emulation mode is used by default if it is not explicitly overridden by the variable `EMULATION_MODE: false` that is reported to the container at startup (see 1.1. Optional variables).

Artifactory-cleaner logs all actions that may cause user questions in stdout, this makes it possible to understand what is happening by reading the container logs with the Docker tools.
The command to view the live container log:
```
docker logs -f <container name>
```

#### [Change Log] (https://github.com/kilZHlik/artifactory-cleaner/blob/0.3/CHANGELOG.md)

* * *

[Github repository of the Artifactory-cleaner] (https://github.com/kilZHlik/artifactory-cleaner)
