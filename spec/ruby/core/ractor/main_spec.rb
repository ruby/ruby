require_relative '../../spec_helper'

ruby_version_is '3.0.0' do
  describe 'Ractor.main' do
    it 'returns main ractor object outside' do
      Ractor.current.should == Ractor.main
    end

    it 'returns main ractor object inside other ractors' do
      ractors = (1..3).map do
        Ractor.new do
          Ractor.main
        end
      end
      ractors[0].take.should == Ractor.current
      ractors[1].take.should == Ractor.current
      ractors[2].take.should == Ractor.current
    end
  end
end
