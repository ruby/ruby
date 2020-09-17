require_relative '../../spec_helper'

ruby_version_is '3.0.0' do
  describe 'Ractor#name' do
    context 'Default ractor name' do
      it 'returns nil for main ractor' do
        Ractor.current.name.should == nil
      end

      it 'returns nil for newly created ractor' do
        r = Ractor.new do
          Ractor.current.name
        end
        r.take.should == nil
      end
    end

    context 'Create ractor with name' do
      it 'returns ractor name outside named ractor' do
        r = Ractor.new(name: 'Test ractor name') {}
        r.name.should == 'Test ractor name'
      end

      it 'returns ractor name inside named ractor' do
        r = Ractor.new(name: 'Test ractor name') { Ractor.current.name }
        r.take.should == 'Test ractor name'
      end

      it 'raises exceptions if initialize with invalid name' do
        -> do
          Ractor.new(name: 123) {}
        end.should raise_error(TypeError)
        -> do
          Ractor.new(name: [1, 2, 3]) {}
        end.should raise_error(TypeError)
        -> do
          Ractor.new(name: {}) {}
        end.should raise_error(TypeError)
        -> do
          Ractor.new(name: String.new('Invalid encoding', encoding: 'UTF-16BE')) {}
        end.should raise_error(ArgumentError)
      end
    end

    context 'Re-assign ractor name' do
      it 'returns ractor new names outside named ractor' do
        r = Ractor.new {}

        r.name = 'New name 1'
        r.name.should == 'New name 1'

        r.name = 'New name 2'
        r.name.should == 'New name 2'

        r.name = nil
        r.name.should == nil
      end

      it 'returns ractor new names inside named ractor' do
        r = Ractor.new do
          3.times { Ractor.recv; Ractor.yield(Ractor.current.name) }
        end

        r.name = 'New name 1'
        r.send 'Rename event'
        r.take.should == 'New name 1'

        r.name = 'New name 2'
        r.send 'Rename event'
        r.take.should == 'New name 2'

        r.name = nil
        r.send 'Rename event'
        r.take.should == nil
      end

      it 'raises exceptions if assign with invalid name' do
        -> do
          r = Ractor.new {}
          r.name = 123
        end.should raise_error(TypeError)
        -> do
          r = Ractor.new {}
          r.name = [1, 2, 3]
        end.should raise_error(TypeError)
        -> do
          r = Ractor.new {}
          r.name = {}
        end.should raise_error(TypeError)
        -> do
          r = Ractor.new {}
          r.name = String.new('Invalid encoding', encoding: 'UTF-16BE')
        end.should raise_error(ArgumentError)
      end
    end
  end
end
