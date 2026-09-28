require_relative '../../../spec_helper'

[:and!, :or!, :xor!].each do |operation|
  describe "IO::Buffer##{operation} range checking" do
    before :each do
      @buffer = IO::Buffer.new(8)
      @buffer.set_string("abcdefgh")
    end

    after :each do
      @buffer.free
    end

    ruby_version_is "4.1" do
      it "accepts an empty destination at the start, inside, or end of the mask" do
        [0, 4, 8].each do |offset|
          destination = @buffer.slice(offset, 0)
          destination.should_not.null?
          destination.public_send(operation, @buffer).should.equal?(destination)
          destination.should.empty?
          @buffer.get_string.should == "abcdefgh"
        end
      end
    end

    it "rejects actual overlap in either address order" do
      [
        [[0, 4], [0, 4]],
        [[0, 4], [2, 4]],
        [[2, 4], [0, 4]],
        [[1, 6], [2, 2]],
        [[2, 2], [1, 6]],
      ].each do |left, right|
        destination = @buffer.slice(*left)
        mask = @buffer.slice(*right)
        -> { destination.public_send(operation, mask) }.should.raise(
          IO::Buffer::MaskError, "Mask overlaps source buffer!"
        )
      end
      @buffer.get_string.should == "abcdefgh"
    end

    # Adjacent-range overlap was fixed in Ruby 3.4 ([Bug #20933]).
    ruby_version_is "3.4" do
      it "accepts adjacent non-empty ranges in either address order" do
        [[[0, 4], [4, 4]], [[4, 4], [0, 4]]].each do |left, right|
          @buffer.set_string("abcdefgh")
          destination = @buffer.slice(*left)
          mask = @buffer.slice(*right)
          original_mask = mask.get_string
          destination.public_send(operation, mask).should.equal?(destination)
          mask.get_string.should == original_mask
        end
      end
    end

    it "rejects empty masks even when the destination is empty" do
      [@buffer, @buffer.slice(4, 0)].each do |destination|
        -> { destination.public_send(operation, @buffer.slice(4, 0)) }.should.raise(
          IO::Buffer::MaskError, "Zero-length mask given!"
        )
      end
    end
  end
end
