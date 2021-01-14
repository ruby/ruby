class RubyVM::MJITWorker
  def self.start
    $VERBOSE, verbose = nil, $VERBOSE # shut up "warning: Ractor is experimental"
    Ractor.new(name: 'mjit-worker') do
      RubyVM.const_get(:MJITWorker, false).new.run
    end
  ensure
    $VERBOSE = verbose
  end

  def run
    Primitive.mjit_worker
  end
end
RubyVM.private_constant(:MJITWorker)
