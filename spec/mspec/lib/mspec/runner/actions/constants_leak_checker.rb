class ConstantsLockFile
  LOCK_FILE_NAME = '.mspec.constants'

  def self.lock_file
    @prefix ||= File.expand_path(MSpecScript.get(:prefix) || '.')
    "#{@prefix}/#{LOCK_FILE_NAME}"
  end

  def self.load
    if File.exist?(lock_file)
      File.readlines(lock_file).map(&:chomp)
    else
      []
    end
  end

  def self.dump(ary)
    contents = ary.map(&:to_s).uniq.sort.join("\n") + "\n"
    File.write(lock_file, contents)
  end
end

class ConstantLeakError < StandardError
end

class ConstantsLeakCheckerAction
  def initialize(save)
    @save = save
    @check = !save
    @constants_locked = ConstantsLockFile.load
    @exclude_patterns = MSpecScript.get(:toplevel_constants_excludes) || []
  end

  def register
    MSpec.register :start, self
    MSpec.register :before, self
    MSpec.register :after, self
    MSpec.register :finish, self
  end

  def start
    @constants_start = constants_now
  end

  def before(state)
    @constants_before = constants_now
  end

  def after(state)
    constants = remove_excludes(constants_now - @constants_before - @constants_locked)

    if @check && !constants.empty?
      MSpec.protect 'Constants leak check' do
        raise ConstantLeakError, "Top level constants leaked: #{constants.join(', ')}"
      end
    end
  end

  def finish
    constants = remove_excludes(constants_now - @constants_start - @constants_locked)

    if @save
      ConstantsLockFile.dump(@constants_locked + constants)
    end

    if @check && !constants.empty?
      MSpec.protect 'Global constants leak check' do
        raise ConstantLeakError, "Top level constants leaked in the whole test suite: #{constants.join(', ')}"
      end
    end
  end

  private

  def constants_now
    Object.constants.map(&:to_s)
  end

  def remove_excludes(constants)
    constants.reject { |name|
      @exclude_patterns.any? { |pattern| pattern === name }
    }
  end
end
