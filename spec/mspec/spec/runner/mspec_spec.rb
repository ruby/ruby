require 'spec_helper'
require 'mspec/expectations/expectations'
require 'mspec/helpers/tmp'
require 'mspec/helpers/fs'
require 'mspec/matchers/base'
require 'mspec/runner/mspec'
require 'mspec/runner/example'

RSpec.describe MSpec, ".register_files" do
  it "records which spec files to run" do
    MSpec.register_files [:one, :two, :three]
    expect(MSpec.files_array).to eq([:one, :two, :three])
  end
end

RSpec.describe MSpec, ".register_mode" do
  before :each do
    MSpec.clear_modes
  end

  it "sets execution mode flags" do
    MSpec.register_mode :verify
    expect(MSpec.retrieve(:modes)).to eq([:verify])
  end
end

RSpec.describe MSpec, ".register_tags_patterns" do
  it "records the patterns for generating a tag file from a spec file" do
    MSpec.register_tags_patterns [[/spec\/ruby/, "spec/tags"], [/frozen/, "ruby"]]
    expect(MSpec.retrieve(:tags_patterns)).to eq([[/spec\/ruby/, "spec/tags"], [/frozen/, "ruby"]])
  end
end

RSpec.describe MSpec, ".register_exit" do
  before :each do
    MSpec.store :exit, 0
  end

  it "records the exit code" do
    expect(MSpec.exit_code).to eq(0)
    MSpec.register_exit 1
    expect(MSpec.exit_code).to eq(1)
  end
end

RSpec.describe MSpec, ".exit_code" do
  it "retrieves the code set with .register_exit" do
    MSpec.register_exit 99
    expect(MSpec.exit_code).to eq(99)
  end
end

RSpec.describe MSpec, ".store" do
  it "records data for MSpec settings" do
    MSpec.store :anything, :value
    expect(MSpec.retrieve(:anything)).to eq(:value)
  end
end

RSpec.describe MSpec, ".retrieve" do
  it "accesses .store'd data" do
    MSpec.register :retrieve, :first
    expect(MSpec.retrieve(:retrieve)).to eq([:first])
  end
end

RSpec.describe MSpec, ".randomize" do
  it "sets the flag to randomize spec execution order" do
    expect(MSpec.randomize?).to eq(false)
    MSpec.randomize = true
    expect(MSpec.randomize?).to eq(true)
    MSpec.randomize = false
    expect(MSpec.randomize?).to eq(false)
  end
end

RSpec.describe MSpec, ".register" do
  it "is the gateway behind the register(symbol, action) facility" do
    MSpec.register :bonus, :first
    MSpec.register :bonus, :second
    MSpec.register :bonus, :second
    expect(MSpec.retrieve(:bonus)).to eq([:first, :second])
  end
end

RSpec.describe MSpec, ".unregister" do
  it "is the gateway behind the unregister(symbol, actions) facility" do
    MSpec.register :unregister, :first
    MSpec.register :unregister, :second
    MSpec.unregister :unregister, :second
    expect(MSpec.retrieve(:unregister)).to eq([:first])
  end
end

RSpec.describe MSpec, ".protect" do
  before :each do
    MSpec.clear_current
    @cs = ContextState.new "C#m"
    @cs.parent = MSpec.current

    @es = ExampleState.new @cs, "runs"
    ScratchPad.record Exception.new("Sharp!")
  end

  it "returns true if no exception is raised" do
    expect(MSpec.protect("passed") { 1 }).to be_truthy
  end

  it "returns false if an exception is raised" do
    expect(MSpec.protect("testing") { raise ScratchPad.recorded }).to be_falsey
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
    expect(ScratchPad.recorded).to eq(:system_exit)
  end

  it "calls all the exception actions" do
    exc = ExceptionState.new @es, "testing", ScratchPad.recorded
    allow(ExceptionState).to receive(:new).and_return(exc)
    action = double("exception")
    expect(action).to receive(:exception).with(exc)
    MSpec.register :exception, action
    MSpec.protect("testing") { raise ScratchPad.recorded }
    MSpec.unregister :exception, action
  end

  it "registers a non-zero exit code when an exception is raised" do
    expect(MSpec).to receive(:register_exit).with(1)
    MSpec.protect("testing") { raise ScratchPad.recorded }
  end
end

RSpec.describe MSpec, ".register_current" do
  before :each do
    MSpec.clear_current
  end

  it "sets the value returned by MSpec.current" do
    expect(MSpec.current).to be_nil
    MSpec.register_current :a
    expect(MSpec.current).to eq(:a)
  end
end

RSpec.describe MSpec, ".clear_current" do
  it "sets the value returned by MSpec.current to nil" do
    MSpec.register_current :a
    expect(MSpec.current).not_to be_nil
    MSpec.clear_current
    expect(MSpec.current).to be_nil
  end
end

RSpec.describe MSpec, ".current" do
  before :each do
    MSpec.clear_current
  end

  it "returns nil if no ContextState has been registered" do
    expect(MSpec.current).to be_nil
  end

  it "returns the most recently registered ContextState" do
    first = ContextState.new ""
    second = ContextState.new ""
    MSpec.register_current first
    expect(MSpec.current).to eq(first)
    MSpec.register_current second
    expect(MSpec.current).to eq(second)
  end
end

RSpec.describe MSpec, ".actions" do
  before :each do
    MSpec.store :start, []
    ScratchPad.record []
    start_one = double("one")
    allow(start_one).to receive(:start) { ScratchPad << :one }
    start_two = double("two")
    allow(start_two).to receive(:start) { ScratchPad << :two }
    MSpec.register :start, start_one
    MSpec.register :start, start_two
  end

  it "does not attempt to run any actions if none have been registered" do
    MSpec.store :finish, nil
    expect { MSpec.actions :finish }.not_to raise_error
  end

  it "runs each action registered as a start action" do
    MSpec.actions :start
    expect(ScratchPad.recorded).to eq([:one, :two])
  end
end

RSpec.describe MSpec, ".mode?" do
  before :each do
    MSpec.clear_modes
  end

  it "returns true if the mode has been set" do
    expect(MSpec.mode?(:verify)).to eq(false)
    MSpec.register_mode :verify
    expect(MSpec.mode?(:verify)).to eq(true)
  end
end

RSpec.describe MSpec, ".clear_modes" do
  it "clears all registered modes" do
    MSpec.register_mode(:pretend)
    MSpec.register_mode(:verify)

    expect(MSpec.mode?(:pretend)).to eq(true)
    expect(MSpec.mode?(:verify)).to eq(true)

    MSpec.clear_modes

    expect(MSpec.mode?(:pretend)).to eq(false)
    expect(MSpec.mode?(:verify)).to eq(false)
  end
end

RSpec.describe MSpec, ".guarded?" do
  before :each do
    MSpec.instance_variable_set :@guarded, []
  end

  it "returns false if no guard has run" do
    expect(MSpec.guarded?).to eq(false)
  end

  it "returns true if a single guard has run" do
    MSpec.guard
    expect(MSpec.guarded?).to eq(true)
  end

  it "returns true if more than one guard has run" do
    MSpec.guard
    MSpec.guard
    expect(MSpec.guarded?).to eq(true)
  end

  it "returns true until all guards have finished" do
    MSpec.guard
    MSpec.guard
    expect(MSpec.guarded?).to eq(true)
    MSpec.unguard
    expect(MSpec.guarded?).to eq(true)
    MSpec.unguard
    expect(MSpec.guarded?).to eq(false)
  end
end

RSpec.describe MSpec, ".describe" do
  before :each do
    MSpec.clear_current
    @cs = ContextState.new ""
    allow(ContextState).to receive(:new).and_return(@cs)
    allow(MSpec).to receive(:current).and_return(nil)
    allow(MSpec).to receive(:register_current)
  end

  it "creates a new ContextState for the block" do
    expect(ContextState).to receive(:new).and_return(@cs)
    MSpec.describe(Object) { }
  end

  it "accepts an optional second argument" do
    expect(ContextState).to receive(:new).and_return(@cs)
    MSpec.describe(Object, "msg") { }
  end

  it "registers the newly created ContextState" do
    expect(MSpec).to receive(:register_current).with(@cs).twice
    MSpec.describe(Object) { }
  end

  it "invokes the ContextState#describe method" do
    expect(@cs).to receive(:describe)
    MSpec.describe(Object, "msg") {}
  end
end

RSpec.describe MSpec, ".process" do
  before :each do
    allow(MSpec).to receive(:files)
    MSpec.store :start, []
    MSpec.store :finish, []
    allow(STDOUT).to receive(:puts)
  end

  it "prints the RUBY_DESCRIPTION" do
    expect(STDOUT).to receive(:puts).with(RUBY_DESCRIPTION)
    MSpec.process
  end

  it "calls all start actions" do
    start = double("start")
    allow(start).to receive(:start) { ScratchPad.record :start }
    MSpec.register :start, start
    MSpec.process
    expect(ScratchPad.recorded).to eq(:start)
  end

  it "calls all finish actions" do
    finish = double("finish")
    allow(finish).to receive(:finish) { ScratchPad.record :finish }
    MSpec.register :finish, finish
    MSpec.process
    expect(ScratchPad.recorded).to eq(:finish)
  end

  it "calls the files method" do
    expect(MSpec).to receive(:files)
    MSpec.process
  end
end

RSpec.describe MSpec, ".files" do
  before :each do
    MSpec.store :load, []
    MSpec.store :unload, []
    MSpec.register_files [:one, :two, :three]
    allow(Kernel).to receive(:load)
  end

  it "calls load actions before each file" do
    load = double("load")
    allow(load).to receive(:load) { ScratchPad.record :load }
    MSpec.register :load, load
    MSpec.files
    expect(ScratchPad.recorded).to eq(:load)
  end

  it "shuffles the file list if .randomize? is true" do
    MSpec.randomize = true
    expect(MSpec).to receive(:shuffle)
    MSpec.files
    MSpec.randomize = false
  end

  it "registers the current file" do
    load = double("load")
    files = []
    allow(load).to receive(:load) { files << MSpec.file }
    MSpec.register :load, load
    MSpec.files
    expect(files).to eq([:one, :two, :three])
  end
end

RSpec.describe MSpec, ".shuffle" do
  before :each do
    @base = (0..100).to_a
    @list = @base.clone
    MSpec.shuffle @list
  end

  it "does not alter the elements in the list" do
    @base.each do |elt|
      expect(@list).to include(elt)
    end
  end

  it "changes the order of the list" do
    # obviously, this spec has a certain probability
    # of failing. If it fails, run it again.
    expect(@list).not_to eq(@base)
  end
end

RSpec.describe MSpec, ".tags_file" do
  before :each do
    MSpec.store :file, "path/to/spec/something/some_spec.rb"
    MSpec.store :tags_patterns, nil
  end

  it "returns the default tags file for the current spec file" do
    expect(MSpec.tags_file).to eq("path/to/spec/tags/something/some_tags.txt")
  end

  it "returns the tags file for the current spec file with custom tags_patterns" do
    MSpec.register_tags_patterns [[/^(.*)\/spec/, '\1/tags'], [/_spec.rb/, "_tags.txt"]]
    expect(MSpec.tags_file).to eq("path/to/tags/something/some_tags.txt")
  end

  it "performs multiple substitutions" do
    MSpec.register_tags_patterns [
      [%r(/spec/something/), "/spec/other/"],
      [%r(/spec/), "/spec/tags/"],
      [/_spec.rb/, "_tags.txt"]
    ]
    expect(MSpec.tags_file).to eq("path/to/spec/tags/other/some_tags.txt")
  end

  it "handles cases where no substitution is performed" do
    MSpec.register_tags_patterns [[/nothing/, "something"]]
    expect(MSpec.tags_file).to eq("path/to/spec/something/some_spec.rb")
  end
end

RSpec.describe MSpec, ".read_tags" do
  before :each do
    allow(MSpec).to receive(:tags_file).and_return(File.dirname(__FILE__) + '/tags.txt')
  end

  it "returns a list of tag instances for matching tag names found" do
    one = SpecTag.new "fail(broken):Some#method? works"
    expect(MSpec.read_tags(["fail", "pass"])).to eq([one])
  end

  it "returns [] if no tags names match" do
    expect(MSpec.read_tags("super")).to eq([])
  end
end

RSpec.describe MSpec, ".read_tags" do
  before :each do
    @tag = SpecTag.new "fails:Some#method"
    File.open(tmp("tags.txt", false), "w") do |f|
      f.puts ""
      f.puts @tag
      f.puts ""
    end
    allow(MSpec).to receive(:tags_file).and_return(tmp("tags.txt", false))
  end

  it "does not return a tag object for empty lines" do
    expect(MSpec.read_tags(["fails"])).to eq([@tag])
  end
end

RSpec.describe MSpec, ".write_tags" do
  before :each do
    FileUtils.cp File.dirname(__FILE__) + "/tags.txt", tmp("tags.txt", false)
    allow(MSpec).to receive(:tags_file).and_return(tmp("tags.txt", false))
    @tag1 = SpecTag.new "check(broken):Tag#rewrite works"
    @tag2 = SpecTag.new "broken:Tag#write_tags fails"
  end

  after :all do
    rm_r tmp("tags.txt", false)
  end

  it "overwrites the tags in the tag file" do
    expect(IO.read(tmp("tags.txt", false))).to eq(%[fail(broken):Some#method? works
incomplete(20%):The#best method ever
benchmark(0.01825):The#fastest method today
extended():\"Multi-line\\ntext\\ntag\"
])
    MSpec.write_tags [@tag1, @tag2]
    expect(IO.read(tmp("tags.txt", false))).to eq(%[check(broken):Tag#rewrite works
broken:Tag#write_tags fails
])
  end
end

RSpec.describe MSpec, ".write_tag" do
  before :each do
    allow(FileUtils).to receive(:mkdir_p)
    allow(MSpec).to receive(:tags_file).and_return(tmp("tags.txt", false))
    @tag = SpecTag.new "fail(broken):Some#method works"
  end

  after :all do
    rm_r tmp("tags.txt", false)
  end

  it "writes a tag to the tags file for the current spec file" do
    MSpec.write_tag @tag
    expect(IO.read(tmp("tags.txt", false))).to eq("fail(broken):Some#method works\n")
  end

  it "does not write a duplicate tag" do
    File.open(tmp("tags.txt", false), "w") { |f| f.puts @tag }
    MSpec.write_tag @tag
    expect(IO.read(tmp("tags.txt", false))).to eq("fail(broken):Some#method works\n")
  end
end

RSpec.describe MSpec, ".delete_tag" do
  before :each do
    FileUtils.cp File.dirname(__FILE__) + "/tags.txt", tmp("tags.txt", false)
    allow(MSpec).to receive(:tags_file).and_return(tmp("tags.txt", false))
    @tag = SpecTag.new "fail(Comments don't matter):Some#method? works"
  end

  after :each do
    rm_r tmp("tags.txt", false)
  end

  it "deletes the tag if it exists" do
    expect(MSpec.delete_tag(@tag)).to eq(true)
    expect(IO.read(tmp("tags.txt", false))).to eq(%[incomplete(20%):The#best method ever
benchmark(0.01825):The#fastest method today
extended():\"Multi-line\\ntext\\ntag\"
])
  end

  it "deletes a tag with escaped newlines" do
    expect(MSpec.delete_tag(SpecTag.new('extended:"Multi-line\ntext\ntag"'))).to eq(true)
    expect(IO.read(tmp("tags.txt", false))).to eq(%[fail(broken):Some#method? works
incomplete(20%):The#best method ever
benchmark(0.01825):The#fastest method today
])
  end

  it "does not change the tags file contents if the tag doesn't exist" do
    @tag.tag = "failed"
    expect(MSpec.delete_tag(@tag)).to eq(false)
    expect(IO.read(tmp("tags.txt", false))).to eq(%[fail(broken):Some#method? works
incomplete(20%):The#best method ever
benchmark(0.01825):The#fastest method today
extended():\"Multi-line\\ntext\\ntag\"
])
  end

  it "deletes the tag file if it is empty" do
    expect(MSpec.delete_tag(@tag)).to eq(true)
    expect(MSpec.delete_tag(SpecTag.new("incomplete:The#best method ever"))).to eq(true)
    expect(MSpec.delete_tag(SpecTag.new("benchmark:The#fastest method today"))).to eq(true)
    expect(MSpec.delete_tag(SpecTag.new('extended:"Multi-line\ntext\ntag"'))).to eq(true)
    expect(File.exist?(tmp("tags.txt", false))).to eq(false)
  end
end

RSpec.describe MSpec, ".delete_tags" do
  before :each do
    @tags = tmp("tags.txt", false)
    FileUtils.cp File.dirname(__FILE__) + "/tags.txt", @tags
    allow(MSpec).to receive(:tags_file).and_return(@tags)
  end

  it "deletes the tag file" do
    MSpec.delete_tags
    expect(File.exist?(@tags)).to be_falsey
  end
end

RSpec.describe MSpec, ".expectation" do
  it "sets the flag that an expectation has been reported" do
    MSpec.clear_expectations
    expect(MSpec.expectation?).to be_falsey
    MSpec.expectation
    expect(MSpec.expectation?).to be_truthy
  end
end

RSpec.describe MSpec, ".expectation?" do
  it "returns true if an expectation has been reported" do
    MSpec.expectation
    expect(MSpec.expectation?).to be_truthy
  end

  it "returns false if an expectation has not been reported" do
    MSpec.clear_expectations
    expect(MSpec.expectation?).to be_falsey
  end
end

RSpec.describe MSpec, ".clear_expectations" do
  it "clears the flag that an expectation has been reported" do
    MSpec.expectation
    expect(MSpec.expectation?).to be_truthy
    MSpec.clear_expectations
    expect(MSpec.expectation?).to be_falsey
  end
end

RSpec.describe MSpec, ".register_shared" do
  it "stores a shared ContextState by description" do
    parent = ContextState.new "container"
    state = ContextState.new "shared"
    state.parent = parent
    prc = lambda { }
    state.describe(&prc)
    MSpec.register_shared(state)
    expect(MSpec.retrieve(:shared)["shared"]).to eq(state)
  end
end

RSpec.describe MSpec, ".retrieve_shared" do
  it "retrieves the shared ContextState matching description" do
    state = ContextState.new ""
    MSpec.retrieve(:shared)["shared"] = state
    expect(MSpec.retrieve_shared(:shared)).to eq(state)
  end
end
