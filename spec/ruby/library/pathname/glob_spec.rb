require_relative '../../spec_helper'
require 'pathname'

describe 'Pathname.glob' do
  before :all  do
    @dir = tmp('pathname_glob') + '/'
    @file_1 = @dir + 'lib/ipaddr.rb'
    @file_2 = @dir + 'lib/irb.rb'
    @file_3 = @dir + 'lib/.hidden.rb'

    touch @file_1
    touch @file_2
    touch @file_3
  end

  after :all do
    rm_r @dir[0...-1]
  end

  it 'returns [] for no match' do
    Pathname.glob(@dir + 'lib/*.js').should == []
  end

  it 'returns matching file paths' do
    Pathname.glob(@dir + 'lib/*i*.rb').sort.should == [Pathname.new(@file_1), Pathname.new(@file_2)].sort
  end

  it 'returns matching file paths when a flag is provided' do
    expected = [Pathname.new(@file_1), Pathname.new(@file_2), Pathname.new(@file_3)].sort
    Pathname.glob(@dir + 'lib/*i*.rb', File::FNM_DOTMATCH).sort.should == expected
  end

  it 'returns matching file paths when supplied :base keyword argument' do
    Pathname.glob('*i*.rb', base: @dir + 'lib').sort.should == [Pathname.new('ipaddr.rb'), Pathname.new('irb.rb')].sort
  end

  it "raises an ArgumentError when supplied a keyword argument other than :base" do
    -> {
      Pathname.glob('*i*.rb', foo: @dir + 'lib')
    }.should raise_error(ArgumentError, /unknown keyword: :?foo/)
  end

  ruby_version_is ''...'2.7' do
    it 'raises an ArgumentError when supplied a flag and :base keyword argument' do
      -> {
        Pathname.glob(@dir + 'lib/*i*.rb', File::FNM_DOTMATCH, base: 'lib')
      }.should raise_error(ArgumentError, 'wrong number of arguments (given 3, expected 1..2)')
    end
  end

  ruby_version_is "2.7" do
    it "does not raise an ArgumentError when supplied a flag and :base keyword argument" do
      expected = [Pathname.new('ipaddr.rb'), Pathname.new('irb.rb'), Pathname.new('.hidden.rb')].sort
      Pathname.glob('*i*.rb', File::FNM_DOTMATCH, base: @dir + 'lib').sort.should == expected
    end
  end
end
