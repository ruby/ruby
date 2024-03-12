require_relative '../../spec_helper'
require 'coverage'

describe 'Coverage.start' do
  before :each do
    Coverage.should_not.running?
  end

  after :each do
    Coverage.result(stop: true, clear: true) if Coverage.running?
  end

  it "enables the coverage measurement" do
    Coverage.start
    Coverage.should.running?
  end

  it "returns nil" do
    Coverage.start.should == nil
  end

  ruby_version_is '3.1' do
    it 'raises error when repeated Coverage.start call happens' do
      Coverage.start

      -> {
        Coverage.start
      }.should raise_error(RuntimeError, 'coverage measurement is already setup')
    end
  end

  ruby_version_is '3.2' do
    it "accepts :all optional argument" do
      Coverage.start(:all)
      Coverage.should.running?
    end

    it "accepts lines: optional keyword argument" do
      Coverage.start(lines: true)
      Coverage.should.running?
    end

    it "accepts branches: optional keyword argument" do
      Coverage.start(branches: true)
      Coverage.should.running?
    end

    it "accepts methods: optional keyword argument" do
      Coverage.start(methods: true)
      Coverage.should.running?
    end

    it "accepts eval: optional keyword argument" do
      Coverage.start(eval: true)
      Coverage.should.running?
    end

    it "accepts oneshot_lines: optional keyword argument" do
      Coverage.start(oneshot_lines: true)
      Coverage.should.running?
    end

    it "ignores unknown keyword arguments" do
      Coverage.start(foo: true)
      Coverage.should.running?
    end

    it "expects a Hash if not passed :all" do
      -> {
        Coverage.start(42)
      }.should raise_error(TypeError, "no implicit conversion of Integer into Hash")
    end

    it "does not accept both lines: and oneshot_lines: keyword arguments" do
      -> {
        Coverage.start(lines: true, oneshot_lines: true)
      }.should raise_error(RuntimeError, "cannot enable lines and oneshot_lines simultaneously")
    end

    it "enables the coverage measurement if passed options with `false` value" do
      Coverage.start(lines: false, branches: false, methods: false, eval: false, oneshot_lines: false)
      Coverage.should.running?
    end

    it "measures coverage within eval" do
      Coverage.start(lines: true, eval: true)
      eval("Object.new\n"*3, binding, "test.rb", 1)
      Coverage.result["test.rb"].should == {lines: [1, 1, 1]}
    end
  end
end
