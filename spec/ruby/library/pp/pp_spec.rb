require_relative '../../spec_helper'
require 'pp'

describe "PP.pp" do
  it 'works with default arguments' do
    array = [1, 2, 3]

    -> {
      PP.pp array
    }.should output "[1, 2, 3]\n"
  end

  it 'allows specifying out explicitly' do
    array = [1, 2, 3]
    other_out = IOStub.new

    -> {
      PP.pp array, other_out
    }.should output "" # no output on stdout

    other_out.to_s.should == "[1, 2, 3]\n"
  end

  it 'correctly prints a Hash' do
    hash = { 'key' => 42 }
    -> {
      PP.pp hash
    }.should output('{"key"=>42}' + "\n")
  end
end
