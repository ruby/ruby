require_relative '../../../spec_helper'

ruby_version_is "4.1" do
  describe "IO::Buffer#slice with a slice parent" do
    before :each do
      @buffer = IO::Buffer.new(8)
      @buffer.set_string("abcdefgh")
      @parent = @buffer.slice(1, 6)
      @child = @parent.slice(1, 2)
    end

    after :each do
      @buffer.free
    end

    it "moves with its immediate parent when the parent advances" do
      @child.get_string.should == "cd"
      @parent.advance(1)
      @child.get_string.should == "de"
      @child.set_string("XY")
      @buffer.get_string.should == "abcXYfgh"
    end

    it "becomes invalid when advancing the parent leaves too little room" do
      @parent.advance(4)
      @parent.get_string.should == "fg"
      @child.should_not.valid?
      -> { @child.get_string }.should.raise(IO::Buffer::InvalidatedError)
      @parent.resize(3)
      @child.should.valid?
      @child.get_string.should == "gh"
    end

    it "becomes valid again when a shrunken parent regrows" do
      @parent.resize(2)
      @child.should_not.valid?
      @parent.resize(3)
      @child.should.valid?
      @child.get_string.should == "cd"
    end

    it "requires every ancestor's complete view to be valid" do
      @buffer.resize(4)
      # The child's absolute range [2, 4) fits, but the parent's does not.
      @parent.should_not.valid?
      @child.should_not.valid?
      -> { @child.get_string }.should.raise(IO::Buffer::InvalidatedError)
      @parent.resize(3)
      @child.should.valid?
      @child.get_string.should == "cd"
    end

    it "remains a view of its parent when resized to zero and grown again" do
      @parent.resize(0)
      @parent.source.should.equal?(@buffer)
      @child.should_not.valid?
      @parent.resize(4)
      @parent.set_string("1234")
      @child.should.valid?
      @child.get_string.should == "23"
      @buffer.get_string.should == "a1234fgh"
    end

    it "does not expose allocation-management methods" do
      @parent.respond_to?(:free).should == false
      @parent.respond_to?(:transfer).should == false
    end

    it "shares the root allocation lock through the parent chain" do
      @child.locked do
        @parent.should.locked?
        @buffer.should.locked?
        -> { @buffer.resize(16) }.should.raise(IO::Buffer::LockedError)
        -> { @buffer.free }.should.raise(IO::Buffer::LockedError)
        -> { @buffer.transfer }.should.raise(IO::Buffer::LockedError)

        @parent.advance(1)
        @child.get_string.should == "de"
      end
      @parent.should_not.locked?
      @buffer.should_not.locked?
    end

    it "respects write restrictions on an intermediate parent" do
      @parent.freeze
      @child.should.readonly?
      -> { @child.set_string("XY") }.should.raise(IO::Buffer::AccessError)
      @buffer.get_string.should == "abcdefgh"
      @child.advance(1)
      @child.get_string.should == "d"
    end
  end
end
