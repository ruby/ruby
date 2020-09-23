# frozen_string_literal: true
##
# Represents a possible Specification object returned from IndexSet.  Used to
# delay needed to download full Specification objects when only the +name+
# and +version+ are needed.

class Gem::Resolver::IndexSpecification < Gem::Resolver::Specification
  ##
  # An IndexSpecification is created from the index format described in `gem
  # help generate_index`.
  #
  # The +set+ contains other specifications for this (URL) +source+.
  #
  # The +name+, +version+ and +platform+ are the name, version and platform of
  # the gem.

  def initialize(set, name, version, source, platform)
    super()

    @set = set
    @name = name
    @version = version
    @source = source
    @platform = platform.to_s

    @spec = nil
  end

  ##
  # The dependencies of the gem for this specification

  def dependencies
    spec.dependencies
  end

  def inspect # :nodoc:
    '#<%s %s source %s>' % [self.class, full_name, @source]
  end

  def pretty_print(q) # :nodoc:
    q.group 2, '[Index specification', ']' do
      q.breakable
      q.text full_name

      unless Gem::Platform::RUBY == @platform
        q.breakable
        q.text @platform.to_s
      end

      q.breakable
      q.text 'source '
      q.pp @source
    end
  end

  ##
  # Fetches a Gem::Specification for this IndexSpecification from the #source.

  def spec # :nodoc:
    @spec ||=
      begin
        tuple = Gem::NameTuple.new @name, @version, @platform

        @source.fetch_spec tuple
      end
  end
end
