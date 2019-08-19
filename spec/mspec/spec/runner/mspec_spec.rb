require 'spec_helper'
require 'mspec/helpers/tmp'
require 'mspec/helpers/fs'
require 'mspec/matchers/base'
require 'mspec/runner/mspec'
require 'mspec/runner/example'

describe MSpec, ".register_files" do
  it "records which spec files to run" do
    MSpec.register_files [:one, :two, :three]
    MSpec.retrieve(:files).should == [:one, :two, :three]
  end
end

describe MSpec, ".register_mode" do
  before :each do
    MSpec.clear_modes
  end

  it "sets execution mode flags" do
    MSpec.register_mode :verify
    MSpec.retrieve(:modes).should == [:verify]
  end
end

describe MSpec, ".register_tags_patterns" do
  it "records the patterns for generating a tag file from a spec file" do
    MSpec.register_tags_patterns [[/spec\/ruby/, "spec/tags"], [/frozen/, "ruby"]]
    MSpec.retrieve(:tags_patterns).should == [[/spec\/ruby/, "spec/tags"], [/frozen/, "ruby"]]
  end
end

describe MSpec, ".register_exit" do
  before :each do
    MSpec.store :exit, 0
  end

  it "records the exit code" do
    MSpec.exit_code.should == 0
    MSpec.register_exit 1
    MSpec.exit_code.should == 1
  end
end

describe MSpec, ".exit_code" do
  it "retrieves the code set with .register_exit" do
    MSpec.register_exit 99
    MSpec.exit_code.should == 99
  end
end

describe MSpec, ".store" do
  it "records data for MSpec settings" do
    MSpec.store :anything, :value
    MSpec.retrieve(:anything).should == :value
  end
end

describe MSpec, ".retrieve" do
  it "accesses .store'd data" do
    MSpec.register :retrieve, :first
    MSpec.retrieve(:retrieve).should == [:first]
  end
end

describe MSpec, ".randomize" do
  it "sets the flag to randomize spec execution order" do
    MSpec.randomize?.should == false
    MSpec.randomize
    MSpec.randomize?.should == true
    MSpec.randomize false
    MSpec.randomize?.should == false
  end
end

describe MSpec, ".register" do
  it "is the gateway behind the register(symbol, action) facility" do
    MSpec.register :bonus, :first
    MSpec.register :bonus, :second
    MSpec.register :bonus, :second
    MSpec.retrieve(:bonus).should == [:first, :second]
  end
end

describe MSpec, ".unregister" do
  it "is the gateway behind the unregister(symbol, actions) facility" do
    MSpec.register :unregister, :first
    MSpec.register :unregister, :second
    MSpec.unregister :unregister, :second
    MSpec.retrieve(:unregister).should == [:first]
  end
end

describe MSpec, ".protect" do
  before :each do
    MSpec.clear_current
    @cs = ContextState.new "C#m"
    @cs.parent = MSpec.current

    @es = ExampleState.new @cs, "runs"
    ScratchPad.record Exception.new("Sharp!")
  end

  it "returns true if no exception is raised" do
    MSpec.protect("passed") { 1 }.should be_true
  end

  it "returns false if an exception is raised" do
    MSpec.protect("testing") { raise ScratchPad.recorded }.should be_false
  end

  it "rescues any exceptions raised when evaluating the block argument" do
    MSpec.protect("") { raise Exception, "Now you see me..." }
  end

  it "does not rescue SystemExit" do
    begin
      MSpec.protect("") { exit 1 }
    rescue SystemExit
      ScratchPad.record :system_exit
    end
    ScratchPad.recorded.should == :system_exit
  end

  it "calls all the exception actions" do
    exc = ExceptionState.new @es, "testing", ScratchPad.recorded
    ExceptionState.stub(:new).and_return(exc)
    action = double("exception")
    action.should_receive(:exception).with(exc)
    MSpec.register :exception, action
    MSpec.protect("testing") { raise ScratchPad.recorded }
    MSpec.unregister :exception, action
  end

  it "registers a non-zero exit code when an exception is raised" do
    MSpec.should_receive(:register_exit).with(1)
    MSpec.protect("testing") { raise ScratchPad.recorded }
  end
end

describe MSpec, ".register_current" do
  before :each do
    MSpec.clear_current
  end

  it "sets the value returned by MSpec.current" do
    MSpec.current.should be_nil
    MSpec.register_current :a
    MSpec.current.should == :a
  end
end

describe MSpec, ".clear_current" do
  it "sets the value returned by MSpec.current to nil" do
    MSpec.register_current :a
    MSpec.current.should_not be_nil
    MSpec.clear_current
    MSpec.current.should be_nil
  end
end

describe MSpec, ".current" do
  before :each do
    MSpec.clear_current
  end

  it "returns nil if no ContextState has been registered" do
    MSpec.current.should be_nil
  end

  it "returns the most recently registered ContextState" do
    first = ContextState.new ""
    second = ContextState.new ""
    MSpec.register_current first
    MSpec.current.should == first
    MSpec.register_current second
    MSpec.current.should == second
  end
end

describe MSpec, ".actions" do
  before :each do
    MSpec.store :start, []
    ScratchPad.record []
    start_one = double("one")
    start_one.stub(:start).and_return { ScratchPad << :one }
    start_two = double("two")
    start_two.stub(:start).and_return { ScratchPad << :two }
    MSpec.register :start, start_one
    MSpec.register :start, start_two
  end

  it "does not attempt to run any actions if none have been registered" do
    MSpec.store :finish, nil
    lambda { MSpec.actions :finish }.should_not raise_error
  end

  it "runs each action registered as a start action" do
    MSpec.actions :start
    ScratchPad.recorded.should == [:one, :two]
  end
end

describe MSpec, ".mode?" do
  before :each do
    MSpec.clear_modes
  end

  it "returns true if the mode has been set" do
    MSpec.mode?(:verify).should == false
    MSpec.register_mode :verify
    MSpec.mode?(:verify).should == true
  end
end

describe MSpec, ".clear_modes" do
  it "clears all registered modes" do
    MSpec.register_mode(:pretend)
    MSpec.register_mode(:verify)

    MSpec.mode?(:pretend).should == true
    MSpec.mode?(:verify).should == true

    MSpec.clear_modes

    MSpec.mode?(:pretend).should == false
    MSpec.mode?(:verify).should == false
  end
end

describe MSpec, ".guarded?" do
  before :each do
    MSpec.instance_variable_set :@guarded, []
  end

  it "returns false if no guard has run" do
    MSpec.guarded?.should == false
  end

  it "returns true if a single guard has run" do
    MSpec.guard
    MSpec.guarded?.should == true
  end

  it "returns true if more than one guard has run" do
    MSpec.guard
    MSpec.guard
    MSpec.guarded?.should == true
  end

  it "returns true until all guards have finished" do
    MSpec.guard
    MSpec.guard
    MSpec.guarded?.should == true
    MSpec.unguard
    MSpec.guarded?.should == true
    MSpec.unguard
    MSpec.guarded?.should == false
  end
end

describe MSpec, ".describe" do
  before :each do
    MSpec.clear_current
    @cs = ContextState.new ""
    ContextState.stub(:new).and_return(@cs)
    MSpec.stub(:current).and_return(nil)
    MSpec.stub(:register_current)
  end

  it "creates a new ContextState for the block" do
    ContextState.should_receive(:new).and_return(@cs)
    MSpec.describe(Object) { }
  end

  it "accepts an optional second argument" do
    ContextState.should_receive(:new).and_return(@cs)
    MSpec.describe(Object, "msg") { }
  end

  it "registers the newly created ContextState" do
    MSpec.should_receive(:register_current).with(@cs).twice
    MSpec.describe(Object) { }
  end

  it "invokes the ContextState#describe method" do
    prc = lambda { }
    @cs.should_receive(:describe).with(&prc)
    MSpec.describe(Object, "msg", &prc)
  end
end

describe MSpec, ".process" do
  before :each do
    MSpec.stub(:files)
    MSpec.store :start, []
    MSpec.store :finish, []
    STDOUT.stub(:puts)
  end

  it "prints the RUBY_DESCRIPTION" do
    STDOUT.should_receive(:puts).with(RUBY_DESCRIPTION)
    MSpec.process
  end

  it "calls all start actions" do
    start = double("start")
    start.stub(:start).and_return { ScratchPad.record :start }
    MSpec.register :start, start
    MSpec.process
    ScratchPad.recorded.should == :start
  end

  it "calls all finish actions" do
    finish = double("finish")
    finish.stub(:finish).and_return { ScratchPad.record :finish }
    MSpec.register :finish, finish
    MSpec.process
    ScratchPad.recorded.should == :finish
  end

  it "calls the files method" do
    MSpec.should_receive(:files)
    MSpec.process
  end
end

describe MSpec, ".files" do
  before :each do
    MSpec.store :load, []
    MSpec.store :unload, []
    MSpec.register_files [:one, :two, :three]
    Kernel.stub(:load)
  end

  it "calls load actions before each file" do
    load = double("load")
    load.stub(:load).and_return { ScratchPad.record :load }
    MSpec.register :load, load
    MSpec.files
    ScratchPad.recorded.should == :load
  end

  it "shuffles the file list if .randomize? is true" do
    MSpec.randomize
    MSpec.should_receive(:shuffle)
    MSpec.files
    MSpec.randomize false
  end

  it "registers the current file" do
    MSpec.should_receive(:store).with(:file, :one)
    MSpec.should_receive(:store).with(:file, :two)
    MSpec.should_receive(:store).with(:file, :three)
    MSpec.files
  end
end

describe MSpec, ".shuffle" do
  before :each do
    @base = (0..100).to_a
    @list = @base.clone
    MSpec.shuffle @list
  end

  it "does not alter the elements in the list" do
    @base.each do |elt|
      @list.should include(elt)
    end
  end

  it "changes the order of the list" do
    # obviously, this spec has a certain probability
    # of failing. If it fails, run it again.
    @list.should_not == @base
  end
end

describe MSpec, ".tags_file" do
  before :each do
    MSpec.store :file, "path/to/spec/something/some_spec.rb"
    MSpec.store :tags_patterns, nil
  end

  it "returns the default tags file for the current spec file" do
    MSpec.tags_file.should == "path/to/spec/tags/something/some_tags.txt"
  end

  it "returns the tags file for the current spec file with custom tags_patterns" do
    MSpec.register_tags_patterns [[/^(.*)\/spec/, '\1/tags'], [/_spec.rb/, "_tags.txt"]]
    MSpec.tags_file.should == "path/to/tags/something/some_tags.txt"
  end

  it "performs multiple substitutions" do
    MSpec.register_tags_patterns [
      [%r(/spec/something/), "/spec/other/"],
      [%r(/spec/), "/spec/tags/"],
      [/_spec.rb/, "_tags.txt"]
    ]
    MSpec.tags_file.should == "path/to/spec/tags/other/some_tags.txt"
  end

  it "handles cases where no substitution is performed" do
    MSpec.register_tags_patterns [[/nothing/, "something"]]
    MSpec.tags_file.should == "path/to/spec/something/some_spec.rb"
  end
end

describe MSpec, ".read_tags" do
  before :each do
    MSpec.stub(:tags_file).and_return(File.dirname(__FILE__) + '/tags.txt')
  end

  it "returns a list of tag instances for matching tag names found" do
    one = SpecTag.new "fail(broken):Some#method? works"
    MSpec.read_tags(["fail", "pass"]).should == [one]
  end

  it "returns [] if no tags names match" do
    MSpec.read_tags("super").should == []
  end
end

describe MSpec, ".read_tags" do
  before :each do
    @tag = SpecTag.new "fails:Some#method"
    File.open(tmp("tags.txt", false), "w") do |f|
      f.puts ""
      f.puts @tag
      f.puts ""
    end
    MSpec.stub(:tags_file).and_return(tmp("tags.txt", false))
  end

  it "does not return a tag object for empty lines" do
    MSpec.read_tags(["fails"]).should == [@tag]
  end
end

describe MSpec, ".write_tags" do
  before :each do
    FileUtils.cp File.dirname(__FILE__) + "/tags.txt", tmp("tags.txt", false)
    MSpec.stub(:tags_file).and_return(tmp("tags.txt", false))
    @tag1 = SpecTag.new "check(broken):Tag#rewrite works"
    @tag2 = SpecTag.new "broken:Tag#write_tags fails"
  end

  after :all do
    rm_r tmp("tags.txt", false)
  end

  it "overwrites the tags in the tag file" do
    IO.read(tmp("tags.txt", false)).should == %[fail(broken):Some#method? works
incomplete(20%):The#best method ever
benchmark(0.01825):The#fastest method today
extended():\"Multi-line\\ntext\\ntag\"
]
    MSpec.write_tags [@tag1, @tag2]
    IO.read(tmp("tags.txt", false)).should == %[check(broken):Tag#rewrite works
broken:Tag#write_tags fails
]
  end
end

describe MSpec, ".write_tag" do
  before :each do
    FileUtils.stub(:mkdir_p)
    MSpec.stub(:tags_file).and_return(tmp("tags.txt", false))
    @tag = SpecTag.new "fail(broken):Some#method works"
  end

  after :all do
    rm_r tmp("tags.txt", false)
  end

  it "writes a tag to the tags file for the current spec file" do
    MSpec.write_tag @tag
    IO.read(tmp("tags.txt", false)).should == "fail(broken):Some#method works\n"
  end

  it "does not write a duplicate tag" do
    File.open(tmp("tags.txt", false), "w") { |f| f.puts @tag }
    MSpec.write_tag @tag
    IO.read(tmp("tags.txt", false)).should == "fail(broken):Some#method works\n"
  end
end

describe MSpec, ".delete_tag" do
  before :each do
    FileUtils.cp File.dirname(__FILE__) + "/tags.txt", tmp("tags.txt", false)
    MSpec.stub(:tags_file).and_return(tmp("tags.txt", false))
    @tag = SpecTag.new "fail(Comments don't matter):Some#method? works"
  end

  after :each do
    rm_r tmp("tags.txt", false)
  end

  it "deletes the tag if it exists" do
    MSpec.delete_tag(@tag).should == true
    IO.read(tmp("tags.txt", false)).should == %[incomplete(20%):The#best method ever
benchmark(0.01825):The#fastest method today
extended():\"Multi-line\\ntext\\ntag\"
]
  end

  it "deletes a tag with escaped newlines" do
    MSpec.delete_tag(SpecTag.new('extended:"Multi-line\ntext\ntag"')).should == true
    IO.read(tmp("tags.txt", false)).should == %[fail(broken):Some#method? works
incomplete(20%):The#best method ever
benchmark(0.01825):The#fastest method today
]
  end

  it "does not change the tags file contents if the tag doesn't exist" do
    @tag.tag = "failed"
    MSpec.delete_tag(@tag).should == false
    IO.read(tmp("tags.txt", false)).should == %[fail(broken):Some#method? works
incomplete(20%):The#best method ever
benchmark(0.01825):The#fastest method today
extended():\"Multi-line\\ntext\\ntag\"
]
  end

  it "deletes the tag file if it is empty" do
    MSpec.delete_tag(@tag).should == true
    MSpec.delete_tag(SpecTag.new("incomplete:The#best method ever")).should == true
    MSpec.delete_tag(SpecTag.new("benchmark:The#fastest method today")).should == true
    MSpec.delete_tag(SpecTag.new('extended:"Multi-line\ntext\ntag"')).should == true
    File.exist?(tmp("tags.txt", false)).should == false
  end
end

describe MSpec, ".delete_tags" do
  before :each do
    @tags = tmp("tags.txt", false)
    FileUtils.cp File.dirname(__FILE__) + "/tags.txt", @tags
    MSpec.stub(:tags_file).and_return(@tags)
  end

  it "deletes the tag file" do
    MSpec.delete_tags
    File.exist?(@tags).should be_false
  end
end

describe MSpec, ".expectation" do
  it "sets the flag that an expectation has been reported" do
    MSpec.clear_expectations
    MSpec.expectation?.should be_false
    MSpec.expectation
    MSpec.expectation?.should be_true
  end
end

describe MSpec, ".expectation?" do
  it "returns true if an expectation has been reported" do
    MSpec.expectation
    MSpec.expectation?.should be_true
  end

  it "returns false if an expectation has not been reported" do
    MSpec.clear_expectations
    MSpec.expectation?.should be_false
  end
end

describe MSpec, ".clear_expectations" do
  it "clears the flag that an expectation has been reported" do
    MSpec.expectation
    MSpec.expectation?.should be_true
    MSpec.clear_expectations
    MSpec.expectation?.should be_false
  end
end

describe MSpec, ".register_shared" do
  it "stores a shared ContextState by description" do
    parent = ContextState.new "container"
    state = ContextState.new "shared"
    state.parent = parent
    prc = lambda { }
    state.describe(&prc)
    MSpec.register_shared(state)
    MSpec.retrieve(:shared)["shared"].should == state
  end
end

describe MSpec, ".retrieve_shared" do
  it "retrieves the shared ContextState matching description" do
    state = ContextState.new ""
    MSpec.retrieve(:shared)["shared"] = state
    MSpec.retrieve_shared(:shared).should == state
  end
end
