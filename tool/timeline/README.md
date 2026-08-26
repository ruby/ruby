# eBPF-based timeline visualization tool

This directory contains timeline visualization tool based on [eBPF] and [bpftrace].  It sets up
probes that attach to the Userspace Statically Defined Tracepoints (USDT) in the Ruby executable or
library, records events during the execution of a Ruby program, and outputs a log file in the [Trace
Event Format] which can be visualized on a timeline in the [Perfetto UI] web frontend.

This tool is primarily intended for analyzing garbage collection performance, but it can also
visualize other events, such as the acquisition of the global VM lock, and can be extended.

[eBPF]: https://ebpf.io/what-is-ebpf/
[bpftrace]: https://bpftrace.org/
[Trace Event Format]: https://docs.google.com/document/d/1CvAClvFfyA5R-PhYUmn5OOQtYMH4h6I0nSsKchNAySU/edit?usp=sharing
[Perfetto UI]: https://www.ui.perfetto.dev/

## How to use?

### Prepare and build

You need to run the tool on a Linux distribution, and you need the following command line tools.

-   `bpftrace`: The `capture.rb` script uses `bpftrace` to capture events.
-   `dtrace` from [SystemTap]: CRuby uses the `dtrace` command line tool during build time to
    generate USDT trace points.  Because `bpftrace` can only work with SystemTap's USDT format, you
    need to install the `dtrace` command line tool from SystemTap, not the [`dtrace` tool from
    Oracle][dtrace-oracle]

    CAUTION: Ubuntu 26.04 provides both the `dtrace` from SystemTap (package name is
    `systemtap-sdt-dev`) and the `dtrace` from Oracle (package name is `dtrace`), and they can
    coexist (installed as `/usr/bin/dtrace` and `/usr/sbin/dtrace`, respectively). Make sure CRuby
    is using the one from SystemTap.

[SystemTap]: https://sourceware.org/systemtap/
[dtrace-oracle]: https://github.com/oracle/dtrace

On Ubuntu, you can use the following commands:

```shell
sudo apt install bpftrace systemtap-sdt-dev
sudo apt remove dtrace
```

Build the `ruby` executable.  Make sure the `ruby` executable is built with USDT trace points.  If
the `configure` command detectes the `dtrace` command line tool, it should be enabled by default. If
not, add `--with-dtrace` to the `configure` command.  You can use the `readelf -n` command to check
if the trace points exist. It should show `stapstd` entries with `Provider: ruby`.

```shell
$ readelf -n /path/to/ruby
Displaying notes found in: .note.stapsdt
  Owner                Data size        Description
  stapsdt              0x00000045       NT_STAPSDT (SystemTap probe descriptors)
    Provider: ruby
    Name: array__create
    Location: 0x000000000006ba92, Base: 0x00000000007abe48, Semaphore: 0x000000000090a658
    Arguments: -4@$0 8@-16(%rbp) -4@%eax
...
```

### Capture and visualize

Open one terminal and run

```shell
/path/to/capture.rb -r /path/to/ruby
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
above.  Be careful if you have multiple Ruby builds in your filesystem.

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

Then press CTRL+C to interrupt the `capture.rb` script.  (More precisely, it interrupts the
underlying `bpftrace` program which `capture.rb` invoked.)

If everything went as expected, we repeat the `capture.rb`, but pipe the output into a log file.

```shell
/path/to/capture.rb -r /path/to/ruby > running_some_script.log
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
`running_some_script.log.json.gz` file.  Then you will be able to see the timeline.  Duration
events, such as `GCEnterExit`, `gc_mark` and `gc_sweep`, are displayed as bars, and instant events
are displayed as arrows.  Some events, such as `GCEnterExit` and `gc_mark`, have arguments.  If you
click an event, the arguments will be shown on the bottom part of the window.

### Enabling additional probes

The supported USDT trace points are organized into groups, and the default group is enabled by
default.  To enable additional groups of trace points, use the `-g` option of `capture.rb`.  For
example, if you want to monitor the number of objects swept during sweeping, you can enable the
`sweep_details` group.

```shell
/path/to/capture.rb -r /path/to/ruby -g sweep_details > running_some_script_with_sweep_details.log
```

There is no additional options needed for the `visualize.rb` script.  Just run it as usual.

See `lib/tracepoint_defs.rb` for a complete list of groups and their trace points.

### Working with GC modules

The default GC in CRuby can be compiled as a GC module.  If DTrace support is enabled when building
`ruby`, the USDT trace points will be automatically built into the GC module of the default GC.

When capturing, add the `-m` option to specify the path of the GC module.

```shell
/path/to/capture.rb -r /path/to/ruby -m /path/to/librubygc.default.so > running_some_script.log
```

Then run `ruby` with the GC module.

```shell
RUBY_GC_LIBRARY=default /path/to/ruby some_script.rb
```

Then visualize in the usual way.

## How to extend?

You can introduce more trace points by editing the `probes.d` file.

Then you can insert the trace points into the program in the form of

```c
RUBY_DTRACE_XXX_XXX_XXX(/* parameters */)
```

To capture and visualize those events, you need to edit the script `lib/tracepoint_defs.rb`.  It
will be read by both the `capture.rb` and the `visualize.rb` scripts.  After adding the definition
of your added trace points, the events and the arguments will be displayed on the timeline.

In rare cases, you can hack `visualize.rb` directly to do post-processing on each event.  For
example, you can combine the numbers of objects marked in multiple invocations of
`gc_mark_stacked_objects` and add it as one argument of the currnet `GCEnterExit` event in the
timeline.

### Performance concerns

USDT trace points are no-op instructions and have negligible overhead when not attached.  Therefore,
it is safe to insert the trace points even in the hot paths of hot functions.

However, when a trace point is attached by `bpftrace` (and therefore our capturing tool), it will
introduce an overhead whenever it is fired.  Different trace points are also fired at different
frequencies.  For example, `gc_enter` and `gc_exit` events are much less frequent than `obj_new` and
`obj_free`.  So you should avoid enabling high-frequency trace points which you are not interested
in in order not to reduce the fidelity of the measurement.  You can do this by grouping the trace
points by freqneucy in `lib/tracepoint_defs.rb` so that you can selectively enable the trace points
you are interested in with the `-g` option of `capture.rb`.

## Acknowledgement

This timeline tracing tool is inspired by [a similar tracing tool][mmtk-timeline] from the [Memory
Management Toolkit (MMTK)][mmtk] project.  The methodology was developed by Claire Huang, Steve
Blackburn, and Zixian Cai, and is described in details in the paper *[Improving Garbage Collection
Observability with Performance Tracing][HBC23]*.

[mmtk-timeline]: https://github.com/mmtk/mmtk-core/tree/master/tools/tracing/timeline
[mmtk]: https://www.mmtk.io/
[HBC23]: https://doi.org/10.1145/3617651.3622986
