## Indexes

### Index of Command-Line Options

These are the IRB command-line options, with links to explanatory text:

-d: Set $DEBUG and $VERBOSE to true.
-E _ex_[:_in_]: Set initial external (ex) and internal (in) encodings (same as ruby -E>).
-f: Don't initialize from configuration file.
-I _dirpath_: Specify $LOAD_PATH directory (same as ruby -I).
-r _load-module_: Require load-module (same as ruby -r).
-U: Set external and internal encodings to UTF-8.
-w: Suppress warnings (same as ruby -w).
-W[_level_]: Set warning level; 0=silence, 1=medium, 2=verbose (same as ruby -W).
--autocomplete: Use auto-completion.
--back-trace-limit _n_: Set a backtrace limit; display at most the top n and bottom n entries.
--colorize: Use color-highlighting for input and output.
--context-mode _n_: Select method to create Binding object for new workspace; n in range 0..4.
--echo: Print (echo) return values.
--extra-doc-dir _dirpath_: Add a documentation directory for the documentation dialog.
--inf-ruby-mode: Set prompt mode to :INF_RUBY (appropriate for inf-ruby-mode on Emacs); suppresses --multiline and --singleline.
--inspect: Use method inspect for printing (echo) return values.
--multiline: Use the multiline editor as the input method.
--noautocomplete: Don't use auto-completion.
--nocolorize: Don't use color-highlighting for input and output.
--noecho: Don't print (echo) return values.
--noecho-on-assignment: Don't print (echo) result on assignment.
--noinspect: Don't use method inspect for printing (echo) return values.
--nomultiline: Don't use the multiline editor as the input method.
--noprompt: Don't print prompts.
--noscript: Treat the first command-line argument as a normal command-line argument, and include it in ARGV.
--nosingleline: Don't use the singleline editor as the input method.
--noverbose: Don't print verbose details.
--prompt _mode_, --prompt-mode _mode_: Set prompt and return formats; mode may be a pre-defined prompt or the name of a custom prompt.
--script: Treat the first command-line argument as the path to an initialization script, and omit it from ARGV.
--simple-prompt, --sample-book-mode: Set prompt mode to :SIMPLE.
--singleline: Use the singleline editor as the input method.
--tracer: Use Tracer to print a stack trace for each input command.
--truncate-echo-on-assignment: Print truncated result on assignment.
--verbose: Print verbose details.
-v, --version: Print the IRB version.
-h, --help: Print the IRB help text.
--: Separate options from arguments on the command-line.


### Index of \IRB.conf Entries

These are the keys for hash \IRB.conf entries, with links to explanatory text;
for each entry that is pre-defined, the initial value is given:

- `:AP_NAME`: \IRB {application name}[rdoc-ref:IRB@Application+Name];
  initial value: `'irb'`.
- `:AT_EXIT`: Array of hooks to call
  {at exit}[rdoc-ref:IRB@IRB];
  initial value: `[]`.
- `:AUTO_INDENT`: Whether {automatic indentation}[rdoc-ref:IRB@Automatic+Indentation]
  is enabled; initial value: `true`.
- `:BACK_TRACE_LIMIT`: Sets the {back trace limit}[rdoc-ref:IRB@Tracer];
  initial value: `16`.
- `:COMMAND_ALIASES`: Defines input {command aliases}[rdoc-ref:IRB@Command+Aliases];
  initial value:

        {
          "$": :show_source,
          "@": :whereami,
        }

- `:CONTEXT_MODE`: Sets the {context mode}[rdoc-ref:IRB@Context+Mode],
  the type of binding to be used when evaluating statements;
  initial value: `4`.
- `:ECHO`: Whether to print ({echo}[rdoc-ref:IRB@Return-Value+Printing+-28Echoing-29])
  return values;
  initial value: `nil`, which would set `conf.echo` to `true`.
- `:ECHO_ON_ASSIGNMENT`: Whether to print ({echo}[rdoc-ref:IRB@Return-Value+Printing+-28Echoing-29])
  return values on assignment;
  initial value: `nil`, which would set `conf.echo_on_assignment` to `:truncate`.
- `:EVAL_HISTORY`: How much {evaluation history}[rdoc-ref:IRB@Evaluation+History]
  is to be stored; initial value: `nil`.
- `:EXTRA_DOC_DIRS`: \Array of
  {RI documentation directories}[rdoc-ref:IRB@RI+Documentation+Directories]
  to be parsed for the documentation dialog;
  initial value: `[]`.
- `:IGNORE_EOF`: Whether to ignore {end-of-file}[rdoc-ref:IRB@End-of-File];
  initial value: `false`.
- `:IGNORE_SIGINT`: Whether to ignore {SIGINT}[rdoc-ref:IRB@SIGINT];
  initial value: `true`.
- `:INSPECT_MODE`: Whether to use method `inspect` for printing
  ({echoing}[rdoc-ref:IRB@Return-Value+Printing+-28Echoing-29]) return values;
  initial value: `true`.
- `:IRB_LIB_PATH`: The path to the {IRB library directory}[rdoc-ref:IRB@IRB+Library+Directory]; initial value:

      - `"<i>RUBY_DIR</i>/lib/ruby/gems/<i>RUBY_VER_NUM</i>/gems/irb-<i>IRB_VER_NUM</i>/lib/irb"`,

    where:

      - <i>RUBY_DIR</i> is the Ruby installation dirpath.
      - <i>RUBY_VER_NUM</i> is the Ruby version number.
      - <i>IRB_VER_NUM</i> is the \IRB version number.

- `:IRB_NAME`: {IRB name}[rdoc-ref:IRB@IRB+Name];
  initial value: `'irb'`.
- `:IRB_RC`: {Configuration monitor}[rdoc-ref:IRB@Configuration+Monitor];
  initial value: `nil`.
- `:LC_MESSAGES`: {Locale}[rdoc-ref:IRB@Locale];
  initial value: IRB::Locale object.
- `:LOAD_MODULES`: deprecated.
- `:MAIN_CONTEXT`: The {context}[rdoc-ref:IRB@Session+Context] for the main \IRB session;
  initial value: IRB::Context object.
- `:MEASURE`: Whether to
  {measure performance}[rdoc-ref:IRB@Performance+Measurement];
  initial value: `false`.
- `:MEASURE_CALLBACKS`: Callback methods for
  {performance measurement}[rdoc-ref:IRB@Performance+Measurement];
  initial value: `[]`.
- `:MEASURE_PROC`: Procs for
  {performance measurement}[rdoc-ref:IRB@Performance+Measurement];
  initial value:

        {
          :TIME=>#<Proc:0x0000556e271c6598 /var/lib/gems/3.0.0/gems/irb-1.8.3/lib/irb/init.rb:106>,
          :STACKPROF=>#<Proc:0x0000556e271c6548 /var/lib/gems/3.0.0/gems/irb-1.8.3/lib/irb/init.rb:116>
        }

- `:PROMPT`: \Hash of {defined prompts}[rdoc-ref:IRB@Prompt+and+Return+Formats];
  initial value:

        {
          :NULL=>{:PROMPT_I=>nil, :PROMPT_S=>nil, :PROMPT_C=>nil, :RETURN=>"%s\n"},
          :DEFAULT=>{:PROMPT_I=>"%N(%m):%03n> ", :PROMPT_S=>"%N(%m):%03n%l ", :PROMPT_C=>"%N(%m):%03n* ", :RETURN=>"=> %s\n"},
          :CLASSIC=>{:PROMPT_I=>"%N(%m):%03n:%i> ", :PROMPT_S=>"%N(%m):%03n:%i%l ", :PROMPT_C=>"%N(%m):%03n:%i* ", :RETURN=>"%s\n"},
          :SIMPLE=>{:PROMPT_I=>">> ", :PROMPT_S=>"%l> ", :PROMPT_C=>"?> ", :RETURN=>"=> %s\n"},
          :INF_RUBY=>{:PROMPT_I=>"%N(%m):%03n> ", :PROMPT_S=>nil, :PROMPT_C=>nil, :RETURN=>"%s\n", :AUTO_INDENT=>true},
          :XMP=>{:PROMPT_I=>nil, :PROMPT_S=>nil, :PROMPT_C=>nil, :RETURN=>"    ==>%s\n"}
        }

- `:PROMPT_MODE`: Name of {current prompt}[rdoc-ref:IRB@Prompt+and+Return+Formats];
  initial value: `:DEFAULT`.
- `:RC`: Whether a {configuration file}[rdoc-ref:IRB@Configuration+File]
  was found and interpreted;
  initial value: `true` if a configuration file was found, `false` otherwise.
- `:SAVE_HISTORY`: Number of commands to save in
  {input command history}[rdoc-ref:IRB@Input+Command+History];
  initial value: `1000`.
- `:SINGLE_IRB`: Whether command-line option `--single-irb` was given;
  initial value: `true` if the option was given, `false` otherwise.
  See {Single-IRB Mode}[rdoc-ref:IRB@Single-IRB+Mode].
- `:USE_AUTOCOMPLETE`: Whether to use
  {automatic completion}[rdoc-ref:IRB@Automatic+Completion];
  initial value: `true`.
- `:USE_COLORIZE`: Whether to use
  {color highlighting}[rdoc-ref:IRB@Color+Highlighting];
  initial value: `true`.
- `:USE_LOADER`: Whether to use the
  {IRB loader}[rdoc-ref:IRB@IRB+Loader] for `require` and `load`;
  initial value: `false`.
- `:USE_TRACER`: Whether to use the
  {IRB tracer}[rdoc-ref:IRB@Tracer];
  initial value: `false`.
- `:VERBOSE`: Whether to print {verbose output}[rdoc-ref:IRB@Verbosity];
  initial value: `nil`.
- `:__MAIN__`: The main \IRB object;
  initial value: `main`.
