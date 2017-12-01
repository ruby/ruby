require File.expand_path('../../../spec_helper', __FILE__)

describe 'TracePoint#raised_exception' do
  it 'returns value from exception raised on the :raise event' do
    raised_exception, error_result = nil
    trace = TracePoint.new(:raise) { |tp| raised_exception = tp.raised_exception }
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
