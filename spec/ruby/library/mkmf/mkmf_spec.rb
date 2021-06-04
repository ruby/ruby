require_relative '../../spec_helper'

describe 'mkmf' do
  it 'can be required with --enable-frozen-string-literal' do
    ruby_exe('p MakeMakefile', options: '-rmkmf --enable-frozen-string-literal').should == "MakeMakefile\n"
  end
end
