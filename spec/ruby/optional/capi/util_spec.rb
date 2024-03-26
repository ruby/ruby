require_relative 'spec_helper'

load_extension('util')

describe "C-API Util function" do
  before :each do
    @o = CApiUtilSpecs.new
  end

  describe "rb_scan_args" do
    before :each do
      @prc = -> { 1 }
      @acc = []
      ScratchPad.record @acc
    end

    it "assigns the required arguments scanned" do
      obj = Object.new
      @o.rb_scan_args([obj, 2], "2", 2, @acc).should == 2
      ScratchPad.recorded.should == [obj, 2]
    end

    it "raises an ArgumentError if there are insufficient arguments" do
      -> { @o.rb_scan_args([1, 2], "3", 0, @acc) }.should raise_error(ArgumentError)
    end

    it "raises an ArgumentError if there are too many arguments" do
      -> { @o.rb_scan_args([1, 2, 3, 4], "3", 0, @acc) }.should raise_error(ArgumentError)
    end

    it "assigns the required and optional arguments scanned" do
      @o.rb_scan_args([1, 2], "11", 2, @acc).should == 2
      ScratchPad.recorded.should == [1, 2]
    end

    it "assigns the optional arguments scanned" do
      @o.rb_scan_args([1, 2], "02", 2, @acc).should == 2
      ScratchPad.recorded.should == [1, 2]
    end

    it "assigns nil for optional arguments that are not present" do
      @o.rb_scan_args([1], "03", 3, @acc).should == 1
      ScratchPad.recorded.should == [1, nil, nil]
    end

    it "assigns the required and optional arguments and splats the rest" do
      @o.rb_scan_args([1, 2, 3, 4], "11*", 3, @acc).should == 4
      ScratchPad.recorded.should == [1, 2, [3, 4]]
    end

    it "assigns the required and optional arguments and empty Array when there are no arguments to splat" do
      @o.rb_scan_args([1, 2], "11*", 3, @acc).should == 2
      ScratchPad.recorded.should == [1, 2, []]
    end

    it "assigns required, optional arguments scanned and the passed block" do
      @o.rb_scan_args([1, 2], "11&", 3, @acc, &@prc).should == 2
      ScratchPad.recorded.should == [1, 2, @prc]
    end

    it "assigns required, optional, splatted arguments scanned and the passed block" do
      @o.rb_scan_args([1, 2, 3, 4], "11*&", 4, @acc, &@prc).should == 4
      ScratchPad.recorded.should == [1, 2, [3, 4], @prc]
    end

    it "assigns required arguments, nil for missing optional arguments and the passed block" do
      @o.rb_scan_args([1], "12&", 4, @acc, &@prc).should == 1
      ScratchPad.recorded.should == [1, nil, nil, @prc]
    end

    it "assigns required, splatted arguments and the passed block" do
      @o.rb_scan_args([1, 2, 3], "1*&", 3, @acc, &@prc).should == 3
      ScratchPad.recorded.should == [1, [2, 3], @prc]
    end

    it "assigns post-splat arguments" do
      @o.rb_scan_args([1, 2, 3], "00*1", 2, @acc).should == 3
      ScratchPad.recorded.should == [[1, 2], 3]
    end

    it "assigns required, optional, splat and post-splat arguments" do
      @o.rb_scan_args([1, 2, 3, 4, 5], "11*1", 4, @acc).should == 5
      ScratchPad.recorded.should == [1, 2, [3, 4], 5]
    end

    it "assigns required, splat, post-splat arguments" do
      @o.rb_scan_args([1, 2, 3, 4], "10*1", 3, @acc).should == 4
      ScratchPad.recorded.should == [1, [2, 3], 4]
    end

    it "assigns optional, splat, post-splat arguments" do
      @o.rb_scan_args([1, 2, 3, 4], "01*1", 3, @acc).should == 4
      ScratchPad.recorded.should == [1, [2, 3], 4]
    end

    it "assigns required, optional, splat, post-splat and block arguments" do
      @o.rb_scan_args([1, 2, 3, 4, 5], "11*1&", 5, @acc, &@prc).should == 5
      ScratchPad.recorded.should == [1, 2, [3, 4], 5, @prc]
    end

    it "assigns Hash arguments" do
      h = {a: 1, b: 2}
      @o.rb_scan_args([h], "k0:", 1, @acc).should == 0
      ScratchPad.recorded.should == [h]
    end

    it "assigns required and Hash arguments" do
      h = {a: 1, b: 2}
      @o.rb_scan_args([1, h], "k1:", 2, @acc).should == 1
      ScratchPad.recorded.should == [1, h]
    end

    it "assigns required and Hash arguments with optional Hash" do
      @o.rb_scan_args([1], "1:", 2, @acc).should == 1
      ScratchPad.recorded.should == [1, nil]
    end

    it "rejects the use of nil as a hash" do
      -> {
        @o.rb_scan_args([1, nil], "1:", 2, @acc).should == 1
      }.should raise_error(ArgumentError)
      ScratchPad.recorded.should == []
    end

    it "assigns required and optional arguments with no hash argument given" do
      @o.rb_scan_args([1, 7, 4], "21:", 3, @acc).should == 3
      ScratchPad.recorded.should == [1, 7, 4]
    end

    it "assigns optional arguments with no hash argument given" do
      @o.rb_scan_args([1, 7], "02:", 3, @acc).should == 2
      ScratchPad.recorded.should == [1, 7, nil]
    end

    it "assigns optional arguments with no hash argument given and rejects the use of optional nil argument as a hash" do
      -> {
        @o.rb_scan_args([1, nil], "02:", 3, @acc).should == 2
      }.should_not complain

      ScratchPad.recorded.should == [1, nil, nil]
    end

    it "assigns required, optional, splat, post-splat, Hash and block arguments" do
      h = {a: 1, b: 2}
      @o.rb_scan_args([1, 2, 3, 4, 5, h], "k11*1:&", 6, @acc, &@prc).should == 5
      ScratchPad.recorded.should == [1, 2, [3, 4], 5, h, @prc]
    end

    it "does not reject non-symbol keys in keyword arguments" do
      h = {1 => 2, 3 => 4}
      @o.rb_scan_args([h], "k0:", 1, @acc).should == 0
      ScratchPad.recorded.should == [h]
    end

    it "does not reject non-symbol keys in keyword arguments with required argument" do
      h = {1 => 2, 3 => 4}
      @o.rb_scan_args([1, h], "k1:", 2, @acc).should == 1
      ScratchPad.recorded.should == [1, h]
    end

    it "considers keyword arguments with non-symbol keys as keywords when using splat and post arguments" do
      h = {1 => 2, 3 => 4}
      @o.rb_scan_args([1, 2, 3, 4, 5, h], "k11*1:&", 6, @acc, &@prc).should == 5
      ScratchPad.recorded.should == [1, 2, [3, 4], 5, h, @prc]
    end
  end

  describe "rb_get_kwargs" do
    it "extracts required arguments in the order requested" do
      h = { :a => 7, :b => 5 }
      @o.rb_get_kwargs(h, [:b, :a], 2, 0).should == [5, 7]
      h.should == {}
    end

    it "extracts required and optional arguments in the order requested" do
      h = { :a => 7, :c => 12, :b => 5 }
      @o.rb_get_kwargs(h, [:b, :a, :c], 2, 1).should == [5, 7, 12]
      h.should == {}
    end

    it "accepts nil instead of a hash when only optional arguments are requested" do
      h = nil
      @o.rb_get_kwargs(h, [:b, :a, :c], 0, 3).should == []
      h.should == nil
    end

    it "raises an error if a required argument is not in the hash" do
      h = { :a => 7, :c => 12, :b => 5 }
      -> { @o.rb_get_kwargs(h, [:b, :d], 2, 0) }.should raise_error(ArgumentError, /missing keyword: :?d/)
      h.should == {:a => 7, :c => 12}
    end

    it "does not raise an error for an optional argument not in the hash" do
      h = { :a => 7, :b => 5 }
      @o.rb_get_kwargs(h, [:b, :a, :c], 2, 1).should == [5, 7]
      h.should == {}
    end

    it "raises an error if there are additional arguments  and optional is positive" do
      h = { :a => 7, :c => 12, :b => 5 }
      -> { @o.rb_get_kwargs(h, [:b, :a], 2, 0) }.should raise_error(ArgumentError, /unknown keyword: :?c/)
      h.should == {:c => 12}
    end

    it "leaves additional arguments in the hash if optional is negative" do
      h = { :a => 7, :c => 12, :b => 5 }
      @o.rb_get_kwargs(h, [:b, :a], 2, -1).should == [5, 7]
      h.should == {:c => 12}
    end
  end

  platform_is wordsize: 64 do
    describe "rb_long2int" do
      it "raises a RangeError if the value is outside the range of a C int" do
        -> { @o.rb_long2int(0xffff_ffff_ffff) }.should raise_error(RangeError)
      end
    end

    it "returns the C int value" do
      @o.rb_long2int(1234).should == 1234
    end
  end

  # #7896
  describe "rb_iter_break" do
    before :each do
      ScratchPad.record []
    end

    it "breaks a loop" do
      3.times do |i|
        if i == 2
          @o.rb_iter_break
        end
        ScratchPad << i
      end
      ScratchPad.recorded.should == [0, 1]
    end

    it "breaks the inner loop" do
      3.times do |i|
        3.times do |j|
          if i == 1
            @o.rb_iter_break
          end
          ScratchPad << [i, j]
        end
      end
      ScratchPad.recorded.should == [[0, 0], [0, 1], [0, 2], [2, 0], [2, 1], [2, 2]]
    end
  end

  describe "rb_sourcefile" do
    it "returns the current ruby file" do
      @o.rb_sourcefile.should == __FILE__
    end
  end

  describe "rb_sourceline" do
    it "returns the current ruby file" do
      @o.rb_sourceline.should be_kind_of(Integer)
    end
  end

  # ruby/util.h redefines strtod as a macro calling ruby_strtod

  describe "strtod" do
    it "converts a string to a double and returns the remaining string" do
      d, s = @o.strtod("14.25test")
      d.should == 14.25
      s.should == "test"
    end

    it "returns 0 and the full string if there's no numerical value" do
      d, s = @o.strtod("test")
      d.should == 0
      s.should == "test"
    end
  end

  describe "ruby_strtod" do
    it "converts a string to a double and returns the remaining string" do
      d, s = @o.ruby_strtod("14.25test")
      d.should == 14.25
      s.should == "test"
    end

    it "returns 0 and the full string if there's no numerical value" do
      d, s = @o.ruby_strtod("test")
      d.should == 0
      s.should == "test"
    end
  end

end
