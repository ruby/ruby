# eBPF-based timeline visualization tool

This directory contains timeline visualization tool based on [eBPF] and [bpftrace].  It is inspired
by [a similar tracing tool][mmtk-timeline] from the [Memory Management Toolkit (MMTK)][mmtk]
project.  This tool is primarily intended for analyzing garbage collection performance, but it can
show other events, such as the acquisation of the global VM lock, and can be extended.

[eBPF]: https://ebpf.io/what-is-ebpf/
[bpftrace]: https://bpftrace.org/
[mmtk-timeline]: https://github.com/mmtk/mmtk-core/tree/master/tools/tracing/timeline
[mmtk]: https://www.mmtk.io/

## How to use?

This tool depends on eBPF which is a feature of the Linux kernel.  It also needs the `bpftrace`
command line tool which is provided most major distributions.

```shell
sudo apt install bpftrace
```

First of all, make sure the `ruby` executable is built from the same revision as the capturing
scripts.  Otherwise, the DTrace USDT trace points may not match those expected by the tools.

Open one terminal and run

```shell
/path/to/capture.bt -r /path/to/ruby
```

The `-r` option points to the `ruby` executable.  You will be prompted to enter the sudo password.
Then you will see output on the terminal:

```
Attaching 'begin' probe
Trying to attach probe: usdt:/path/to/ruby:ruby:gc__exit
Trying to attach probe: usdt:/path/to/ruby:ruby:gc__enter
Trying to attach probe: usdt:/path/to/ruby:ruby:gc__sweep__end
Trying to attach probe: usdt:/path/to/ruby:ruby:gc__sweep__begin
Trying to attach probe: usdt:/path/to/ruby:ruby:gc__mark__end
Trying to attach probe: usdt:/path/to/ruby:ruby:gc__mark__begin
Attached 7 probes
====RUBY_TRACING_LOG_START====
```

Then open another terminal and run a Ruby program using *the same* `ruby` executable specified
above.

```shell
/path/to/ruby some_script.rb
```

Go back to the first terminal.  If everything goes well, you should see output from `capture.rb` in
the CSV format like this:

```
...
GCEnterExit,B,18498,2093498438581,1
gc_sweep,B,18498,2093498439826
gc_sweep,E,18498,2093498444465
GCEnterExit,E,18498,2093498445798,1
GCEnterExit,B,18498,2093498629067,1
gc_sweep,B,18498,2093498630379
gc_sweep,E,18498,2093498682380
GCEnterExit,E,18498,2093498683848,1
GCEnterExit,B,18498,2093501215787,3
GCEnterExit,E,18498,2093501641157,3
```

Then press CTRL+C to interrupt the `capture.rb` script.  (More precisely, it interrupts the underlying
`bpftrace` program which `capture.rb` invokes.)  It will produce additional output like this:

```
@enable_print: 1
@every: 1
@gc_count: 0
@harness: 0
@stats_enabled: 1
```

If everything goes as expected, we repeat the `capture.rb`, but pipe the output into a log file.

```shell
/path/to/capture.bt -r /path/to/ruby > running_some_script.log
```

Then use the other terminal to run the script again

```shell
/path/to/ruby some_script.rb
```

Go back to the first terminal and use CTRL+C to interrupt `capture.rb`.  You should see the standard
output captured in the `running_some_script.log` file.

Then use the `visualize.rb` script to convert the log file into a JSON file.

```shell
/path/to/visualize.rb running_some_script.log
```

It should generate a file named `running_some_script.log.json.gz`.

Open a browser and go to <https://www.ui.perfetto.dev/>.  Click "open trace file" and select the
`running_some_script.log.json.gz` file.  Then you will be able to see the timeline.
