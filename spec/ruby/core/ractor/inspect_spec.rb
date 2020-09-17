require_relative '../../spec_helper'

ruby_version_is '3.0.0' do
  describe 'Ractor#inspect' do
    context 'Main ractor' do
      it 'returns id number one and status' do
        Ractor.current.inspect.should == '#<Ractor:#1 running>'
      end
    end

    context 'New plain Ractor' do
      it 'returns id, loc, and current status' do
        file = __FILE__
        lineno = __LINE__ + 1
        r = Ractor.new { Ractor.recv }
        r.inspect.should =~ /^#<Ractor:#([^ ]*?) #{file}:#{lineno} blocking>$/

        r.send('End ractor')
        r.take
        r.inspect.should =~ /^#<Ractor:#([^ ]*?) #{file}:#{lineno} terminated>$/
      end
    end

    context 'Named Ractor' do
      it 'returns id, name, loc, and current status' do
        file = __FILE__
        lineno = __LINE__ + 1
        r = Ractor.new(name: 'Super ractor') { Ractor.recv }
        r.inspect.should =~ /^#<Ractor:#([^ ]*?) Super ractor #{file}:#{lineno} blocking>$/

        r.send('End ractor')
        r.take
        r.inspect.should =~ /^#<Ractor:#([^ ]*?) Super ractor #{file}:#{lineno} terminated>$/

        r.name = 'Hot ractor'
        r.inspect.should =~ /^#<Ractor:#([^ ]*?) Hot ractor #{file}:#{lineno} terminated>$/
      end
    end
  end
end
