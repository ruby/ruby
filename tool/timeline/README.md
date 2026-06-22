# eBPF-based timeline visualization tool

This directory contains timeline visualization tool based on [eBPF] and [bpftrace].  It is inspired
by [a similar tracing tool][mmtk-timeline] from the [Memory Management Toolkit (MMTK)][mmtk]
project.  This tool is primarily intended for analyzing garbage collection performance, but it can
show other events, such as the acquisition of the global VM lock, and can be extended.

[eBPF]: https://ebpf.io/what-is-ebpf/
[bpftrace]: https://bpftrace.org/
[mmtk-timeline]: https://github.com/mmtk/mmtk-core/tree/master/tools/tracing/timeline
[mmtk]: https://www.mmtk.io/

## How to use?

### Prepare and build

You need Linux because eBPF is a feature of the Linux kernel.  It also needs the `bpftrace` command
line tool which is provided most major distributions.

```shell
sudo apt install bpftrace
```

Build the `ruby` executable.  Make sure the `ruby` executable is built with DTrace support (which
inserts the USDT trace points compatible with `bpftrace`).  It should be enabled by default.  If
not, add `--with-dtrace` to the `configure` command.  You can use the `readelf -n` command to check
if the trace points exist.  It should show `stapstd` entries with `Provider: ruby`.

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

Then press CTRL+C to interrupt the `capture.rb` script.  (More precisely, it interrupts the underlying
`bpftrace` program which `capture.rb` invokes.)

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

### Working with GC modules

The default GC in CRuby can be compiled as a GC module.  The USDT trace points are automatically
built into the GC module of the default GC.

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
will be read by both the `capture.rb` and the `visualize.rb` scripts.  The events and the arguments
will be displayed on the timeline.

In rare cases, you can hack `visualize.rb` directly to do post-processing on each event.  For
example, you can combine the numbers of objects marked in multiple invocations of
`gc_mark_stacked_objects` and add it as an argument of the currnet GC in the timeline.

### Performance concerns

USDT trace points are no-op instructions when not hooked, so they can be inserted even in the hot
paths of hot functions.

However, when hooked by `bpftrace` (and therefore our capturing tool), it will introduce an overhead
whenever a trace point is fired.  Different trace points are also fired at different frequencies.
For example, `gc_enter` and `gc_exit` events are much less frequent than `obj_new` and `obj_free`.
So you may want to group the trace points by freqneucy so that you can selectively enable the trace
points you are interested in.
