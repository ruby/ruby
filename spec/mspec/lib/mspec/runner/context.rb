# Holds the state of the +describe+ block that is being
# evaluated. Every example (i.e. +it+ block) is evaluated
# in a context, which may include state set up in <tt>before
# :each</tt> or <tt>before :all</tt> blocks.
#
#--
# A note on naming: this is named _ContextState_ rather
# than _DescribeState_ because +describe+ is the keyword
# in the DSL for referring to the context in which an example
# is evaluated, just as +it+ refers to the example itself.
#++
class ContextState
  attr_reader :state, :parent, :parents, :children, :examples, :to_s

  def initialize(mod, options = nil)
    @to_s = mod.to_s
    if options.is_a? Hash
      @options = options
    else
      @to_s += "#{".:#".include?(options[0,1]) ? "" : " "}#{options}" if options
      @options = { }
    end
    @options[:shared] ||= false

    @parsed   = false
    @before   = { :all => [], :each => [] }
    @after    = { :all => [], :each => [] }
    @pre      = {}
    @post     = {}
    @examples = []
    @parent   = nil
    @parents  = [self]
    @children = []

    @mock_verify         = Proc.new { Mock.verify_count }
    @mock_cleanup        = Proc.new { Mock.cleanup }
    @expectation_missing = Proc.new { raise SpecExpectationNotFoundError }
  end

  # Remove caching when a ContextState is dup'd for shared specs.
  def initialize_copy(other)
    @pre  = {}
    @post = {}
  end

  # Returns true if this is a shared +ContextState+. Essentially, when
  # created with: describe "Something", :shared => true { ... }
  def shared?
    return @options[:shared]
  end

  # Set the parent (enclosing) +ContextState+ for this state. Creates
  # the +parents+ list.
  def parent=(parent)
    @description = nil

    if shared?
      @parent = nil
    else
      @parent = parent
      parent.child self if parent

      @parents = [self]
      state = parent
      while state
        @parents.unshift state
        state = state.parent
      end
    end
  end

  # Add the ContextState instance +child+ to the list of nested
  # describe blocks.
  def child(child)
    @children << child
  end

  # Adds a nested ContextState in a shared ContextState to a containing
  # ContextState.
  #
  # Normal adoption is from the parent's perspective. But adopt is a good
  # verb and it's reasonable for the child to adopt the parent as well. In
  # this case, manipulating state from inside the child avoids needlessly
  # exposing the state to manipulate it externally in the dup. (See
  # #it_should_behave_like)
  def adopt(parent)
    self.parent = parent

    @examples = @examples.map do |example|
      example = example.dup
      example.context = self
      example
    end

    children = @children
    @children = []

    children.each { |child| child.dup.adopt self }
  end

  # Returns a list of all before(+what+) blocks from self and any parents.
  def pre(what)
    @pre[what] ||= parents.inject([]) { |l, s| l.push(*s.before(what)) }
  end

  # Returns a list of all after(+what+) blocks from self and any parents.
  # The list is in reverse order. In other words, the blocks defined in
  # inner describes are in the list before those defined in outer describes,
  # and in a particular describe block those defined later are in the list
  # before those defined earlier.
  def post(what)
    @post[what] ||= parents.inject([]) { |l, s| l.unshift(*s.after(what)) }
  end

  # Records before(:each) and before(:all) blocks.
  def before(what, &block)
    return if MSpec.guarded?
    block ? @before[what].push(block) : @before[what]
  end

  # Records after(:each) and after(:all) blocks.
  def after(what, &block)
    return if MSpec.guarded?
    block ? @after[what].unshift(block) : @after[what]
  end

  # Creates an ExampleState instance for the block and stores it
  # in a list of examples to evaluate unless the example is filtered.
  def it(desc, &block)
    example = ExampleState.new(self, desc, block)
    MSpec.actions :add, example
    return if MSpec.guarded?
    @examples << example
  end

  # Evaluates the block and resets the toplevel +ContextState+ to #parent.
  def describe(&block)
    @parsed = protect @to_s, block, false
    MSpec.register_current parent
    MSpec.register_shared self if shared?
  end

  # Returns a description string generated from self and all parents
  def description
    @description ||= parents.map { |p| p.to_s }.compact.join(" ")
  end

  # Injects the before/after blocks and examples from the shared
  # describe block into this +ContextState+ instance.
  def it_should_behave_like(desc)
    return if MSpec.guarded?

    unless state = MSpec.retrieve_shared(desc)
      raise Exception, "Unable to find shared 'describe' for #{desc}"
    end

    state.before(:all).each { |b| before :all, &b }
    state.before(:each).each { |b| before :each, &b }
    state.after(:each).each { |b| after :each, &b }
    state.after(:all).each { |b| after :all, &b }

    state.examples.each do |example|
      example = example.dup
      example.context = self
      @examples << example
    end

    state.children.each do |child|
      child.dup.adopt self
    end
  end

  # Evaluates each block in +blocks+ using the +MSpec.protect+ method
  # so that exceptions are handled and tallied. Returns true and does
  # NOT evaluate any blocks if +check+ is true and
  # <tt>MSpec.mode?(:pretend)</tt> is true.
  def protect(what, blocks, check = true)
    return true if check and MSpec.mode? :pretend
    Array(blocks).all? { |block| MSpec.protect what, &block }
  end

  # Removes filtered examples. Returns true if there are examples
  # left to evaluate.
  def filter_examples
    filtered, @examples = @examples.partition do |ex|
      ex.filtered?
    end

    filtered.each do |ex|
      MSpec.actions :tagged, ex
    end

    !@examples.empty?
  end

  # Evaluates the examples in a +ContextState+. Invokes the MSpec events
  # for :enter, :before, :after, :leave.
  def process
    MSpec.register_current self

    if @parsed and filter_examples
      MSpec.shuffle @examples if MSpec.randomize?
      MSpec.actions :enter, description

      if protect "before :all", pre(:all)
        @examples.each do |state|
          MSpec.repeat do
            @state  = state
            example = state.example
            MSpec.actions :before, state

            if protect "before :each", pre(:each)
              MSpec.clear_expectations
              if example
                passed = protect nil, example
                MSpec.actions :example, state, example
                protect nil, @expectation_missing if !MSpec.expectation? and passed
              end
            end
            protect "after :each", post(:each)
            protect "Mock.verify_count", @mock_verify

            protect "Mock.cleanup", @mock_cleanup
            MSpec.actions :after, state
            @state = nil
          end
        end
        protect "after :all", post(:all)
      else
        protect "Mock.cleanup", @mock_cleanup
      end

      MSpec.actions :leave
    end

    MSpec.register_current nil
    children.each { |child| child.process }
  end
end
