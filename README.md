Ubuntu 12.04 Precise cloud-init script designed for ec2 or Virtualbox

## Why
Needed a quick & cross-region way to prepare fresh instances.

## How
On ec2 the script can be passed via the ```user-data``` field to ```run-instances```. If you're using Virtualbox you'll have to get the script onto the machine manually and run it as root.

## Notes
Currently the script just installs git, build tools (and node js), creates an unprivileged user called 'server' and configures Upstart to handle user jobs.

## License
MIT