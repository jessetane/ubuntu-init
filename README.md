# Cloud-init script for Ubuntu Server 12.04 Precise

## What
* Create user 'server' to install / run services with
* Enable Upstart user-jobs & auto start them at boot
* Install git, build tools, and node

## Why
An init-script is effectively a cross-region image. Plus, free docs.

## How
On ec2 the script can be passed via the ```user-data``` field to ```run-instances```. You can run the script manually too, though you will need to be root.

## License
MIT