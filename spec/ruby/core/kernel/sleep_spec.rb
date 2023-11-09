require_relative '../../spec_helper'

describe "Kernel#sleep" do
  it "is a private method" do
    Kernel.should have_private_instance_method(:sleep)
  end

  it "returns an Integer" do
    sleep(0.001).should be_kind_of(Integer)
  end

  it "accepts a Float" do
    sleep(0.001).should >= 0
  end

  it "accepts an Integer" do
    sleep(0).should >= 0
  end

  it "accepts a Rational" do
    sleep(Rational(1, 999)).should >= 0
  end

  it "accepts any Object that reponds to divmod" do
    o = Object.new
    def o.divmod(*); [0, 0.001]; end
    sleep(o).should >= 0
  end

  it "raises an ArgumentError when passed a negative duration" do
    -> { sleep(-0.1) }.should raise_error(ArgumentError)
    -> { sleep(-1) }.should raise_error(ArgumentError)
  end

  it "raises a TypeError when passed a String" do
    -> { sleep('2')   }.should raise_error(TypeError)
  end

  it "pauses execution indefinitely if not given a duration" do
    running = false
    t = Thread.new do
      running = true
      sleep
      5
    end

    Thread.pass until running
    Thread.pass while t.status and t.status != "sleep"

    t.wakeup
    t.value.should == 5
  end

  ruby_version_is ""..."3.3" do
    it "raises a TypeError when passed nil" do
      -> { sleep(nil)   }.should raise_error(TypeError)
    end
  end

  ruby_version_is "3.3" do
    it "accepts a nil duration" do
      running = false
      t = Thread.new do
        running = true
        sleep(nil)
        5
      end

      Thread.pass until running
      Thread.pass while t.status and t.status != "sleep"

      t.wakeup
      t.value.should == 5
    end
  end
end

describe "Kernel.sleep" do
  it "needs to be reviewed for spec completeness"
end
