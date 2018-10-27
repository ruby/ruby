require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/each_line'
require_relative 'shared/each_line_without_block'

describe "String#lines" do
  it_behaves_like :string_each_line, :lines

  it "returns an array when no block given" do
    ary = "hello world".lines(' ')
    ary.should == ["hello ", "world"]
  end

  ruby_version_is '2.4' do
    context "when `chomp` keyword argument is passed" do
      it "removes new line characters" do
        "hello \nworld\n".lines(chomp: true).should == ["hello ", "world"]
        "hello \r\nworld\r\n".lines(chomp: true).should == ["hello ", "world"]
      end
    end
  end
end
