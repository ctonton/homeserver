# Scripts to build NAS server

## Usage

Run the "start.sh" script as "root" on a fresh Debian installation to setup a network-attached storage server. Storage must be located in a directory named "Public" that is on the root of a separate drive or partition. A lite version of the server will be automatically installed on devices having less than 1GB of memory.

```shell
wget -q --show-progress https://github.com/ctonton/homeserver/raw/main/setup.sh && chmod +x start.sh && bash start.sh
```
