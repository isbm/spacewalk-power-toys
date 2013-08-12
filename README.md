Spacewalk Power Toys
====================

Scripts and "crutches" when developing RedHat's Spacewalk.
Feel free to port that elsewhere.

License: BSD v3


Turn your CentOS into Spacewalk appliance
-----------------------------------------

CentOS is the way to go.

1. Get latest CentOS, network install, choose "Minimum".
2. Place "build-spacewalk.sh" somewhere in your ~/bin in $PATH on the _remote_ machine by using "curl".
3. Run: "build-spacewalk.sh --init-environment" and it will install missing packages on the _local_ machine.
4. Run: "build-spacewalk.sh --install-spacewalk" and it will install the rest of the stuff on the _local_ machine.


Deploy your developed Spacewalk to the appliance
------------------------------------------------

1. In your $JAVA_SOURCES_SPACEWALK run "build-spacewalk.sh --generate-config" to define defaults.
2. Every time you need to refresh target _remote_ machine, run just "build-spacewalk.sh".
3. For more options, run "build-spacewalk.sh -h"

That's it.
