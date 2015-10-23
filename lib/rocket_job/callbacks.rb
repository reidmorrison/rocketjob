require 'thread_safe'
# Before and after callbacks are executed in sequence.
# Around callbacks are chained using nested lambda calls.
#
# Callbacks are executed in the following order during inheritance
#   child.before
#   parent.before
#   child.around
#   parent.around
#   parent.after
#   child.after
#
# Example:
#
# class Foo
#   @callbacks = RocketJob::Callbacks.new
#
#   # Define callbacks
#   def self.before_perform(&block)
#     @callbacks.before(&block)
#   end
#
#   def self.around_perform(&block)
#     @callbacks.around(&block)
#   end
#
#   def self.after_perform(&block)
#     @callbacks.after(&block)
#   end
#
#   # Execute the callbacks and call the perform method
#   def run
#     @callbacks.call { perform }
#   end
#
#   # Use callbacks
#   before_perform do
#     puts "BEFORE PERFORM1"
#   end
#
#   before_perform do
#     puts "BEFORE PERFORM2"
#   end
#
#   around_perform do |&block|
#     puts "AROUND BEFORE PERFORM1"
#     block.call
#     puts "AROUND AFTER PERFORM1"
#   end
#
#   around_perform do |&block|
#     puts "AROUND BEFORE PERFORM2"
#     block.call
#     puts "AROUND AFTER PERFORM2"
#   end
#
#   after_perform do
#     puts "AFTER PERFORM1"
#   end
#
#   after_perform do
#     puts "AFTER PERFORM2"
#   end
#
#   def perform
#     puts "PERFORM"
#     23
#   end
# end
#
# Foo.new.run
#
# Output from the example above:
#
#   BEFORE PERFORM2
#   BEFORE PERFORM1
#   AROUND BEFORE PERFORM2
#   AROUND BEFORE PERFORM1
#   PERFORM
#   AROUND AFTER PERFORM1
#   AROUND AFTER PERFORM2
#   AFTER PERFORM1
#   AFTER PERFORM2
#
module RocketJob
  class Callbacks
    attr_reader :around_list, :before_list, :after_list

    def initialize
      @around_list = ThreadSafe::Array.new
      @before_list = ThreadSafe::Array.new
      @after_list  = ThreadSafe::Array.new
    end

    # Called by clone()
    def initialize_copy(orig)
      @after_list  = @after_list.dup
      @before_list = @before_list.dup
      @after_list  = @after_list.dup
    end

    def before(&block)
      @before_list.unshift(block)
      self
    end

    def after(&block)
      @after_list.push(block)
      self
    end

    # Nest around blocks
    def around(&block)
      @around_list.push(block)
      self
    end

    # Call the supplied block and all necessary callbacks
    def call(*args, &block)
      @before_list.each { |b| b.call(*args) }
      value = exec_around_callbacks(*args, &block)
      @after_list.each { |a| a.call(*args) }
      value
    end

    # Runs the around blocks
    # &block is the last block to be called
    #
    # TODO: Need to make the around blocks run in the target binding
    def exec_around_callbacks(target, *args, &block)
      if @around_list.size > 0
        last = @around_list.inject(block) { |inner, blk| -> { blk.call(*args, &inner) } }
        last.call
      else
        block.call
      end
    end

  end
end
