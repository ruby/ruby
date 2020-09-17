require_relative '../../spec_helper'

ruby_version_is '3.0.0' do
  describe 'Ractor#status' do
    context 'ractor has 1 terminated thread' do
      it 'returns terminated' do
        r = Ractor.new { 'farewell' }
        r.take
        r.status.should == 'terminated'
      end
    end

    context 'ractor has many terminated threads' do
      it 'returns terminated' do
        r = Ractor.new do
          threads = (1..3).map do |index|
            Thread.new do
              a = 1
            end
          end
          threads.map(&:join)
          0
        end
        r.take
        r.status.should == 'terminated'
      end
    end

    context 'ractor is being blocked' do
      it 'returns blocking' do
        r = Ractor.new do
          Ractor.recv
        end
        r.status.should == 'blocking'

        r.send 'End ractor'
        r.take
        r.status.should == 'terminated'
      end
    end

    context 'ractor has 1 blocking thread and some terminated threads' do
      it 'returns blocking' do
        r = Ractor.new do
          threads = (1..3).map do |index|
            Thread.new do
              a = 1
            end
          end
          threads.map(&:join)
          Ractor.yield 'Finish join'
          Ractor.recv
        end

        r.take
        r.status.should == 'blocking'

        r.send 'End ractor'
        r.take
        r.status.should == 'terminated'
      end
    end

    context 'ractor is running' do
      it 'returns running' do
        Ractor.current.status.should == 'running'
        r = Ractor.new { Ractor.current.status }
        r.take.should == 'running'
      end
    end
  end
end
