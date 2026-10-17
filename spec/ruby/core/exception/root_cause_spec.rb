require_relative '../../spec_helper'

ruby_version_is '3.3' do
  describe "Exception#root_cause" do
    it "returns the root cause of an exception" do
      root_cause = RuntimeError.new('a')

      -> {
        begin
          raise root_cause
        rescue => a
          begin
            raise 'b'
          rescue => b
            raise 'c'
          end
        end
      }.should raise_error(RuntimeError) { |e|
        e.root_cause.should.equal?(root_cause)
      }
    end

    it "has a nil cause" do
      -> {
        begin
          raise 'a'
        rescue => a
          begin
            raise 'b'
          rescue => b
            raise 'c'
          end
        end
      }.should raise_error(RuntimeError) { |e|
        e.root_cause.cause.should == nil
      }
    end
  end
end
