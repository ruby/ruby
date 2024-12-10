require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe 'TracePoint#raised_exception' do
  it 'returns value from exception raised on the :raise event' do
    raised_exception, error_result = nil
    trace = TracePoint.new(:raise) { |tp|
      next unless TracePointSpec.target_thread?
      raised_exception = tp.raised_exception
    }
    trace.enable do
      begin
        raise StandardError
      rescue => e
        error_result = e
      end
      raised_exception.should equal(error_result)
    end
  end

  ruby_version_is "3.3" do
    it 'returns value from exception rescued on the :rescue event' do
      raised_exception, error_result = nil
      trace = TracePoint.new(:rescue) { |tp|
        next unless TracePointSpec.target_thread?
        raised_exception = tp.raised_exception
      }
      trace.enable do
        begin
          raise StandardError
        rescue => e
          error_result = e
        end
        raised_exception.should equal(error_result)
      end
    end
  end
end
