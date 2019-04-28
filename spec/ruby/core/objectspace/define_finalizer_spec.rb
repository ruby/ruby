require_relative '../../spec_helper'
require_relative 'fixtures/classes'

# NOTE: A call to define_finalizer does not guarantee that the
# passed proc or callable will be called at any particular time.
describe "ObjectSpace.define_finalizer" do
  it "raises an ArgumentError if the action does not respond to call" do
    lambda {
      ObjectSpace.define_finalizer("", mock("ObjectSpace.define_finalizer no #call"))
    }.should raise_error(ArgumentError)
  end

  it "accepts an object and a proc" do
    handler = lambda { |obj| obj }
    ObjectSpace.define_finalizer("garbage", handler).should == [0, handler]
  end

  it "accepts an object and a callable" do
    handler = mock("callable")
    def handler.call(obj) end
    ObjectSpace.define_finalizer("garbage", handler).should == [0, handler]
  end

  it "raises ArgumentError trying to define a finalizer on a non-reference" do
    lambda {
      ObjectSpace.define_finalizer(:blah) { 1 }
    }.should raise_error(ArgumentError)
  end

  # see [ruby-core:24095]
  it "calls finalizer on process termination" do
    code = <<-RUBY
      def scoped
        Proc.new { puts "finalized" }
      end
      handler = scoped
      obj = "Test"
      ObjectSpace.define_finalizer(obj, handler)
      exit 0
    RUBY

    ruby_exe(code).should == "finalized\n"
  end

  it "calls finalizer at exit even if it is self-referencing" do
    code = <<-RUBY
      obj = "Test"
      handler = Proc.new { puts "finalized" }
      ObjectSpace.define_finalizer(obj, handler)
      exit 0
    RUBY

    ruby_exe(code).should == "finalized\n"
  end

  it "allows multiple finalizers with different 'callables' to be defined" do
    code = <<-RUBY
      obj = Object.new

      ObjectSpace.define_finalizer(obj, Proc.new { STDOUT.write "finalized1\n" })
      ObjectSpace.define_finalizer(obj, Proc.new { STDOUT.write "finalized2\n" })

      exit 0
    RUBY

    ruby_exe(code).lines.sort.should == ["finalized1\n", "finalized2\n"]
  end
end
