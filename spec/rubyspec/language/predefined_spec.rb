require File.expand_path('../../spec_helper', __FILE__)
require 'stringio'

# The following tables are excerpted from Programming Ruby: The Pragmatic Programmer's Guide'
# Second Edition by Dave Thomas, Chad Fowler, and Andy Hunt, page 319-22.
#
# Entries marked [r/o] are read-only and an error will be raised of the program attempts to
# modify them. Entries marked [thread] are thread local.

=begin
Exception Information
---------------------------------------------------------------------------------------------------

$!               Exception       The exception object passed to raise. [thread]
$@               Array           The stack backtrace generated by the last exception. [thread]
=end

=begin
Pattern Matching Variables
---------------------------------------------------------------------------------------------------

These variables are set to nil after an unsuccessful pattern match.

$&               String          The string matched (following a successful pattern match). This variable is
                                 local to the current scope. [r/o, thread]
$+               String          The contents of the highest-numbered group matched following a successful
                                 pattern match. Thus, in "cat" =~/(c|a)(t|z)/, $+ will be set to “t”. This
                                 variable is local to the current scope. [r/o, thread]
$`               String          The string preceding the match in a successful pattern match. This variable
                                 is local to the current scope. [r/o, thread]
$'               String          The string following the match in a successful pattern match. This variable
                                 is local to the current scope. [r/o, thread]
$1 to $9         String          The contents of successive groups matched in a successful pattern match. In
                                 "cat" =~/(c|a)(t|z)/, $1 will be set to “a” and $2 to “t”. This variable
                                 is local to the current scope. [r/o, thread]
$~               MatchData       An object that encapsulates the results of a successful pattern match. The
                                 variables $&, $`, $', and $1 to $9 are all derived from $~. Assigning to $~
                                 changes the values of these derived variables. This variable is local to the
                                 current scope. [thread]
=end


describe "Predefined global $~" do
  it "is set to contain the MatchData object of the last match if successful" do
    md = /foo/.match 'foo'
    $~.should be_kind_of(MatchData)
    $~.object_id.should == md.object_id

    /bar/ =~ 'bar'
    $~.should be_kind_of(MatchData)
    $~.object_id.should_not == md.object_id
  end

  it "is set to nil if the last match was unsuccessful" do
    /foo/ =~ 'foo'
    $~.nil?.should == false

    /foo/ =~ 'bar'
    $~.nil?.should == true
  end

  it "is set at the method-scoped level rather than block-scoped" do
    obj = Object.new
    def obj.foo; yield; end
    def obj.foo2(&proc); proc.call; end

    match2 = nil
    match3 = nil
    match4 = nil

    match1 = /foo/.match "foo"

    obj.foo { match2 = /bar/.match("bar") }

    match2.should_not == nil
    $~.should == match2

    eval 'match3 = /baz/.match("baz")'

    match3.should_not == nil
    $~.should == match3

    obj.foo2 { match4 = /qux/.match("qux") }

    match4.should_not == nil
    $~.should == match4
  end

  it "raises an error if assigned an object not nil or instanceof MatchData" do
    $~ = nil
    $~.should == nil
    $~ = /foo/.match("foo")
    $~.should be_an_instance_of(MatchData)

    lambda { $~ = Object.new }.should raise_error(TypeError)
    lambda { $~ = 1 }.should raise_error(TypeError)
  end

  it "changes the value of derived capture globals when assigned" do
    "foo" =~ /(f)oo/
    foo_match = $~
    "bar" =~ /(b)ar/
    $~ = foo_match
    $1.should == "f"
  end

  it "changes the value of the derived preceding match global" do
    "foo hello" =~ /hello/
    foo_match = $~
    "bar" =~ /(bar)/
    $~ = foo_match
    $`.should == "foo "
  end

  it "changes the value of the derived following match global" do
    "foo hello" =~ /foo/
    foo_match = $~
    "bar" =~ /(bar)/
    $~ = foo_match
    $'.should == " hello"
  end

  it "changes the value of the derived full match global" do
    "foo hello" =~ /foo/
    foo_match = $~
    "bar" =~ /(bar)/
    $~ = foo_match
    $&.should == "foo"
  end
end

describe "Predefined global $&" do
  it "is equivalent to MatchData#[0] on the last match $~" do
    /foo/ =~ 'barfoobaz'
    $&.should == $~[0]
    $&.should == 'foo'
  end

  with_feature :encoding do
    it "sets the encoding to the encoding of the source String" do
      "abc".force_encoding(Encoding::EUC_JP) =~ /b/
      $&.encoding.should equal(Encoding::EUC_JP)
    end
  end
end

describe "Predefined global $`" do
  it "is equivalent to MatchData#pre_match on the last match $~" do
    /foo/ =~ 'barfoobaz'
    $`.should == $~.pre_match
    $`.should == 'bar'
  end

  with_feature :encoding do
    it "sets the encoding to the encoding of the source String" do
      "abc".force_encoding(Encoding::EUC_JP) =~ /b/
      $`.encoding.should equal(Encoding::EUC_JP)
    end

    it "sets an empty result to the encoding of the source String" do
      "abc".force_encoding(Encoding::ISO_8859_1) =~ /a/
      $`.encoding.should equal(Encoding::ISO_8859_1)
    end
  end
end

describe "Predefined global $'" do
  it "is equivalent to MatchData#post_match on the last match $~" do
    /foo/ =~ 'barfoobaz'
    $'.should == $~.post_match
    $'.should == 'baz'
  end

  with_feature :encoding do
    it "sets the encoding to the encoding of the source String" do
      "abc".force_encoding(Encoding::EUC_JP) =~ /b/
      $'.encoding.should equal(Encoding::EUC_JP)
    end

    it "sets an empty result to the encoding of the source String" do
      "abc".force_encoding(Encoding::ISO_8859_1) =~ /c/
      $'.encoding.should equal(Encoding::ISO_8859_1)
    end
  end
end

describe "Predefined global $+" do
  it "is equivalent to $~.captures.last" do
    /(f(o)o)/ =~ 'barfoobaz'
    $+.should == $~.captures.last
    $+.should == 'o'
  end

  it "captures the last non nil capture" do
    /(a)|(b)/ =~ 'a'
    $+.should == 'a'
  end

  with_feature :encoding do
    it "sets the encoding to the encoding of the source String" do
      "abc".force_encoding(Encoding::EUC_JP) =~ /(b)/
      $+.encoding.should equal(Encoding::EUC_JP)
    end
  end
end

describe "Predefined globals $1..N" do
  it "are equivalent to $~[N]" do
    /(f)(o)(o)/ =~ 'foo'
    $1.should == $~[1]
    $2.should == $~[2]
    $3.should == $~[3]
    $4.should == $~[4]

    [$1, $2, $3, $4].should == ['f', 'o', 'o', nil]
  end

  it "are nil unless a match group occurs" do
    def test(arg)
      case arg
      when /-(.)?/
        $1
      end
    end
    test("-").should == nil
  end

  with_feature :encoding do
    it "sets the encoding to the encoding of the source String" do
      "abc".force_encoding(Encoding::EUC_JP) =~ /(b)/
      $1.encoding.should equal(Encoding::EUC_JP)
    end
  end
end

describe "Predefined global $stdout" do
  before :each do
    @old_stdout = $stdout
  end

  after :each do
    $stdout = @old_stdout
  end

  it "raises TypeError error if assigned to nil" do
    lambda { $stdout = nil }.should raise_error(TypeError)
  end

  it "raises TypeError error if assigned to object that doesn't respond to #write" do
    obj = mock('object')
    lambda { $stdout = obj }.should raise_error(TypeError)

    obj.stub!(:write)
    $stdout = obj
    $stdout.should equal(obj)
  end
end

describe "Predefined global $!" do
  # See http://jira.codehaus.org/browse/JRUBY-5550
  it "remains nil after a failed core class \"checked\" coercion against a class that defines method_missing" do
    $!.should == nil

    obj = Class.new do
      def method_missing(*args)
        super
      end
    end.new

    [obj, 'foo'].join

    $!.should == nil
  end

  it "should be set to the value of $! before the begin after a successful rescue" do
    outer = StandardError.new 'outer'
    inner = StandardError.new 'inner'

    begin
      raise outer
    rescue
      $!.should == outer

      # nested rescue
      begin
        $!.should == outer
        raise inner
      rescue
        $!.should == inner
      ensure
        $!.should == outer
      end
      $!.should == outer
    end
    $!.should == nil
  end

  it "should be set to the value of $! before the begin after a rescue which returns" do
    def foo
      outer = StandardError.new 'outer'
      inner = StandardError.new 'inner'

      begin
        raise outer
      rescue
        $!.should == outer

        # nested rescue
        begin
          $!.should == outer
          raise inner
        rescue
          $!.should == inner
          return
        ensure
          $!.should == outer
        end
        $!.should == outer
      end
      $!.should == nil
    end
    foo
  end

  it "should be set to the value of $! before the begin after a successful rescue within an ensure" do
    outer = StandardError.new 'outer'
    inner = StandardError.new 'inner'

    begin
      begin
        raise outer
      ensure
        $!.should == outer

        # nested rescue
        begin
          $!.should == outer
          raise inner
        rescue
          $!.should == inner
        ensure
          $!.should == outer
        end
        $!.should == outer
      end
      flunk "outer should be raised after the ensure"
    rescue
      $!.should == outer
    end
    $!.should == nil
  end

  it "should be set to the new exception after a throwing rescue" do
    outer = StandardError.new 'outer'
    inner = StandardError.new 'inner'

    begin
      raise outer
    rescue
      $!.should == outer

      begin
        # nested rescue
        begin
          $!.should == outer
          raise inner
        rescue # the throwing rescue
          $!.should == inner
          raise inner
        ensure
          $!.should == inner
        end
      rescue # do not make the exception fail the example
        $!.should == inner
      end
      $!.should == outer
    end
    $!.should == nil
  end

  describe "in bodies without ensure" do
    it "should be cleared when an exception is rescued" do
      e = StandardError.new 'foo'
      begin
        raise e
      rescue
        $!.should == e
      end
      $!.should == nil
    end

    it "should be cleared when an exception is rescued even when a non-local return is present" do
      def foo(e)
        $!.should == e
        yield
      end
      def bar
        e = StandardError.new 'foo'
        begin
          raise e
        rescue
          $!.should == e
          foo(e) { return }
        end
      end

      bar
      $!.should == nil
    end

    it "should not be cleared when an exception is not rescued" do
      e = StandardError.new
      begin
        begin
          begin
            raise e
          rescue TypeError
            flunk
          end
        ensure
          $!.should == e
        end
      rescue
        $!.should == e
      end
      $!.should == nil
    end

    it "should not be cleared when an exception is rescued and rethrown" do
      e = StandardError.new 'foo'
      begin
        begin
          begin
            raise e
          rescue => e
            $!.should == e
            raise e
          end
        ensure
          $!.should == e
        end
      rescue
        $!.should == e
      end
      $!.should == nil
    end
  end

  describe "in ensure-protected bodies" do
    it "should be cleared when an exception is rescued" do
      e = StandardError.new 'foo'
      begin
        raise e
      rescue
        $!.should == e
      ensure
        $!.should == nil
      end
      $!.should == nil
    end

    it "should not be cleared when an exception is not rescued" do
      e = StandardError.new
      begin
        begin
          begin
            raise e
          rescue TypeError
            flunk
          ensure
            $!.should == e
          end
        ensure
          $!.should == e
        end
      rescue
        $!.should == e
      end
    end

    it "should not be cleared when an exception is rescued and rethrown" do
      e = StandardError.new
      begin
        begin
          begin
            raise e
          rescue => e
            $!.should == e
            raise e
          ensure
            $!.should == e
          end
        ensure
          $!.should == e
        end
      rescue
        $!.should == e
      end
    end
  end
end

=begin
Input/Output Variables
---------------------------------------------------------------------------------------------------

$/               String          The input record separator (newline by default). This is the value that rou-
                                 tines such as Kernel#gets use to determine record boundaries. If set to
                                 nil, gets will read the entire file.
$-0              String          Synonym for $/.
$\               String          The string appended to the output of every call to methods such as
                                 Kernel#print and IO#write. The default value is nil.
$,               String          The separator string output between the parameters to methods such as
                                 Kernel#print and Array#join. Defaults to nil, which adds no text.
$.               Fixnum          The number of the last line read from the current input file.
$;               String          The default separator pattern used by String#split. May be set from the
                                 command line using the -F flag.
$<               Object          An object that provides access to the concatenation of the contents of all
                                 the files given as command-line arguments or $stdin (in the case where
                                 there are no arguments). $< supports methods similar to a File object:
                                 binmode, close, closed?, each, each_byte, each_line, eof, eof?,
                                 file, filename, fileno, getc, gets, lineno, lineno=, path, pos, pos=,
                                 read, readchar, readline, readlines, rewind, seek, skip, tell, to_a,
                                 to_i, to_io, to_s, along with the methods in Enumerable. The method
                                 file returns a File object for the file currently being read. This may change
                                 as $< reads through the files on the command line. [r/o]
$>               IO              The destination of output for Kernel#print and Kernel#printf. The
                                 default value is $stdout.
$_               String          The last line read by Kernel#gets or Kernel#readline. Many string-
                                 related functions in the Kernel module operate on $_ by default. The vari-
                                 able is local to the current scope. [thread]
$-F              String          Synonym for $;.
$stderr          IO              The current standard error output.
$stdin           IO              The current standard input.
$stdout          IO              The current standard output. Assignment to $stdout is deprecated: use
                                 $stdout.reopen instead.
=end

describe "Predefined global $/" do
  before :each do
    @dollar_slash = $/
    @dollar_dash_zero = $-0
  end

  after :each do
    $/ = @dollar_slash
    $-0 = @dollar_dash_zero
  end

  it "can be assigned a String" do
    str = "abc"
    $/ = str
    $/.should equal(str)
  end

  it "can be assigned nil" do
    $/ = nil
    $/.should be_nil
  end

  it "returns the value assigned" do
    ($/ = "xyz").should == "xyz"
  end


  it "changes $-0" do
    $/ = "xyz"
    $-0.should equal($/)
  end

  it "does not call #to_str to convert the object to a String" do
    obj = mock("$/ value")
    obj.should_not_receive(:to_str)

    lambda { $/ = obj }.should raise_error(TypeError)
  end

  it "raises a TypeError if assigned a Fixnum" do
    lambda { $/ = 1 }.should raise_error(TypeError)
  end

  it "raises a TypeError if assigned a boolean" do
    lambda { $/ = true }.should raise_error(TypeError)
  end
end

describe "Predefined global $-0" do
  before :each do
    @dollar_slash = $/
    @dollar_dash_zero = $-0
  end

  after :each do
    $/ = @dollar_slash
    $-0 = @dollar_dash_zero
  end

  it "can be assigned a String" do
    str = "abc"
    $-0 = str
    $-0.should equal(str)
  end

  it "can be assigned nil" do
    $-0 = nil
    $-0.should be_nil
  end

  it "returns the value assigned" do
    ($-0 = "xyz").should == "xyz"
  end

  it "changes $/" do
    $-0 = "xyz"
    $/.should equal($-0)
  end

  it "does not call #to_str to convert the object to a String" do
    obj = mock("$-0 value")
    obj.should_not_receive(:to_str)

    lambda { $-0 = obj }.should raise_error(TypeError)
  end

  it "raises a TypeError if assigned a Fixnum" do
    lambda { $-0 = 1 }.should raise_error(TypeError)
  end

  it "raises a TypeError if assigned a boolean" do
    lambda { $-0 = true }.should raise_error(TypeError)
  end
end

describe "Predefined global $," do
  after :each do
    $, = nil
  end

  it "defaults to nil" do
    $,.should be_nil
  end

  it "raises TypeError if assigned a non-String" do
    lambda { $, = Object.new }.should raise_error(TypeError)
  end
end

describe "Predefined global $_" do
  it "is set to the last line read by e.g. StringIO#gets" do
    stdin = StringIO.new("foo\nbar\n", "r")

    read = stdin.gets
    read.should == "foo\n"
    $_.should == read

    read = stdin.gets
    read.should == "bar\n"
    $_.should == read

    read = stdin.gets
    read.should == nil
    $_.should == read
  end

  it "is set at the method-scoped level rather than block-scoped" do
    obj = Object.new
    def obj.foo; yield; end
    def obj.foo2; yield; end

    stdin = StringIO.new("foo\nbar\nbaz\nqux\n", "r")
    match = stdin.gets

    obj.foo { match = stdin.gets }

    match.should == "bar\n"
    $_.should == match

    eval 'match = stdin.gets'

    match.should == "baz\n"
    $_.should == match

    obj.foo2 { match = stdin.gets }

    match.should == "qux\n"
    $_.should == match
  end

  it "is Thread-local" do
    $_ = nil
    running = false

    thr = Thread.new do
      $_ = "last line"
      running = true
    end

    Thread.pass until running
    $_.should be_nil

    thr.join
  end

  it "can be assigned any value" do
    $_ = nil
    $_.should == nil
    $_ = "foo"
    $_.should == "foo"
    o = Object.new
    $_ = o
    $_.should == o
    $_ = 1
    $_.should == 1
  end
end

=begin
Execution Environment Variables
---------------------------------------------------------------------------------------------------

$0               String          The name of the top-level Ruby program being executed. Typically this will
                                 be the program’s filename. On some operating systems, assigning to this
                                 variable will change the name of the process reported (for example) by the
                                 ps(1) command.
$*               Array           An array of strings containing the command-line options from the invoca-
                                 tion of the program. Options used by the Ruby interpreter will have been
                                 removed. [r/o]
$"               Array           An array containing the filenames of modules loaded by require. [r/o]
$$               Fixnum          The process number of the program being executed. [r/o]
$?               Process::Status The exit status of the last child process to terminate. [r/o, thread]
$:               Array           An array of strings, where each string specifies a directory to be searched for
                                 Ruby scripts and binary extensions used by the load and require methods.
                                 The initial value is the value of the arguments passed via the -I command-
                                 line option, followed by an installation-defined standard library location, fol-
                                 lowed by the current directory (“.”). This variable may be set from within a
                                 program to alter the default search path; typically, programs use $: << dir
                                 to append dir to the path. [r/o]
$-a              Object          True if the -a option is specified on the command line. [r/o]
$-d              Object          Synonym for $DEBUG.
$DEBUG           Object          Set to true if the -d command-line option is specified.
__FILE__         String          The name of the current source file. [r/o]
$F               Array           The array that receives the split input line if the -a command-line option is
                                 used.
$FILENAME        String          The name of the current input file. Equivalent to $<.filename. [r/o]
$-i              String          If in-place edit mode is enabled (perhaps using the -i command-line
                                 option), $-i holds the extension used when creating the backup file. If you
                                 set a value into $-i, enables in-place edit mode.
$-I              Array           Synonym for $:. [r/o]
$-K              String          Sets the multibyte coding system for strings and regular expressions. Equiv-
                                 alent to the -K command-line option.
$-l              Object          Set to true if the -l option (which enables line-end processing) is present
                                 on the command line. [r/o]
__LINE__         String          The current line number in the source file. [r/o]
$LOAD_PATH       Array           A synonym for $:. [r/o]
$-p              Object          Set to true if the -p option (which puts an implicit while gets . . . end
                                 loop around your program) is present on the command line. [r/o]
$SAFE            Fixnum          The current safe level. This variable’s value may never be
                                 reduced by assignment. [thread] (Not implemented in Rubinius)
$VERBOSE         Object          Set to true if the -v, --version, -W, or -w option is specified on the com-
                                 mand line. Set to false if no option, or -W1 is given. Set to nil if -W0
                                 was specified. Setting this option to true causes the interpreter and some
                                 library routines to report additional information. Setting to nil suppresses
                                 all warnings (including the output of Kernel.warn).
$-v              Object          Synonym for $VERBOSE.
$-w              Object          Synonym for $VERBOSE.
=end
describe "Execution variable $:" do
  it "is initialized to an array of strings" do
    $:.is_a?(Array).should == true
    ($:.length > 0).should == true
  end

  it "does not include the current directory" do
    $:.should_not include(".")
  end

  it "is the same object as $LOAD_PATH and $-I" do
    $:.__id__.should == $LOAD_PATH.__id__
    $:.__id__.should == $-I.__id__
  end

  it "can be changed via <<" do
    $: << "foo"
    $:.should include("foo")
  end

  it "is read-only" do
    lambda {
      $: = []
    }.should raise_error(NameError)

    lambda {
      $LOAD_PATH = []
    }.should raise_error(NameError)

    lambda {
      $-I = []
    }.should raise_error(NameError)
  end
end

describe "Global variable $\"" do
  it "is an alias for $LOADED_FEATURES" do
    $".object_id.should == $LOADED_FEATURES.object_id
  end

  it "is read-only" do
    lambda {
      $" = []
    }.should raise_error(NameError)

    lambda {
      $LOADED_FEATURES = []
    }.should raise_error(NameError)
  end
end

describe "Global variable $<" do
  it "is read-only" do
    lambda {
      $< = nil
    }.should raise_error(NameError)
  end
end

describe "Global variable $FILENAME" do
  it "is read-only" do
    lambda {
      $FILENAME = "-"
    }.should raise_error(NameError)
  end
end

describe "Global variable $?" do
  it "is read-only" do
    lambda {
      $? = nil
    }.should raise_error(NameError)
  end

  it "is thread-local" do
    system(ruby_cmd('exit 0'))
    Thread.new { $?.should be_nil }.join
  end
end

describe "Global variable $-a" do
  it "is read-only" do
    lambda { $-a = true }.should raise_error(NameError)
  end
end

describe "Global variable $-l" do
  it "is read-only" do
    lambda { $-l = true }.should raise_error(NameError)
  end
end

describe "Global variable $-p" do
  it "is read-only" do
    lambda { $-p = true }.should raise_error(NameError)
  end
end

describe "Global variable $-d" do
  before :each do
    @debug = $DEBUG
  end

  after :each do
    $DEBUG = @debug
  end

  it "is an alias of $DEBUG" do
    $DEBUG = true
    $-d.should be_true
    $-d = false
    $DEBUG.should be_false
  end
end

describe :verbose_global_alias, shared: true do
  before :each do
    @verbose = $VERBOSE
  end

  after :each do
    $VERBOSE = @verbose
  end

  it "is an alias of $VERBOSE" do
    $VERBOSE = true
    eval(@method).should be_true
    eval("#{@method} = false")
    $VERBOSE.should be_false
  end
end

describe "Global variable $-v" do
  it_behaves_like :verbose_global_alias, '$-v'
end

describe "Global variable $-w" do
  it_behaves_like :verbose_global_alias, '$-w'
end

describe "Global variable $0" do
  before :each do
    @orig_program_name = $0
  end

  after :each do
    $0 = @orig_program_name
  end

  it "is the path given as the main script and the same as __FILE__" do
    script = "fixtures/dollar_zero.rb"
    Dir.chdir(File.dirname(__FILE__)) do
      ruby_exe(script).should == "#{script}\n#{script}\nOK"
    end
  end

  it "returns the program name" do
    $0 = "rbx"
    $0.should == "rbx"
  end

  platform_is :linux, :darwin do
    it "actually sets the program name" do
      title = "rubyspec-dollar0-test"
      $0 = title
      `ps -ocommand= -p#{$$}`.should include(title)
    end
  end

  it "returns the given value when set" do
    ($0 = "rbx").should == "rbx"
  end

  it "raises a TypeError when not given an object that can be coerced to a String" do
    lambda { $0 = nil }.should raise_error(TypeError)
  end
end

=begin
Standard Objects
---------------------------------------------------------------------------------------------------

ARGF             Object          A synonym for $<.
ARGV             Array           A synonym for $*.
ENV              Object          A hash-like object containing the program’s environment variables. An
                                 instance of class Object, ENV implements the full set of Hash methods. Used
                                 to query and set the value of an environment variable, as in ENV["PATH"]
                                 and ENV["term"]="ansi".
false            FalseClass      Singleton instance of class FalseClass. [r/o]
nil              NilClass        The singleton instance of class NilClass. The value of uninitialized
                                 instance and global variables. [r/o]
self             Object          The receiver (object) of the current method. [r/o]
true             TrueClass       Singleton instance of class TrueClass. [r/o]
=end

describe "The predefined standard objects" do
  it "includes ARGF" do
    Object.const_defined?(:ARGF).should == true
  end

  it "includes ARGV" do
    Object.const_defined?(:ARGV).should == true
  end

  it "includes a hash-like object ENV" do
    Object.const_defined?(:ENV).should == true
    ENV.respond_to?(:[]).should == true
  end
end

describe "The predefined standard object nil" do
  it "is an instance of NilClass" do
    nil.should be_kind_of(NilClass)
  end

  it "raises a SyntaxError if assigned to" do
    lambda { eval("nil = true") }.should raise_error(SyntaxError)
  end
end

describe "The predefined standard object true" do
  it "is an instance of TrueClass" do
    true.should be_kind_of(TrueClass)
  end

  it "raises a SyntaxError if assigned to" do
    lambda { eval("true = false") }.should raise_error(SyntaxError)
  end
end

describe "The predefined standard object false" do
  it "is an instance of FalseClass" do
    false.should be_kind_of(FalseClass)
  end

  it "raises a SyntaxError if assigned to" do
    lambda { eval("false = nil") }.should raise_error(SyntaxError)
  end
end

describe "The self pseudo-variable" do
  it "raises a SyntaxError if assigned to" do
    lambda { eval("self = 1") }.should raise_error(SyntaxError)
  end
end

=begin
Global Constants
---------------------------------------------------------------------------------------------------

The following constants are defined by the Ruby interpreter.

DATA                 IO          If the main program file contains the directive __END__, then
                                 the constant DATA will be initialized so that reading from it will
                                 return lines following __END__ from the source file.
FALSE                FalseClass  Synonym for false.
NIL                  NilClass    Synonym for nil.
RUBY_PLATFORM        String      The identifier of the platform running this program. This string
                                 is in the same form as the platform identifier used by the GNU
                                 configure utility (which is not a coincidence).
RUBY_RELEASE_DATE    String      The date of this release.
RUBY_VERSION         String      The version number of the interpreter.
STDERR               IO          The actual standard error stream for the program. The initial
                                 value of $stderr.
STDIN                IO          The actual standard input stream for the program. The initial
                                 value of $stdin.
STDOUT               IO          The actual standard output stream for the program. The initial
                                 value of $stdout.
SCRIPT_LINES__       Hash        If a constant SCRIPT_LINES__ is defined and references a Hash,
                                 Ruby will store an entry containing the contents of each file it
                                 parses, with the file’s name as the key and an array of strings as
                                 the value.
TOPLEVEL_BINDING     Binding     A Binding object representing the binding at Ruby’s top level—
                                 the level where programs are initially executed.
TRUE                 TrueClass   Synonym for true.
=end

describe "The predefined global constants" do
  ruby_version_is ""..."2.4" do
    it "includes TRUE" do
      Object.const_defined?(:TRUE).should == true
      TRUE.should equal(true)
    end

    it "includes FALSE" do
      Object.const_defined?(:FALSE).should == true
      FALSE.should equal(false)
    end

    it "includes NIL" do
      Object.const_defined?(:NIL).should == true
      NIL.should equal(nil)
    end
  end

  ruby_version_is "2.4" do
    it "includes TRUE" do
      Object.const_defined?(:TRUE).should == true
      -> {
        TRUE.should equal(true)
      }.should complain(/constant ::TRUE is deprecated/)
    end

    it "includes FALSE" do
      Object.const_defined?(:FALSE).should == true
      -> {
        FALSE.should equal(false)
      }.should complain(/constant ::FALSE is deprecated/)
    end

    it "includes NIL" do
      Object.const_defined?(:NIL).should == true
      -> {
        NIL.should equal(nil)
      }.should complain(/constant ::NIL is deprecated/)
    end
  end

  it "includes STDIN" do
    Object.const_defined?(:STDIN).should == true
  end

  it "includes STDOUT" do
    Object.const_defined?(:STDOUT).should == true
  end

  it "includes STDERR" do
    Object.const_defined?(:STDERR).should == true
  end

  it "includes RUBY_VERSION" do
    Object.const_defined?(:RUBY_VERSION).should == true
  end

  it "includes RUBY_RELEASE_DATE" do
    Object.const_defined?(:RUBY_RELEASE_DATE).should == true
  end

  it "includes RUBY_PLATFORM" do
    Object.const_defined?(:RUBY_PLATFORM).should == true
  end

  it "includes TOPLEVEL_BINDING" do
    Object.const_defined?(:TOPLEVEL_BINDING).should == true
  end

end

with_feature :encoding do
  describe "The predefined global constant" do
    before :each do
      @external = Encoding.default_external
      @internal = Encoding.default_internal
    end

    after :each do
      Encoding.default_external = @external
      Encoding.default_internal = @internal
    end

    describe "STDIN" do
      it "has the same external encoding as Encoding.default_external" do
        STDIN.external_encoding.should equal(Encoding.default_external)
      end

      it "has the same external encoding as Encoding.default_external when that encoding is changed" do
        Encoding.default_external = Encoding::ISO_8859_16
        STDIN.external_encoding.should equal(Encoding::ISO_8859_16)
      end

      it "has the encodings set by #set_encoding" do
        code = "STDIN.set_encoding Encoding::IBM775, Encoding::IBM866; " \
               "p [STDIN.external_encoding.name, STDIN.internal_encoding.name]"
        ruby_exe(code).chomp.should == %{["IBM775", "IBM866"]}
      end

      it "retains the encoding set by #set_encoding when Encoding.default_external is changed" do
        code = "STDIN.set_encoding Encoding::IBM775, Encoding::IBM866; " \
               "Encoding.default_external = Encoding::ISO_8859_16;" \
               "p [STDIN.external_encoding.name, STDIN.internal_encoding.name]"
        ruby_exe(code).chomp.should == %{["IBM775", "IBM866"]}
      end

      it "has nil for the internal encoding" do
        STDIN.internal_encoding.should be_nil
      end

      it "has nil for the internal encoding despite Encoding.default_internal being changed" do
        Encoding.default_internal = Encoding::IBM437
        STDIN.internal_encoding.should be_nil
      end
    end

    describe "STDOUT" do
      it "has nil for the external encoding" do
        STDOUT.external_encoding.should be_nil
      end

      it "has nil for the external encoding despite Encoding.default_external being changed" do
        Encoding.default_external = Encoding::ISO_8859_1
        STDOUT.external_encoding.should be_nil
      end

      it "has the encodings set by #set_encoding" do
        code = "STDOUT.set_encoding Encoding::IBM775, Encoding::IBM866; " \
               "p [STDOUT.external_encoding.name, STDOUT.internal_encoding.name]"
        ruby_exe(code).chomp.should == %{["IBM775", "IBM866"]}
      end

      it "has nil for the internal encoding" do
        STDOUT.internal_encoding.should be_nil
      end

      it "has nil for the internal encoding despite Encoding.default_internal being changed" do
        Encoding.default_internal = Encoding::IBM437
        STDOUT.internal_encoding.should be_nil
      end
    end

    describe "STDERR" do
      it "has nil for the external encoding" do
        STDERR.external_encoding.should be_nil
      end

      it "has nil for the external encoding despite Encoding.default_external being changed" do
        Encoding.default_external = Encoding::ISO_8859_1
        STDERR.external_encoding.should be_nil
      end

      it "has the encodings set by #set_encoding" do
        code = "STDERR.set_encoding Encoding::IBM775, Encoding::IBM866; " \
               "p [STDERR.external_encoding.name, STDERR.internal_encoding.name]"
        ruby_exe(code).chomp.should == %{["IBM775", "IBM866"]}
      end

      it "has nil for the internal encoding" do
        STDERR.internal_encoding.should be_nil
      end

      it "has nil for the internal encoding despite Encoding.default_internal being changed" do
        Encoding.default_internal = Encoding::IBM437
        STDERR.internal_encoding.should be_nil
      end
    end

    describe "ARGV" do
      it "contains Strings encoded in locale Encoding" do
        code = fixture __FILE__, "argv_encoding.rb"
        result = ruby_exe(code, args: "a b")
        encoding = Encoding.default_external
        result.chomp.should == %{["#{encoding}", "#{encoding}"]}
      end
    end
  end
end
