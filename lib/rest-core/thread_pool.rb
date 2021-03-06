
# reference implementation: puma
# https://github.com/puma/puma/blob/v2.7.1/lib/puma/thread_pool.rb

require 'thread'
require 'rest-core'

class RestCore::ThreadPool
  include RestCore

  class Queue
    def initialize
      @queue = []
      @mutex = Mutex.new
      @condv = ConditionVariable.new
    end

    def << task
      mutex.synchronize do
        queue << task
        condv.signal
      end
    end

    def pop timeout=60
      mutex.synchronize do
        if queue.empty?
          condv.wait(mutex, timeout)
          queue.shift || lambda{ |_| false } # shutdown idle workers
        else
          queue.shift
        end
      end
    end

    def clear
      queue.clear
    end

    protected
    attr_reader :queue, :mutex, :condv
  end

  class Task < Struct.new(:job, :mutex, :thread, :cancelled)
    # this should never fail
    def call working_thread
      mutex.synchronize do
        return if cancelled
        self.thread = working_thread
      end
      job.call
      true
    end

    def cancel
      self.cancelled = true
    end
  end

  def self.[] client_class
    (@pools ||= {})[client_class] ||= new(client_class)
  end

  attr_reader :client_class

  def initialize client_class
    @client_class = client_class
    @queue        = Queue.new
    @mutex        = Mutex.new
    @workers      = []
    @waiting      = 0
  end

  def inspect
    "#<#{self.class.name} client_class=#{client_class}>"
  end

  def size
    workers.size
  end

  def max_size
    client_class.pool_size
  end

  def idle_time
    client_class.pool_idle_time
  end

  def defer mutex=nil, &job
    task = Task.new(job, mutex)
    queue << task
    spawn_worker if waiting == 0 && workers.size < max_size
    task
  end

  def trim force=false
    queue << lambda{ |_| false } if force || waiting > 0
  end

  # Block on shutting down, and should not add more jobs while shutting down
  def shutdown
    workers.size.times{ trim(true) }
    workers.first.join && trim(true) until workers.empty?
    queue.clear
  end

  protected
  attr_reader :queue, :mutex, :condv, :workers, :waiting

  private
  def spawn_worker
    workers << Thread.new{
      Thread.current.abort_on_exception = !!$DEBUG

      task = nil
      begin
        mutex.synchronize{ @waiting += 1 }
        task = queue.pop(idle_time)
        mutex.synchronize{ @waiting -= 1 }
      end while task.call(Thread.current)

      mutex.synchronize{ workers.delete(Thread.current) }
    }
  end
end
