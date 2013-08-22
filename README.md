Spacewalk Power Toys
====================

Scripts and "crutches" when developing RedHat's Spacewalk.
Feel free to port that elsewhere.

License: BSD v3


Turn your CentOS into Spacewalk appliance
-----------------------------------------

CentOS is the way to go.

1. Get latest CentOS, network install, choose "Minimum".
2. Place `bsp.sh` somewhere in your `~/bin` in `$PATH` on the _remote_ machine by using `curl`.
3. Run: `bsp.sh --init-environment` and it will install missing packages on the _local_ machine.
4. Run: `bsp.sh --install-spacewalk` and it will install the rest of the stuff on the _local_ machine.


Deploy your developed Spacewalk to the appliance
------------------------------------------------

1. In your `$JAVA_SOURCES_SPACEWALK` run `bsp.sh --generate-config` to define defaults.
2. Every time you need to refresh target _remote_ machine, run just `bsp.sh`.
3. For more options, run `bsp.sh -h`

**Note: This does update only to Java stack!** At least at the moment. Don't like it? Pull request, please.

That's it.
