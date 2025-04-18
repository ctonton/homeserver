# Scripts to build NAS server

## Instructions

Run the "setup.sh" script as "root" on a fresh Debian installation to setup a network-attached storage server. Storage must be located in a directory named "Public" that is on the root of a separate drive or partition. A lite version of the server will be automatically installed on devices having less than 1GB of memory.

```shell
wget -q --show-progress https://github.com/ctonton/homeserver/raw/main/setup.sh -O setup.sh && chmod +x setup.sh
```

## Usage

To run the script without any ineruptions, use the following arguments.
```shell
./setup.sh -a -h hostname -p sda1)
```
<br>
-a &emsp;&emsp;&emsp;acknoledge all warnings
<br>
-n host &ensp;set hostname
<br>
-p part &ensp;set partition for storage
