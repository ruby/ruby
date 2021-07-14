require 'fiddle'
require 'fiddle/import'

module Reline::Terminfo
  extend Fiddle::Importer

  class TerminfoError < StandardError; end

  @curses_dl = nil
  def self.curses_dl
    return @curses_dl if @curses_dl
    if RUBY_VERSION >= '3.0.0'
      # Gem module isn't defined in test-all of the Ruby repository, and
      # Fiddle in Ruby 3.0.0 or later supports Fiddle::TYPE_VARIADIC.
      fiddle_supports_variadic = true
    elsif Fiddle.const_defined?(:VERSION) and Gem::Version.create(Fiddle::VERSION) >= Gem::Version.create('1.0.1')
      # Fiddle::TYPE_VARIADIC is supported from Fiddle 1.0.1.
      fiddle_supports_variadic = true
    else
      fiddle_supports_variadic = false
    end
    if fiddle_supports_variadic
      %w[libncursesw.so libcursesw.so libncurses.so libcurses.so].each do |curses_name|
        result = Fiddle::Handle.new(curses_name)
      rescue Fiddle::DLError
        next
      else
        @curses_dl = result
        break
      end
    end
    @curses_dl
  end
end

module Reline::Terminfo
  dlload curses_dl
  #extern 'int setupterm(char *term, int fildes, int *errret)'
  @setupterm = Fiddle::Function.new(curses_dl['setupterm'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_INT, Fiddle::TYPE_VOIDP], Fiddle::TYPE_INT)
  #extern 'char *tigetstr(char *capname)'
  @tigetstr = Fiddle::Function.new(curses_dl['tigetstr'], [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
  #extern 'char *tiparm(const char *str, ...)'
  @tiparm = Fiddle::Function.new(curses_dl['tiparm'], [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VARIADIC], Fiddle::TYPE_VOIDP)

  def self.setupterm(term, fildes)
    errret_int = String.new("\x00" * 8, encoding: 'ASCII-8BIT')
    ret = @setupterm.(term, fildes, errret_int)
    errret = errret_int.unpack('i')[0]
    case ret
    when 0 # OK
      0
    when -1 # ERR
      case errret
      when 1
        raise TerminfoError.new('The terminal is hardcopy, cannot be used for curses applications.')
      when 0
        raise TerminfoError.new('The terminal could not be found, or that it is a generic type, having too little information for curses applications to run.')
      when -1
        raise TerminfoError.new('The terminfo database could not be found.')
      else # unknown
        -1
      end
    else # unknown
      -2
    end
  end

  def self.tigetstr(capname)
    result = @tigetstr.(capname).to_s
    def result.tiparm(*args) # for method chain
      Reline::Terminfo.tiparm(self, *args)
    end
    result
  end

  def self.tiparm(str, *args)
    new_args = []
    args.each do |a|
      new_args << Fiddle::TYPE_INT << a
    end
    @tiparm.(str, *new_args).to_s
  end

  def self.enabled?
    true
  end
end if Reline::Terminfo.curses_dl

module Reline::Terminfo
  def self.enabled?
    false
  end
end unless Reline::Terminfo.curses_dl
