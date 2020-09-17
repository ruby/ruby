require_relative '../../spec_helper'

ruby_version_is '3.0.0' do
  describe 'Ractor.count' do
    it 'returns currently alive ractors' do
      Ractor.count.should == 1

      ractors = (1..3).map { Ractor.new { Ractor.recv } }
      Ractor.count.should == 4

      ractors[0].send('End 0').take
      Ractor.count.should == 3

      ractors[1].send('End 1').take
      Ractor.count.should == 2

      ractors[2].send('End 2').take
      Ractor.count.should == 1
    end
  end
end
