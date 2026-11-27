module CoverageSpecs
  # Loads the code as a file of its own and returns what Coverage.result reports for that file.
  # The file is loaded wrapped, so that its top-level definitions do not outlive it.
  def self.result(code, modes)
    path = tmp("coverage_spec.rb")
    touch(path) { |f| f.write(code) }
    Coverage.start(modes)
    begin
      suppress_warning { load path, true }
      Coverage.result.fetch(path)
    ensure
      Coverage.result if Coverage.running?
      rm_r path
    end
  end

  def self.line_coverage(code)
    result(code, lines: true)[:lines]
  end

  def self.branch_coverage(code)
    result(code, branches: true)[:branches]
  end

  def self.method_coverage(code)
    result(code, methods: true)[:methods]
  end

  def self.line_stub(code)
    path = tmp("coverage_spec.rb")
    touch(path) { |f| f.write(code) }
    Coverage.line_stub(path)
  ensure
    rm_r path
  end
end
