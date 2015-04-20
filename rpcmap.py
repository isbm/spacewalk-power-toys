#!/usr/bin/python
#
# A pretty ugly script that just finds out the XML-RPC load on the SUSE Manager.
# The idea is to have a rough overview what is happening behind the scenes
# between the client and the server.
#
# Note: this might not always work on the latest version of SUSE Manager.
#

import time
import sys
import os
import bz2


class DistributionGraph(object):
    """
    Very simple chart hack.
    """
    # It could be https://pypi.python.org/pypi/ascii_graph/0.2.1 for example.

    def __init__(self):
        """
        Print ASCII graph of calls distribution.
        """
        self.width = 24
        self.height = 50
        self._clear()

    def _t_off(self, tm):
        """
        Time offset.
        """
        h, m, s = tm.split(":")
        offset = int(h) + (int(m) and 1 or 0)
        return offset < 24 and offset or 23

    def _v_off(self, offset, calls, f=1):
        """
        Set height by factor.
        """
        for line in self.canvas:
            if not calls:
                line[offset] = "."
                break
            else:
                line[offset] = "#"
                calls -= f
                if calls < 1:
                    break

    def _clear(self):
        """
        Clear canvas.
        """
        self.canvas = list()
        for x in range(self.height):
            self.canvas.append([" " for x in range(self.width)])

    def _get_load_all(self, data, day=None):
        """
        Calculate load.
        """
        self.top_calls = dict()
        offsets = dict()
        for dt in sorted(data.keys()):
            if day and dt != day: continue
            times = data[dt]
            for tm in sorted(times.keys()):
                if tm not in offsets:
                    offsets[tm] = 0
                offsets[tm] += len(times[tm])
                for call in times[tm]:
                    if call not in self.top_calls:
                        self.top_calls[call] = 0
                    self.top_calls[call] += 1

        return offsets

    def _max_peaks(self, peaks):
        """
        Get max of peaks
        """
        m_data = [None, 0]
        for offset, data in peaks.items():
            calls, time = data
            if m_data[1] < calls:
                m_data = [offset, calls]
        return m_data[0]

    def _max_calls(self, pop=True):
        """
        Get max of calls
        """
        mx_tm = 0
        mx_call = None
        for call, tm in self.top_calls.items():
            mx_tm = tm > mx_tm and tm or mx_tm
            mx_call = mx_tm == tm and call or mx_call

        if pop:
            self.top_calls.pop(mx_call)

        return mx_call.strip(), mx_tm

    def _get_peaks(self, load, data):
        """
        Get peak calls per selected period.
        """
        self.peaks = dict()
        for t in sorted(load.keys()):
            t_off = self._t_off(t)
            if t_off not in self.peaks:
                self.peaks[t_off] = [0, t]
            self.peaks[t_off][0] += load[t]
        return self.peaks

    def load(self, data, day=None):
        """
        Load a log file.
        """
        self._clear()
        load = None
        if day:
            load = self._get_load_all(data, day=day)
            if not load:
                self.height = 5
                self._clear()
                msg = day + " N/A"
                l = " " * ((self.width - len(msg)) / 2)
                r = " " * (self.width - len(msg + l))
                self.canvas[self.height / 2] = l + msg + r
        else:
            load = self._get_load_all(data)

        x_load = [0 for x in range(self.width)]
        for offset, tset in self._get_peaks(load, data).items():
            x_load[offset] = tset[0]

        factor = max(x_load) / self.height
        for idx in range(len(x_load)):
            self._v_off(idx, x_load[idx], factor)

    def draw(self):
        """
        Draw ASCII chart. :-)
        """
        print " " + ("-" * self.width)
        for cl in self.canvas[::-1]:
            print "|{0}|".format(''.join(cl))
        print " " + ("-" * self.width)

        # Top peaks
        if self.peaks:
            top = len(self.peaks) > 5 and 5 or len(self.peaks)
            print "\nTop {0} peaks:".format(top)
            for x in range(top):
                print "\t{0} calls at {1}".format(*self.peaks.pop(self._max_peaks(self.peaks)))

        # Top calls
        top = len(self.top_calls) > 5 and 5 or len(self.top_calls)
        print "\nTop {0} calls:".format(top)
        for x in range(top):
            print "\t{0}".format(*self._max_calls(pop=True))
        print


class CallMapper(object):
    """
    Data collector.
    Usually breaks, if the log format is different. :)
    """
    FILTER = " xmlrpc/"

    def __init__(self, logmask, all_logs=False):
        self.logmask = logmask
        self.nodes = set()
        self.all_logs = all_logs
        self._log_data = list()

    def _log(self):
        """
        Open log data and filter for a criteria.
        This takes all the logs into the memory. :)
        """
        if self._log_data:
            return self._log_data

        logs = 0
        b_name = os.path.basename(self.logmask)
        b_dir = self.logmask.replace(b_name, "")
        for fname in os.listdir(b_dir):
            rl = list()
            if not fname.startswith(b_name): continue
            if self.all_logs and fname.endswith(".bz2"):
                rl = bz2.BZ2File(os.path.join(b_dir, fname)).xreadlines()
                logs += 1
            elif fname.endswith(".log"):
                rl = open(os.path.join(b_dir, fname)).xreadlines()
                logs += 1
            self._log_data.extend([l for l in rl if l.find(self.FILTER) > -1])

        print "Used {0} log{1}".format(logs, logs > 1 and "s" or "")

        return self._log_data

    def find_nodes(self, period=None):
        """
        Find involved nodes in the period of time.
        """
        for logline in self._log():
            if period and period not in ('--all', '--show') and logline.find(period) < 0: continue
            ip = logline.split(" ")[4][:-1]
            if len(ip.split(".")) == 4:
                self.nodes.add(ip)

    def _clean_call(self, call):
        """
        Strip the call to the mere function.
        """
        return call.replace(self.FILTER.strip(), '').split("(")[0]

    def get_calls(self, node, period=None, call=None):
        """
        Find calls per a node.
        """
        out = dict()
        for logline in self._log():
            if logline.find(node) < 0: continue
            dt, tm, offset, pid, ip, data = logline.split(" ", 5)
            if period and period != dt: continue
            # Round time
            tm = tm[:3] + (int(tm[3:4]) > 3 and '3' or '0') + '0:00'

            # Tree map
            if out.get(dt) is None:
                out[dt] = dict()
            if out[dt].get(tm) is None:
                out[dt][tm] = list()
            out[dt][tm].append(self._clean_call(data))

        return out

    def get_all_calls(self, period=None, call=None):
        """
        Summarize all calls together.
        """
        period = not period.startswith("--") and period or None
        out = dict()
        for node in self.nodes:
            out.update(self.get_calls(node, period=period, call=call))

        return out


def usage():
    usg = """
Usage: rpcmap <mode> [options]

Modes:
    YYYY/MM/DD
        A valid day in the log, e.g. 2015/02/22 etc.

    --all
        Use all available dates in the log.

    --show
        List all available periods in the log.

Options:
    --use-all-logs
        Read all logs, including already compressed (rotated)

    --call=...
        A string that would match an XML-RPC call.
"""
    print usg.strip()
    sys.exit(1)

if __name__ == '__main__':
    if not sys.argv[1:]:
        usage()
    option = sys.argv[1].lower()

    cm = CallMapper("/var/log/rhn/rhn_server_xmlrpc", all_logs="--use-all-logs" in sys.argv)
    cm.find_nodes(option)
    print "Found {0} nodes".format(len(cm.nodes))

    data = cm.get_all_calls(period=option)

    if option == '--show':
        for day in sorted(data.keys()):
            print "\t{0}".format(day)
        sys.exit(0)

    g = DistributionGraph()
    g.load(data, day=(option and not option.startswith("--") and option or None))
    g.draw()
