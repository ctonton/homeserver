# Scripts to build NAS server

## Usage

Run the "start.sh" script on a fresh Debian installation to setup a N.A.S. file server where storage is on a separate drive or partition in a directory named "Public" on the root of that partition.

Select option "1 - install lite version server" for devices with less than 1gb of RAM.

Select option "2 - install full version server" for devices with at least 1gb of RAM.

```shell
wget https://raw.githubusercontent.com/ctonton/homeserver/main/start.sh -O start.sh && chmod +x start.sh && bash start.sh
```
