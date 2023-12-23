# frozen_string_literal: false
#
#   irb.rb - irb main module
#       by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

require "ripper"
require "reline"

require_relative "irb/init"
require_relative "irb/context"
require_relative "irb/extend-command"

require_relative "irb/ruby-lex"
require_relative "irb/statement"
require_relative "irb/input-method"
require_relative "irb/locale"
require_relative "irb/color"

require_relative "irb/version"
require_relative "irb/easter-egg"
require_relative "irb/debug"
require_relative "irb/pager"

# == \IRB
#
# \Module \IRB ("Interactive Ruby") provides a shell-like interface
# that supports user interaction with the Ruby interpreter.
#
# It operates as a <i>read-eval-print loop</i>
# ({REPL}[https://en.wikipedia.org/wiki/Read%E2%80%93eval%E2%80%93print_loop])
# that:
#
# - <b>_Reads_</b> each character as you type.
#   You can modify the \IRB context to change the way input works.
#   See {Input}[rdoc-ref:IRB@Input].
# - <b>_Evaluates_</b> the code each time it has read a syntactically complete passage.
# - <b>_Prints_</b> after evaluating.
#   You can modify the \IRB context to change the way output works.
#   See {Output}[rdoc-ref:IRB@Output].
#
# Example:
#
#   $ irb
#   irb(main):001> File.basename(Dir.pwd)
#   => "irb"
#   irb(main):002> Dir.entries('.').size
#   => 25
#   irb(main):003* Dir.entries('.').select do |entry|
#   irb(main):004*   entry.start_with?('R')
#   irb(main):005> end
#   => ["README.md", "Rakefile"]
#
# The typed input may also include
# {\IRB-specific commands}[rdoc-ref:IRB@IRB-Specific+Commands].
#
# As seen above, you can start \IRB by using the shell command +irb+.
#
# You can stop an \IRB session by typing command +exit+:
#
#   irb(main):006> exit
#   $
#
# At that point, \IRB calls any hooks found in array <tt>IRB.conf[:AT_EXIT]</tt>,
# then exits.
#
# == Startup
#
# At startup, \IRB:
#
# 1. Interprets (as Ruby code) the content of the
#    {configuration file}[rdoc-ref:IRB@Configuration+File] (if given).
# 1. Constructs the initial session context
#    from {hash IRB.conf}[rdoc-ref:IRB@Hash+IRB.conf] and from default values;
#    the hash content may have been affected
#    by {command-line options}[rdoc-ref:IB@Command-Line+Options],
#    and by direct assignments in the configuration file.
# 1. Assigns the context to variable +conf+.
# 1. Assigns command-line arguments to variable <tt>ARGV</tt>.
# 1. Prints the {prompt}[rdoc-ref:IRB@Prompt+and+Return+Formats].
# 1. Puts the content of the
#    {initialization script}[rdoc-ref:IRB@Initialization+Script]
#    onto the \IRB shell, just as if it were user-typed commands.
#
# === The Command Line
#
# On the command line, all options precede all arguments;
# the first item that is not recognized as an option is treated as an argument,
# as are all items that follow.
#
# ==== Command-Line Options
#
# Many command-line options affect entries in hash <tt>IRB.conf</tt>,
# which in turn affect the initial configuration of the \IRB session.
#
# Details of the options are described in the relevant subsections below.
#
# A cursory list of the \IRB command-line options
# may be seen in the {help message}[https://raw.githubusercontent.com/ruby/irb/master/lib/irb/lc/help-message],
# which is also displayed if you use command-line option <tt>--help</tt>.
#
# If you are interested in a specific option, consult the
# {index}[rdoc-ref:doc/irb/indexes.md@Index+of+Command-Line+Options].
#
# ==== Command-Line Arguments
#
# Command-line arguments are passed to \IRB in array +ARGV+:
#
#   $ irb --noscript Foo Bar Baz
#   irb(main):001> ARGV
#   => ["Foo", "Bar", "Baz"]
#   irb(main):002> exit
#   $
#
# Command-line option <tt>--</tt> causes everything that follows
# to be treated as arguments, even those that look like options:
#
#   $ irb --noscript -- --noscript -- Foo Bar Baz
#   irb(main):001> ARGV
#   => ["--noscript", "--", "Foo", "Bar", "Baz"]
#   irb(main):002> exit
#   $
#
# === Configuration File
#
# You can initialize \IRB via a <i>configuration file</i>.
#
# If command-line option <tt>-f</tt> is given,
# no configuration file is looked for.
#
# Otherwise, \IRB reads and interprets a configuration file
# if one is available.
#
# The configuration file can contain any Ruby code, and can usefully include
# user code that:
#
# - Can then be debugged in \IRB.
# - Configures \IRB itself.
# - Requires or loads files.
#
# The path to the configuration file is the first found among:
#
# - The value of variable <tt>$IRBRC</tt>, if defined.
# - The value of variable <tt>$XDG_CONFIG_HOME/irb/irbrc</tt>, if defined.
# - File <tt>$HOME/.irbrc</tt>, if it exists.
# - File <tt>$HOME/.config/irb/irbrc</tt>, if it exists.
# - File +.config/irb/irbrc+ in the current directory, if it exists.
# - File +.irbrc+ in the current directory, if it exists.
# - File +irb.rc+ in the current directory, if it exists.
# - File +_irbrc+ in the current directory, if it exists.
# - File <tt>$irbrc</tt> in the current directory, if it exists.
#
# If the search fails, there is no configuration file.
#
# If the search succeeds, the configuration file is read as Ruby code,
# and so can contain any Ruby programming you like.
#
# \Method <tt>conf.rc?</tt> returns +true+ if a configuration file was read,
# +false+ otherwise.
# \Hash entry <tt>IRB.conf[:RC]</tt> also contains that value.
#
# === \Hash <tt>IRB.conf</tt>
#
# The initial entries in hash <tt>IRB.conf</tt> are determined by:
#
# - Default values.
# - Command-line options, which may override defaults.
# - Direct assignments in the configuration file.
#
# You can see the hash by typing <tt>IRB.conf</tt>.
#
# Details of the entries' meanings are described in the relevant subsections below.
#
# If you are interested in a specific entry, consult the
# {index}[rdoc-ref:doc/irb/indexes.md@Index+of+IRB.conf+Entries].
#
# === Notes on Initialization Precedence
#
# - Any conflict between an entry in hash <tt>IRB.conf</tt> and a command-line option
#   is resolved in favor of the hash entry.
# - \Hash <tt>IRB.conf</tt> affects the context only once,
#   when the configuration file is interpreted;
#   any subsequent changes to it do not affect the context
#   and are therefore essentially meaningless.
#
# === Initialization Script
#
# By default, the first command-line argument (after any options)
# is the path to a Ruby initialization script.
#
# \IRB reads the initialization script and puts its content onto the \IRB shell,
# just as if it were user-typed commands.
#
# Command-line option <tt>--noscript</tt> causes the first command-line argument
# to be treated as an ordinary argument (instead of an initialization script);
# <tt>--script</tt> is the default.
#
# == Input
#
# This section describes the features that allow you to change
# the way \IRB input works;
# see also {Input and Output}[rdoc-ref:IRB@Input+and+Output].
#
# === Input Command History
#
# By default, \IRB stores a history of up to 1000 input commands
# in file <tt>~/.irb_history</tt>
# (or, if a {configuration file}[rdoc-ref:IRB@Configuration+File]
# is found, in file +.irb_history+
# inin the same directory as that file).
#
# A new \IRB session creates the history file if it does not exist,
# and appends to the file if it does exist.
#
# You can change the filepath by adding to your configuration file:
# <tt>IRB.conf[:HISTORY_FILE] = _filepath_</tt>,
# where _filepath_ is a string filepath.
#
# During the session, method <tt>conf.history_file</tt> returns the filepath,
# and method <tt>conf.history_file = <i>new_filepath</i></tt>
# copies the history to the file at <i>new_filepath</i>,
# which becomes the history file for the session.
#
# You can change the number of commands saved by adding to your configuration file:
# <tt>IRB.conf[:SAVE_HISTORY] = _n_</tt>,
# where _n_ is one of:
#
# - Positive integer: the number of commands to be saved,
# - Zero: all commands are to be saved.
# - +nil+: no commands are to be saved,.
#
# During the session, you can use
# methods <tt>conf.save_history</tt> or <tt>conf.save_history=</tt>
# to retrieve or change the count.
#
# === Command Aliases
#
# By default, \IRB defines several command aliases:
#
#   irb(main):001> conf.command_aliases
#   => {:"$"=>:show_source, :"@"=>:whereami}
#
# You can change the initial aliases in the configuration file with:
#
#   IRB.conf[:COMMAND_ALIASES] = {foo: :show_source, bar: :whereami}
#
# You can replace the current aliases at any time
# with configuration method <tt>conf.command_aliases=</tt>;
# Because <tt>conf.command_aliases</tt> is a hash,
# you can modify it.
#
# === End-of-File
#
# By default, <tt>IRB.conf[:IGNORE_EOF]</tt> is +false+,
# which means that typing the end-of-file character <tt>Ctrl-D</tt>
# causes the session to exit.
#
# You can reverse that behavior by adding <tt>IRB.conf[:IGNORE_EOF] = true</tt>
# to the configuration file.
#
# During the session, method <tt>conf.ignore_eof?</tt> returns the setting,
# and method <tt>conf.ignore_eof = _boolean_</tt> sets it.
#
# === SIGINT
#
# By default, <tt>IRB.conf[:IGNORE_SIGINT]</tt> is +true+,
# which means that typing the interrupt character <tt>Ctrl-C</tt>
# causes the session to exit.
#
# You can reverse that behavior by adding <tt>IRB.conf[:IGNORE_SIGING] = false</tt>
# to the configuration file.
#
# During the session, method <tt>conf.ignore_siging?</tt> returns the setting,
# and method <tt>conf.ignore_sigint = _boolean_</tt> sets it.
#
# === Automatic Completion
#
# By default, \IRB enables
# {automatic completion}[https://en.wikipedia.org/wiki/Autocomplete#In_command-line_interpreters]:
#
# You can disable it by either of these:
#
# - Adding <tt>IRB.conf[:USE_AUTOCOMPLETE] = false</tt> to the configuration file.
# - Giving command-line option <tt>--noautocomplete</tt>
#   (<tt>--autocomplete</tt> is the default).
#
# \Method <tt>conf.use_autocomplete?</tt> returns +true+
# if automatic completion is enabled, +false+ otherwise.
#
# The setting may not be changed during the session.
#
# === Automatic Indentation
#
# By default, \IRB automatically indents lines of code to show structure
# (e.g., it indent the contents of a block).
#
# The current setting is returned
# by the configuration method <tt>conf.auto_indent_mode</tt>.
#
# The default initial setting is +true+:
#
#   irb(main):001> conf.auto_indent_mode
#   => true
#   irb(main):002* Dir.entries('.').select do |entry|
#   irb(main):003*   entry.start_with?('R')
#   irb(main):004> end
#   => ["README.md", "Rakefile"]
#
# You can change the initial setting in the
# configuration file with:
#
#   IRB.conf[:AUTO_INDENT] = false
#
# Note that the _current_ setting <i>may not</i> be changed in the \IRB session.
#
# === Input \Method
#
# The \IRB input method determines how command input is to be read;
# by default, the input method for a session is IRB::RelineInputMethod.
#
# You can set the input method by:
#
# - Adding to the configuration file:
#
#   - <tt>IRB.conf[:USE_SINGLELINE] = true</tt>
#     or <tt>IRB.conf[:USE_MULTILINE]= false</tt>
#     sets the input method to IRB::ReadlineInputMethod.
#   - <tt>IRB.conf[:USE_SINGLELINE] = false</tt>
#     or <tt>IRB.conf[:USE_MULTILINE] = true</tt>
#     sets the input method to IRB::RelineInputMethod.
#
# - Giving command-line options:
#
#   - <tt>--singleline</tt>
#     or <tt>--nomultiline</tt>
#     sets the input method to IRB::ReadlineInputMethod.
#   - <tt>--nosingleline</tt>
#     or <tt>--multiline/tt>
#     sets the input method to IRB::RelineInputMethod.
#
# \Method <tt>conf.use_multiline?</tt>
# and its synonym <tt>conf.use_reline</tt> return:
#
# - +true+ if option <tt>--multiline</tt> was given.
# - +false+ if option <tt>--nomultiline</tt> was given.
# - +nil+ if neither was given.
#
# \Method <tt>conf.use_singleline?</tt>
# and its synonym <tt>conf.use_readline</tt> return:
#
# - +true+ if option <tt>--singleline</tt> was given.
# - +false+ if option <tt>--nosingleline</tt> was given.
# - +nil+ if neither was given.
#
# == Output
#
# This section describes the features that allow you to change
# the way \IRB output works;
# see also {Input and Output}[rdoc-ref:IRB@Input+and+Output].
#
# === Return-Value Printing (Echoing)
#
# By default, \IRB prints (echoes) the values returned by all input commands.
#
# You can change the initial behavior and suppress all echoing by:
#
# - Adding to the configuration file: <tt>IRB.conf[:ECHO] = false</tt>.
#   (The default value for this entry is +niL+, which means the same as +true+.)
# - Giving command-line option <tt>--noecho</tt>.
#   (The default is <tt>--echo</tt>.)
#
# During the session, you can change the current setting
# with configuration method <tt>conf.echo=</tt> (set to +true+ or +false+).
#
# As stated above, by default \IRB prints the values returned by all input commands;
# but \IRB offers special treatment for values returned by assignment statements,
# which may be:
#
# - Printed with truncation (to fit on a single line of output),
#   which is the default;
#   an ellipsis (<tt>...</tt> is suffixed, to indicate the truncation):
#
#     irb(main):001> x = 'abc' * 100
# => "abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabc...
#
# - Printed in full (regardless of the length).
# - Suppressed (not printed at all)
#
# You can change the initial behavior by:
#
# - Adding to the configuration file: <tt>IRB.conf[:ECHO_ON_ASSIGNMENT] = false</tt>.
#   (The default value for this entry is +niL+, which means the same as +:truncate+.)
# - Giving command-line option <tt>--noecho-on-assignment</tt>
#   or <tt>--echo-on-assignment</tt>.
#   (The default is <tt>--truncate-echo-on-assigment</tt>.)
#
# During the session, you can change the current setting
# with configuration method <tt>conf.echo_on_assignment=</tt>
# (set to +true+, +false+, or +:truncate+).
#
# By default, \IRB formats returned values by calling method +inspect+.
#
# You can change the initial behavior by:
#
# - Adding to the configuration file: <tt>IRB.conf[:INSPECT_MODE] = false</tt>.
#   (The default value for this entry is +true+.)
# - Giving command-line option <tt>--noinspect</tt>.
#   (The default is <tt>--inspect</tt>.)
#
# During the session, you can change the setting using method <tt>conf.inspect_mode=</tt>.
#
# === Multiline Output
#
# By default, \IRB prefixes a newline to a multiline response.
#
# You can change the initial default value by adding to the configuation file:
#
#   IRB.conf[:NEWLINE_BEFORE_MULTILINE_OUTPUT] = false
#
# During a session, you can retrieve or set the value using
# methods <tt>conf.newline_before_multiline_output?</tt>
# and <tt>conf.newline_before_multiline_output=</tt>.
#
# Examples:
#
#   irb(main):001> conf.inspect_mode = false
#   => false
#   irb(main):002> "foo\nbar"
#   =>
#   foo
#   bar
#   irb(main):003> conf.newline_before_multiline_output = false
#   => false
#   irb(main):004> "foo\nbar"
#   => foo
#   bar
#
# === Evaluation History
#
# By default, \IRB saves no history of evaluations (returned values),
# and the related methods <tt>conf.eval_history</tt>, <tt>_</tt>,
# and <tt>__</tt> are undefined.
#
# You can turn on that history, and set the maximum number of evaluations to be stored:
#
# - In the configuration file: add <tt>IRB.conf[:EVAL_HISTORY] = _n_</tt>.
#   (Examples below assume that we've added <tt>IRB.conf[:EVAL_HISTORY] = 5</tt>.)
# - In the session (at any time): <tt>conf.eval_history = _n_</tt>.
#
# If +n+ is zero, all evaluation history is stored.
#
# Doing either of the above:
#
# - Sets the maximum size of the evaluation history;
#   defines method <tt>conf.eval_history</tt>,
#   which returns the maximum size +n+ of the evaluation history:
#
#     irb(main):001> conf.eval_history = 5
#     => 5
#     irb(main):002> conf.eval_history
#     => 5
#
# - Defines variable <tt>_</tt>, which contains the most recent evaluation,
#   or +nil+ if none; same as method <tt>conf.last_value</tt>:
#
#     irb(main):003> _
#     => 5
#     irb(main):004> :foo
#     => :foo
#     irb(main):005> :bar
#     => :bar
#     irb(main):006> _
#     => :bar
#     irb(main):007> _
#     => :bar
#
# - Defines variable <tt>__</tt>:
#
#   - <tt>__</tt> unadorned: contains all evaluation history:
#
#       irb(main):008> :foo
#       => :foo
#       irb(main):009> :bar
#       => :bar
#       irb(main):010> :baz
#       => :baz
#       irb(main):011> :bat
#       => :bat
#       irb(main):012> :bam
#       => :bam
#       irb(main):013> __
#       =>
#       9 :bar
#       10 :baz
#       11 :bat
#       12 :bam
#       irb(main):014> __
#       =>
#       10 :baz
#       11 :bat
#       12 :bam
#       13 ...self-history...
#
#     Note that when the evaluation is multiline, it is displayed differently.
#
#   - <tt>__[</tt>_m_<tt>]</tt>:
#
#     - Positive _m_:  contains the evaluation for the given line number,
#       or +nil+ if that line number is not in the evaluation history:
#
#         irb(main):015> __[12]
#         => :bam
#         irb(main):016> __[1]
#         => nil
#
#     - Negative _m_: contains the +mth+-from-end evaluation,
#       or +nil+ if that evaluation is not in the evaluation history:
#
#         irb(main):017> __[-3]
#         => :bam
#         irb(main):018> __[-13]
#         => nil
#
#     - Zero _m_: contains +nil+:
#
#         irb(main):019> __[0]
#         => nil
#
# === Prompt and Return Formats
#
# By default, \IRB uses the prompt and return value formats
# defined in its +:DEFAULT+ prompt mode.
#
# ==== The Default Prompt and Return Format
#
# The default prompt and return values look like this:
#
#   irb(main):001> 1 + 1
#   => 2
#   irb(main):002> 2 + 2
#   => 4
#
# The prompt includes:
#
# - The name of the running program (<tt>irb</tt>);
#   see {IRB Name}[rdoc-ref:IRB@IRB+Name].
# - The name of the current session (<tt>main</tt>);
#   See {IRB Sessions}[rdoc-ref:IRB@IRB+Sessions].
# - A 3-digit line number (1-based).
#
# The default prompt actually defines three formats:
#
# - One for most situations (as above):
#
#     irb(main):003> Dir
#     => Dir
#
# - One for when the typed command is a statement continuation (adds trailing asterisk):
#
#     irb(main):004* Dir.
#
# - One for when the typed command is a string continuation (adds trailing single-quote):
#
#     irb(main):005' Dir.entries('.
#
# You can see the prompt change as you type the characters in the following:
#
#     irb(main):001* Dir.entries('.').select do |entry|
#     irb(main):002*   entry.start_with?('R')
#     irb(main):003> end
#     => ["README.md", "Rakefile"]
#
# ==== Pre-Defined Prompts
#
# \IRB has several pre-defined prompts, stored in hash <tt>IRB.conf[:PROMPT]</tt>:
#
#   irb(main):001> IRB.conf[:PROMPT].keys
#   => [:NULL, :DEFAULT, :CLASSIC, :SIMPLE, :INF_RUBY, :XMP]
#
# To see the full data for these, type <tt>IRB.conf[:PROMPT]</tt>.
#
# Most of these prompt definitions include specifiers that represent
# values like the \IRB name, session name, and line number;
# see {Prompt Specifiers}[rdoc-ref:IRB@Prompt+Specifiers].
#
# You can change the initial prompt and return format by:
#
# - Adding to the configuration file: <tt>IRB.conf[:PROMPT] = _mode_</tt>
#   where _mode_ is the symbol name of a prompt mode.
# - Giving a command-line option:
#
#   - <tt>--prompt _mode_</tt>: sets the prompt mode to _mode_.
#     where _mode_ is the symbol name of a prompt mode.
#   - <tt>--simple-prompt</tt> or <tt>--sample-book-mode</tt>:
#     sets the prompt mode to +:SIMPLE+.
#   - <tt>--inf-ruby-mode</tt>: sets the prompt mode to +:INF_RUBY+
#     and suppresses both <tt>--multiline</tt> and <tt>--singleline</tt>.
#   - <tt>--noprompt</tt>: suppresses prompting; does not affect echoing.
#
# You can retrieve or set the current prompt mode with methods
#
# <tt>conf.prompt_mode</tt> and <tt>conf.prompt_mode=</tt>.
#
# If you're interested in prompts and return formats other than the defaults,
# you might experiment by trying some of the others.
#
# ==== Custom Prompts
#
# You can also define custom prompts and return formats,
# which may be done either in an \IRB session or in the configuration file.
#
# A prompt in \IRB actually defines three prompts, as seen above.
# For simple custom data, we'll make all three the same:
#
#   irb(main):001* IRB.conf[:PROMPT][:MY_PROMPT] = {
#   irb(main):002*   PROMPT_I: ': ',
#   irb(main):003*   PROMPT_C: ': ',
#   irb(main):004*   PROMPT_S: ': ',
#   irb(main):005*   RETURN: '=> '
#   irb(main):006> }
#   => {:PROMPT_I=>": ", :PROMPT_C=>": ", :PROMPT_S=>": ", :RETURN=>"=> "}
#
# If you define the custom prompt in the configuration file,
# you can also make it the current prompt by adding:
#
#   IRB.conf[:PROMPT_MODE] = :MY_PROMPT
#
# Regardless of where it's defined, you can make it the current prompt in a session:
#
#   conf.prompt_mode = :MY_PROMPT
#
# You can view or modify the current prompt data with various configuration methods:
#
# - <tt>conf.prompt_mode</tt>, <tt>conf.prompt_mode=</tt>.
# - <tt>conf.prompt_c</tt>, <tt>conf.c=</tt>.
# - <tt>conf.prompt_i</tt>, <tt>conf.i=</tt>.
# - <tt>conf.prompt_s</tt>, <tt>conf.s=</tt>.
# - <tt>conf.return_format</tt>, <tt>return_format=</tt>.
#
# ==== Prompt Specifiers
#
# A prompt's definition can include specifiers for which certain values are substituted:
#
# - <tt>%N</tt>: the name of the running program.
# - <tt>%m</tt>: the value of <tt>self.to_s</tt>.
# - <tt>%M</tt>: the value of <tt>self.inspect</tt>.
# - <tt>%l</tt>: an indication of the type of string;
#   one of <tt>"</tt>, <tt>'</tt>, <tt>/</tt>, <tt>]</tt>.
# - <tt><i>NN</i>i</tt>: Indentation level.
# - <tt><i>NN</i>n</tt>: Line number.
# - <tt>%%</tt>: Literal <tt>%</tt>.
#
# === Verbosity
#
# By default, \IRB verbosity is disabled, which means that output is smaller
# rather than larger.
#
# You can enable verbosity by:
#
# - Adding to the configuration file: <tt>IRB.conf[:VERBOSE] = true</tt>
#   (the default is +nil+).
# - Giving command-line options <tt>--verbose</tt>
#   (the default is <tt>--noverbose</tt>).
#
# During a session, you can retrieve or set verbosity with methods
# <tt>conf.verbose</tt> and <tt>conf.verbose=</tt>.
#
# === Help
#
# Command-line option <tt>--version</tt> causes \IRB to print its help text
# and exit.
#
# === Version
#
# Command-line option <tt>--version</tt> causes \IRB to print its version text
# and exit.
#
# == Input and Output
#
# === \Color Highlighting
#
# By default, \IRB color highlighting is enabled, and is used for both:
#
# - Input: As you type, \IRB reads the typed characters and highlights
#   elements that it recognizes;
#   it also highlights errors such as mismatched parentheses.
# - Output: \IRB highlights syntactical elements.
#
# You can disable color highlighting by:
#
# - Adding to the configuration file: <tt>IRB.conf[:USE_COLORIZE] = false</tt>
#   (the default value is +true+).
# - Giving command-line option <tt>--nocolorize</tt>
#
# == Debugging
#
# Command-line option <tt>-d</tt> sets variables <tt>$VERBOSE</tt>
# and <tt>$DEBUG</tt> to +true+;
# these have no effect on \IRB output.
#
# === Warnings
#
# Command-line option <tt>-w</tt> suppresses warnings.
#
# Command-line option <tt>-W[_level_]<tt>
# sets warning level; 0=silence, 1=medium, 2=verbose.
#
# :stopdoc:
# === Performance Measurement
#
# IRB.conf[:MEASURE] IRB.conf[:MEASURE_CALLBACKS] IRB.conf[:MEASURE_PROC]
# :startdoc:
#
# == Other Features
#
# === Load Modules
#
# You can specify the names of modules that are to be required at startup.
#
# \Array <tt>conf.load_modules</tt> determines the modules (if any)
# that are to be required during session startup.
# The array is used only during session startup,
# so the initial value is the only one that counts.
#
# The default initial value is <tt>[]</tt> (load no modules):
#
#   irb(main):001> conf.load_modules
#   => []
#
# You can set the default initial value via:
#
# - Command-line option <tt>-r</tt>
#
#     $ irb -r csv -r json
#    irb(main):001> conf.load_modules
#    => ["csv", "json"]
#
# - \Hash entry <tt>IRB.conf[:LOAD_MODULES] = _array_</tt>:
#
#     IRB.conf[:LOAD_MODULES] = %w[csv, json]
#
# Note that the configuration file entry overrides the command-line options.
#
# === RI Documentation Directories
#
# You can specify the paths to RI documentation directories
# that are to be loaded (in addition to the default directories) at startup;
# see details about RI by typing <tt>ri --help</tt>.
#
# \Array <tt>conf.extra_doc_dirs</tt> determines the directories (if any)
# that are to be loaded during session startup.
# The array is used only during session startup,
# so the initial value is the only one that counts.
#
# The default initial value is <tt>[]</tt> (load no extra documentation):
#
#   irb(main):001> conf.extra_doc_dirs
#   => []
#
# You can set the default initial value via:
#
# - Command-line option <tt>--extra_doc_dir</tt>
#
#     $ irb --extra-doc-dir your_doc_dir --extra-doc-dir my_doc_dir
#     irb(main):001> conf.extra_doc_dirs
#     => ["your_doc_dir", "my_doc_dir"]
#
# - \Hash entry <tt>IRB.conf[:EXTRA_DOC_DIRS] = _array_</tt>:
#
#     IRB.conf[:EXTRA_DOC_DIRS] = %w[your_doc_dir my_doc_dir]
#
# Note that the configuration file entry overrides the command-line options.
#
# :stopdoc:
# === \Context Mode
#
# IRB.conf[:CONTEXT_MODE]
# :startdoc:
#
# === \IRB Name
#
# You can specify a name for \IRB.
#
# The default initial value is <tt>'irb'</tt>:
#
#   irb(main):001> conf.irb_name
#   => "irb"
#
# You can set the default initial value
# via hash entry <tt>IRB.conf[:IRB_NAME] = _string_</tt>:
#
#   IRB.conf[:IRB_NAME] = 'foo'
#
# === Application Name
#
# You can specify an application name for the \IRB session.
#
# The default initial value is <tt>'irb'</tt>:
#
#   irb(main):001> conf.ap_name
#   => "irb"
#
# You can set the default initial value
# via hash entry <tt>IRB.conf[:AP_NAME] = _string_</tt>:
#
#   IRB.conf[:AP_NAME] = 'my_ap_name'
#
# === Configuration Monitor
#
# You can monitor changes to the configuration by assigning a proc
# to <tt>IRB.conf[:IRB_RC]</tt> in the configuration file:
#
#   IRB.conf[:IRB_RC] = proc {|conf| puts conf.class }
#
# Each time the configuration is changed,
# that proc is called with argument +conf+:
#
# :stopdoc:
# === \Locale
#
# IRB.conf[:LC_MESSAGES]
# :startdoc:
#
# === Encodings
#
# Command-line option <tt>-E _ex_[:_in_]</tt>
# sets initial external (ex) and internal (in) encodings.
#
# Command-line option <tt>-U</tt> sets both to UTF-8.
#
# === Commands
#
# Please use the `show_cmds` command to see the list of available commands.
#
# === IRB Sessions
#
# IRB has a special feature, that allows you to manage many sessions at once.
#
# You can create new sessions with Irb.irb, and get a list of current sessions
# with the +jobs+ command in the prompt.
#
# ==== Configuration
#
# The command line options, or IRB.conf, specify the default behavior of
# Irb.irb.
#
# On the other hand, each conf in IRB@Command-Line+Options is used to
# individually configure IRB.irb.
#
# If a proc is set for <code>IRB.conf[:IRB_RC]</code>, its will be invoked after execution
# of that proc with the context of the current session as its argument. Each
# session can be configured using this mechanism.
#
# ==== Session variables
#
# There are a few variables in every Irb session that can come in handy:
#
# <code>_</code>::
#   The value command executed, as a local variable
# <code>__</code>::
#   The history of evaluated commands. Available only if
#   <code>IRB.conf[:EVAL_HISTORY]</code> is not +nil+ (which is the default).
#   See also IRB::Context#eval_history= and IRB::History.
# <code>__[line_no]</code>::
#   Returns the evaluation value at the given line number, +line_no+.
#   If +line_no+ is a negative, the return value +line_no+ many lines before
#   the most recent return value.
#
# == Restrictions
#
# Ruby code typed into \IRB behaves the same as Ruby code in a file, except that:
#
# - Because \IRB evaluates input immediately after it is syntactically complete,
#   some results may be slightly different.
# - Forking may not be well behaved.
#
module IRB

  # An exception raised by IRB.irb_abort
  class Abort < Exception;end

  # The current IRB::Context of the session, see IRB.conf
  #
  #   irb
  #   irb(main):001:0> IRB.CurrentContext.irb_name = "foo"
  #   foo(main):002:0> IRB.conf[:MAIN_CONTEXT].irb_name #=> "foo"
  def IRB.CurrentContext
    IRB.conf[:MAIN_CONTEXT]
  end

  # Initializes IRB and creates a new Irb.irb object at the +TOPLEVEL_BINDING+
  def IRB.start(ap_path = nil)
    STDOUT.sync = true
    $0 = File::basename(ap_path, ".rb") if ap_path

    IRB.setup(ap_path)

    if @CONF[:SCRIPT]
      irb = Irb.new(nil, @CONF[:SCRIPT])
    else
      irb = Irb.new
    end
    irb.run(@CONF)
  end

  # Quits irb
  def IRB.irb_exit(irb, ret)
    throw :IRB_EXIT, ret
  end

  # Aborts then interrupts irb.
  #
  # Will raise an Abort exception, or the given +exception+.
  def IRB.irb_abort(irb, exception = Abort)
    irb.context.thread.raise exception, "abort then interrupt!"
  end

  class Irb
    # Note: instance and index assignment expressions could also be written like:
    # "foo.bar=(1)" and "foo.[]=(1, bar)", when expressed that way, the former
    # be parsed as :assign and echo will be suppressed, but the latter is
    # parsed as a :method_add_arg and the output won't be suppressed

    PROMPT_MAIN_TRUNCATE_LENGTH = 32
    PROMPT_MAIN_TRUNCATE_OMISSION = '...'.freeze
    CONTROL_CHARACTERS_PATTERN = "\x00-\x1F".freeze

    # Returns the current context of this irb session
    attr_reader :context
    # The lexer used by this irb session
    attr_accessor :scanner

    # Creates a new irb session
    def initialize(workspace = nil, input_method = nil)
      @context = Context.new(self, workspace, input_method)
      @context.workspace.load_commands_to_main
      @signal_status = :IN_IRB
      @scanner = RubyLex.new
      @line_no = 1
    end

    # A hook point for `debug` command's breakpoint after :IRB_EXIT as well as its clean-up
    def debug_break
      # it means the debug integration has been activated
      if defined?(DEBUGGER__) && DEBUGGER__.respond_to?(:capture_frames_without_irb)
        # after leaving this initial breakpoint, revert the capture_frames patch
        DEBUGGER__.singleton_class.send(:alias_method, :capture_frames, :capture_frames_without_irb)
        # and remove the redundant method
        DEBUGGER__.singleton_class.send(:undef_method, :capture_frames_without_irb)
      end
    end

    def debug_readline(binding)
      workspace = IRB::WorkSpace.new(binding)
      context.workspace = workspace
      context.workspace.load_commands_to_main
      @line_no += 1

      # When users run:
      # 1. Debugging commands, like `step 2`
      # 2. Any input that's not irb-command, like `foo = 123`
      #
      # Irb#eval_input will simply return the input, and we need to pass it to the debugger.
      input = if IRB.conf[:SAVE_HISTORY] && context.io.support_history_saving?
        # Previous IRB session's history has been saved when `Irb#run` is exited
        # We need to make sure the saved history is not saved again by reseting the counter
        context.io.reset_history_counter

        begin
          eval_input
        ensure
          context.io.save_history
        end
      else
        eval_input
      end

      if input&.include?("\n")
        @line_no += input.count("\n") - 1
      end

      input
    end

    def run(conf = IRB.conf)
      in_nested_session = !!conf[:MAIN_CONTEXT]
      conf[:IRB_RC].call(context) if conf[:IRB_RC]
      conf[:MAIN_CONTEXT] = context

      save_history = !in_nested_session && conf[:SAVE_HISTORY] && context.io.support_history_saving?

      if save_history
        context.io.load_history
      end

      prev_trap = trap("SIGINT") do
        signal_handle
      end

      begin
        catch(:IRB_EXIT) do
          eval_input
        end
      ensure
        trap("SIGINT", prev_trap)
        conf[:AT_EXIT].each{|hook| hook.call}
        context.io.save_history if save_history
      end
    end

    # Evaluates input for this session.
    def eval_input
      configure_io

      each_top_level_statement do |statement, line_no|
        signal_status(:IN_EVAL) do
          begin
            # If the integration with debugger is activated, we return certain input if it should be dealt with by debugger
            if @context.with_debugger && statement.should_be_handled_by_debugger?
              return statement.code
            end

            @context.evaluate(statement.evaluable_code, line_no)

            if @context.echo? && !statement.suppresses_echo?
              if statement.is_assignment?
                if @context.echo_on_assignment?
                  output_value(@context.echo_on_assignment? == :truncate)
                end
              else
                output_value
              end
            end
          rescue SystemExit, SignalException
            raise
          rescue Interrupt, Exception => exc
            handle_exception(exc)
            @context.workspace.local_variable_set(:_, exc)
          end
        end
      end
    end

    def read_input(prompt)
      signal_status(:IN_INPUT) do
        @context.io.prompt = prompt
        if l = @context.io.gets
          print l if @context.verbose?
        else
          if @context.ignore_eof? and @context.io.readable_after_eof?
            l = "\n"
            if @context.verbose?
              printf "Use \"exit\" to leave %s\n", @context.ap_name
            end
          else
            print "\n" if @context.prompting?
          end
        end
        l
      end
    end

    def readmultiline
      prompt = generate_prompt([], false, 0)

      # multiline
      return read_input(prompt) if @context.io.respond_to?(:check_termination)

      # nomultiline
      code = ''
      line_offset = 0
      loop do
        line = read_input(prompt)
        unless line
          return code.empty? ? nil : code
        end

        code << line

        # Accept any single-line input for symbol aliases or commands that transform args
        return code if single_line_command?(code)

        tokens, opens, terminated = @scanner.check_code_state(code, local_variables: @context.local_variables)
        return code if terminated

        line_offset += 1
        continue = @scanner.should_continue?(tokens)
        prompt = generate_prompt(opens, continue, line_offset)
      end
    end

    def each_top_level_statement
      loop do
        code = readmultiline
        break unless code

        if code != "\n"
          yield build_statement(code), @line_no
        end
        @line_no += code.count("\n")
      rescue RubyLex::TerminateLineInput
      end
    end

    def build_statement(code)
      code.force_encoding(@context.io.encoding)
      command_or_alias, arg = code.split(/\s/, 2)
      # Transform a non-identifier alias (@, $) or keywords (next, break)
      command_name = @context.command_aliases[command_or_alias.to_sym]
      command = command_name || command_or_alias
      command_class = ExtendCommandBundle.load_command(command)

      if command_class
        Statement::Command.new(code, command, arg, command_class)
      else
        is_assignment_expression = @scanner.assignment_expression?(code, local_variables: @context.local_variables)
        Statement::Expression.new(code, is_assignment_expression)
      end
    end

    def single_line_command?(code)
      command = code.split(/\s/, 2).first
      @context.symbol_alias?(command) || @context.transform_args?(command)
    end

    def configure_io
      if @context.io.respond_to?(:check_termination)
        @context.io.check_termination do |code|
          if Reline::IOGate.in_pasting?
            rest = @scanner.check_termination_in_prev_line(code, local_variables: @context.local_variables)
            if rest
              Reline.delete_text
              rest.bytes.reverse_each do |c|
                Reline.ungetc(c)
              end
              true
            else
              false
            end
          else
            # Accept any single-line input for symbol aliases or commands that transform args
            next true if single_line_command?(code)

            _tokens, _opens, terminated = @scanner.check_code_state(code, local_variables: @context.local_variables)
            terminated
          end
        end
      end
      if @context.io.respond_to?(:dynamic_prompt)
        @context.io.dynamic_prompt do |lines|
          lines << '' if lines.empty?
          tokens = RubyLex.ripper_lex_without_warning(lines.map{ |l| l + "\n" }.join, local_variables: @context.local_variables)
          line_results = IRB::NestingParser.parse_by_line(tokens)
          tokens_until_line = []
          line_results.map.with_index do |(line_tokens, _prev_opens, next_opens, _min_depth), line_num_offset|
            line_tokens.each do |token, _s|
              # Avoid appending duplicated token. Tokens that include "\n" like multiline tstring_content can exist in multiple lines.
              tokens_until_line << token if token != tokens_until_line.last
            end
            continue = @scanner.should_continue?(tokens_until_line)
            generate_prompt(next_opens, continue, line_num_offset)
          end
        end
      end

      if @context.io.respond_to?(:auto_indent) and @context.auto_indent_mode
        @context.io.auto_indent do |lines, line_index, byte_pointer, is_newline|
          next nil if lines == [nil] # Workaround for exit IRB with CTRL+d
          next nil if !is_newline && lines[line_index]&.byteslice(0, byte_pointer)&.match?(/\A\s*\z/)

          code = lines[0..line_index].map { |l| "#{l}\n" }.join
          tokens = RubyLex.ripper_lex_without_warning(code, local_variables: @context.local_variables)
          @scanner.process_indent_level(tokens, lines, line_index, is_newline)
        end
      end
    end

    def convert_invalid_byte_sequence(str, enc)
      str.force_encoding(enc)
      str.scrub { |c|
        c.bytes.map{ |b| "\\x#{b.to_s(16).upcase}" }.join
      }
    end

    def encode_with_invalid_byte_sequence(str, enc)
      conv = Encoding::Converter.new(str.encoding, enc)
      dst = String.new
      begin
        ret = conv.primitive_convert(str, dst)
        case ret
        when :invalid_byte_sequence
          conv.insert_output(conv.primitive_errinfo[3].dump[1..-2])
          redo
        when :undefined_conversion
          c = conv.primitive_errinfo[3].dup.force_encoding(conv.primitive_errinfo[1])
          conv.insert_output(c.dump[1..-2])
          redo
        when :incomplete_input
          conv.insert_output(conv.primitive_errinfo[3].dump[1..-2])
        when :finished
        end
        break
      end while nil
      dst
    end

    def handle_exception(exc)
      if exc.backtrace[0] =~ /\/irb(2)?(\/.*|-.*|\.rb)?:/ && exc.class.to_s !~ /^IRB/ &&
         !(SyntaxError === exc) && !(EncodingError === exc)
        # The backtrace of invalid encoding hash (ex. {"\xAE": 1}) raises EncodingError without lineno.
        irb_bug = true
      else
        irb_bug = false
      end

      if RUBY_VERSION < '3.0.0'
        if STDOUT.tty?
          message = exc.full_message(order: :bottom)
          order = :bottom
        else
          message = exc.full_message(order: :top)
          order = :top
        end
      else # '3.0.0' <= RUBY_VERSION
        message = exc.full_message(order: :top)
        order = :top
      end
      message = convert_invalid_byte_sequence(message, exc.message.encoding)
      message = encode_with_invalid_byte_sequence(message, IRB.conf[:LC_MESSAGES].encoding) unless message.encoding.to_s.casecmp?(IRB.conf[:LC_MESSAGES].encoding.to_s)
      message = message.gsub(/((?:^\t.+$\n)+)/) { |m|
        case order
        when :top
          lines = m.split("\n")
        when :bottom
          lines = m.split("\n").reverse
        end
        unless irb_bug
          lines = lines.map { |l| @context.workspace.filter_backtrace(l) }.compact
          if lines.size > @context.back_trace_limit
            omit = lines.size - @context.back_trace_limit
            lines = lines[0..(@context.back_trace_limit - 1)]
            lines << "\t... %d levels..." % omit
          end
        end
        lines = lines.reverse if order == :bottom
        lines.map{ |l| l + "\n" }.join
      }
      # The "<top (required)>" in "(irb)" may be the top level of IRB so imitate the main object.
      message = message.gsub(/\(irb\):(?<num>\d+):in `<(?<frame>top \(required\))>'/) { "(irb):#{$~[:num]}:in `<main>'" }
      puts message
      puts 'Maybe IRB bug!' if irb_bug
    rescue Exception => handler_exc
      begin
        puts exc.inspect
        puts "backtraces are hidden because #{handler_exc} was raised when processing them"
      rescue Exception
        puts 'Uninspectable exception occurred'
      end
    end

    # Evaluates the given block using the given +path+ as the Context#irb_path
    # and +name+ as the Context#irb_name.
    #
    # Used by the irb command +source+, see IRB@IRB+Sessions for more
    # information.
    def suspend_name(path = nil, name = nil)
      @context.irb_path, back_path = path, @context.irb_path if path
      @context.irb_name, back_name = name, @context.irb_name if name
      begin
        yield back_path, back_name
      ensure
        @context.irb_path = back_path if path
        @context.irb_name = back_name if name
      end
    end

    # Evaluates the given block using the given +workspace+ as the
    # Context#workspace.
    #
    # Used by the irb command +irb_load+, see IRB@IRB+Sessions for more
    # information.
    def suspend_workspace(workspace)
      @context.workspace, back_workspace = workspace, @context.workspace
      begin
        yield back_workspace
      ensure
        @context.workspace = back_workspace
      end
    end

    # Evaluates the given block using the given +input_method+ as the
    # Context#io.
    #
    # Used by the irb commands +source+ and +irb_load+, see IRB@IRB+Sessions
    # for more information.
    def suspend_input_method(input_method)
      back_io = @context.io
      @context.instance_eval{@io = input_method}
      begin
        yield back_io
      ensure
        @context.instance_eval{@io = back_io}
      end
    end

    # Handler for the signal SIGINT, see Kernel#trap for more information.
    def signal_handle
      unless @context.ignore_sigint?
        print "\nabort!\n" if @context.verbose?
        exit
      end

      case @signal_status
      when :IN_INPUT
        print "^C\n"
        raise RubyLex::TerminateLineInput
      when :IN_EVAL
        IRB.irb_abort(self)
      when :IN_LOAD
        IRB.irb_abort(self, LoadAbort)
      when :IN_IRB
        # ignore
      else
        # ignore other cases as well
      end
    end

    # Evaluates the given block using the given +status+.
    def signal_status(status)
      return yield if @signal_status == :IN_LOAD

      signal_status_back = @signal_status
      @signal_status = status
      begin
        yield
      ensure
        @signal_status = signal_status_back
      end
    end

    def output_value(omit = false) # :nodoc:
      str = @context.inspect_last_value
      multiline_p = str.include?("\n")
      if omit
        winwidth = @context.io.winsize.last
        if multiline_p
          first_line = str.split("\n").first
          result = @context.newline_before_multiline_output? ? (@context.return_format % first_line) : first_line
          output_width = Reline::Unicode.calculate_width(result, true)
          diff_size = output_width - Reline::Unicode.calculate_width(first_line, true)
          if diff_size.positive? and output_width > winwidth
            lines, _ = Reline::Unicode.split_by_width(first_line, winwidth - diff_size - 3)
            str = "%s..." % lines.first
            str += "\e[0m" if Color.colorable?
            multiline_p = false
          else
            str = str.gsub(/(\A.*?\n).*/m, "\\1...")
            str += "\e[0m" if Color.colorable?
          end
        else
          output_width = Reline::Unicode.calculate_width(@context.return_format % str, true)
          diff_size = output_width - Reline::Unicode.calculate_width(str, true)
          if diff_size.positive? and output_width > winwidth
            lines, _ = Reline::Unicode.split_by_width(str, winwidth - diff_size - 3)
            str = "%s..." % lines.first
            str += "\e[0m" if Color.colorable?
          end
        end
      end

      if multiline_p && @context.newline_before_multiline_output?
        str = "\n" + str
      end

      Pager.page_content(format(@context.return_format, str), retain_content: true)
    end

    # Outputs the local variables to this current session, including
    # #signal_status and #context, using IRB::Locale.
    def inspect
      ary = []
      for iv in instance_variables
        case (iv = iv.to_s)
        when "@signal_status"
          ary.push format("%s=:%s", iv, @signal_status.id2name)
        when "@context"
          ary.push format("%s=%s", iv, eval(iv).__to_s__)
        else
          ary.push format("%s=%s", iv, eval(iv))
        end
      end
      format("#<%s: %s>", self.class, ary.join(", "))
    end

    private

    def generate_prompt(opens, continue, line_offset)
      ltype = @scanner.ltype_from_open_tokens(opens)
      indent = @scanner.calc_indent_level(opens)
      continue = opens.any? || continue
      line_no = @line_no + line_offset

      if ltype
        f = @context.prompt_s
      elsif continue
        f = @context.prompt_c
      else
        f = @context.prompt_i
      end
      f = "" unless f
      if @context.prompting?
        p = format_prompt(f, ltype, indent, line_no)
      else
        p = ""
      end
      if @context.auto_indent_mode and !@context.io.respond_to?(:auto_indent)
        unless ltype
          prompt_i = @context.prompt_i.nil? ? "" : @context.prompt_i
          ind = format_prompt(prompt_i, ltype, indent, line_no)[/.*\z/].size +
            indent * 2 - p.size
          p += " " * ind if ind > 0
        end
      end
      p
    end

    def truncate_prompt_main(str) # :nodoc:
      str = str.tr(CONTROL_CHARACTERS_PATTERN, ' ')
      if str.size <= PROMPT_MAIN_TRUNCATE_LENGTH
        str
      else
        str[0, PROMPT_MAIN_TRUNCATE_LENGTH - PROMPT_MAIN_TRUNCATE_OMISSION.size] + PROMPT_MAIN_TRUNCATE_OMISSION
      end
    end

    def format_prompt(format, ltype, indent, line_no) # :nodoc:
      format.gsub(/%([0-9]+)?([a-zA-Z])/) do
        case $2
        when "N"
          @context.irb_name
        when "m"
          main_str = @context.main.to_s rescue "!#{$!.class}"
          truncate_prompt_main(main_str)
        when "M"
          main_str = @context.main.inspect rescue "!#{$!.class}"
          truncate_prompt_main(main_str)
        when "l"
          ltype
        when "i"
          if indent < 0
            if $1
              "-".rjust($1.to_i)
            else
              "-"
            end
          else
            if $1
              format("%" + $1 + "d", indent)
            else
              indent.to_s
            end
          end
        when "n"
          if $1
            format("%" + $1 + "d", line_no)
          else
            line_no.to_s
          end
        when "%"
          "%"
        end
      end
    end
  end
end

class Binding
  # Opens an IRB session where +binding.irb+ is called which allows for
  # interactive debugging. You can call any methods or variables available in
  # the current scope, and mutate state if you need to.
  #
  #
  # Given a Ruby file called +potato.rb+ containing the following code:
  #
  #     class Potato
  #       def initialize
  #         @cooked = false
  #         binding.irb
  #         puts "Cooked potato: #{@cooked}"
  #       end
  #     end
  #
  #     Potato.new
  #
  # Running <code>ruby potato.rb</code> will open an IRB session where
  # +binding.irb+ is called, and you will see the following:
  #
  #     $ ruby potato.rb
  #
  #     From: potato.rb @ line 4 :
  #
  #         1: class Potato
  #         2:   def initialize
  #         3:     @cooked = false
  #      => 4:     binding.irb
  #         5:     puts "Cooked potato: #{@cooked}"
  #         6:   end
  #         7: end
  #         8:
  #         9: Potato.new
  #
  #     irb(#<Potato:0x00007feea1916670>):001:0>
  #
  # You can type any valid Ruby code and it will be evaluated in the current
  # context. This allows you to debug without having to run your code repeatedly:
  #
  #     irb(#<Potato:0x00007feea1916670>):001:0> @cooked
  #     => false
  #     irb(#<Potato:0x00007feea1916670>):002:0> self.class
  #     => Potato
  #     irb(#<Potato:0x00007feea1916670>):003:0> caller.first
  #     => ".../2.5.1/lib/ruby/2.5.0/irb/workspace.rb:85:in `eval'"
  #     irb(#<Potato:0x00007feea1916670>):004:0> @cooked = true
  #     => true
  #
  # You can exit the IRB session with the +exit+ command. Note that exiting will
  # resume execution where +binding.irb+ had paused it, as you can see from the
  # output printed to standard output in this example:
  #
  #     irb(#<Potato:0x00007feea1916670>):005:0> exit
  #     Cooked potato: true
  #
  # See IRB for more information.
  def irb(show_code: true)
    # Setup IRB with the current file's path and no command line arguments
    IRB.setup(source_location[0], argv: [])
    # Create a new workspace using the current binding
    workspace = IRB::WorkSpace.new(self)
    # Print the code around the binding if show_code is true
    STDOUT.print(workspace.code_around_binding) if show_code
    # Get the original IRB instance
    debugger_irb = IRB.instance_variable_get(:@debugger_irb)

    irb_path = File.expand_path(source_location[0])

    if debugger_irb
      # If we're already in a debugger session, set the workspace and irb_path for the original IRB instance
      debugger_irb.context.workspace = workspace
      debugger_irb.context.irb_path = irb_path
      # If we've started a debugger session and hit another binding.irb, we don't want to start an IRB session
      # instead, we want to resume the irb:rdbg session.
      IRB::Debug.setup(debugger_irb)
      IRB::Debug.insert_debug_break
      debugger_irb.debug_break
    else
      # If we're not in a debugger session, create a new IRB instance with the current workspace
      binding_irb = IRB::Irb.new(workspace)
      binding_irb.context.irb_path = irb_path
      binding_irb.run(IRB.conf)
      binding_irb.debug_break
    end
  end
end
