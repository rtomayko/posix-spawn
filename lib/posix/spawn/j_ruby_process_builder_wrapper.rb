require 'java'
require 'stringio'
require 'delegate'

module ::Process
  class JRubyPid < SimpleDelegator
    attr_accessor :jruby_process
  end
  def self.jruby_pid(process)
    f = process.getClass.getDeclaredField("pid")
    f.setAccessible(true)
    pid = f.get(process)
    raise "posix_spawn: Could not determine PID" unless pid.kind_of?(Fixnum) && pid > 0
    pid = JRubyPid.new(pid)
    pid.jruby_process = process
    pid
  end

  class << self
    alias_method :orig_wait, :wait
    alias_method :orig_waitpid, :waitpid

    def wait(*args)
      if args.first.respond_to?(:jruby_process)
        waitpid(*args)
      else
        orig_wait(*args)
      end
    end

    def waitpid(*args)
      if args.first.respond_to?(:jruby_process)
        exitstatus = args.first.jruby_process.waitFor
        $?.singleton_class.send :define_method, :to_i do
          exitstatus
        end
        class << $?
          def success?
            to_i == 0
          end

          def exitstatus
            to_i
          end
        end
        args.first
      else
        orig_waitpid(*args)
      end
    end
  end
end

class POSIX::Spawn::JRubyProcessBuilderWrapper
  def self.spawn(*args)
    env = args[0].kind_of?(Hash) ? args.shift : {}
    options = args[-1].kind_of?(Hash) ? args.pop : {}
    wrapper = self.new(*args)
    if chdir = options.delete(:chdir)
      wrapper.directory = chdir
    end
    env.each_pair { |k, v| wrapper.environment.put(k.to_s, v.to_s) }

    # options
    stdin = options.delete(:in)
    stdout = options.delete(:out)
    stderr = options.delete(:err)
    close_fds = []
    options.delete_if do |k, v|
      if v == :close
        close_fds << k
        true
      end
    end

    raise ArgumentError, "spawn: unsupported options " + options.keys.map(&:to_s).join(', ') unless options.empty?
    raise ArgumentError, "only ruby IO supported" if [stdin, stdout, stderr].compact.find { |fd| !fd.kind_of?(IO) }
    raise ArgumentError, "cannot use same IO multiple times" if [stdin, stdout, stderr].compact.uniq != [stdin, stdout, stderr].compact
    wrapper.start_spawn(stdin, stdout, stderr, close_fds)
  end

  def initialize(*args)
    args = [args[0][0], *args[1, args.length-1]] if args[0].kind_of?(Array) && args[0].size == 2
    if args.size == 1 && args.first.kind_of?(String)
      args = ['sh', '-c', args.first]
    end
    raise ArgumentError if args.find { |arg| !arg.kind_of?(String) }
    @pb = java.lang.ProcessBuilder.new(java.util.ArrayList.new(args))
    @pb.redirectErrorStream(false)
  end

  def directory
    @pb.directory().path
  end

  def directory=(value)
    @pb.directory(java.io.File.new(value))
  end

  def environment
    @pb.environment
  end

  def start_spawn(stdin, stdout, stderr, close_fds)
    begin
      @process = @pb.start
    rescue java.io.IOException
      raise Errno::ENOENT
    end
    close_fds.each do |fd|
      class << fd
        def write_nonblock(*args)
          write(*args)
        end
      end
    end
    threads = [redirect_input(@process.getOutputStream, stdin),
      redirect_output(@process.getInputStream, stdout),
      redirect_output(@process.getErrorStream, stderr)]
    process = @process
    start_thread do
      sleep(0.05) while close_fds.map(&:closed?).include?(false)
      [stdin, stdout, stderr].each { |fd| fd.close if fd }
      sleep 0.1
      threads.compact.each { |thread| thread.terminate if thread.alive? }
      if false
        begin
          process.exitValue
        rescue java.lang.IllegalThreadStateException
          sleep 0.5
          system("pkill -9 -P " + ::Process.jruby_pid(@process).to_s)
        end
      end
    end
    ::Process.jruby_pid(@process)
  end

  def start
    process = @pb.start
    connectOutputStream(process.getOutputStream) do |sin|
      connectInputStream(process.getInputStream) do |sout|
        connectInputStream(process.getErrorStream) do |serr|
          yield(process, sin, sout, serr)
        end
      end
    end
  end

private
  def connectInputStream(stream)
    is = java.io.InputStreamReader.new(stream)
    br = java.io.BufferedReader.new(is)
    yield(br).tap { br.close }
  end

  def connectOutputStream(stream)
    ow = java.io.OutputStreamWriter.new(stream)
    bw = java.io.BufferedWriter.new(ow)
    yield(bw).tap { bw.close }
  end

  def patchRubyIoClose(ruby_io)
    return unless ruby_io
    class << ruby_io
      alias_method :_close, :close
      def close
      end
    end
  end

  def redirect_input(java_io, ruby_io)
    return unless ruby_io
    patchRubyIoClose(ruby_io)
    start_thread do
      begin
        isr = java.io.OutputStreamWriter.new(java_io)
        br = java.io.BufferedWriter.new(isr)
        begin
          ruby_io.each_char do |data|
            begin
              br.write(data, 0, data.size)
            rescue java.io.IOException # java.io.IOException: Broken pipe
              break
            end
          end
        rescue EOFError
        end
      ensure
        ruby_io._close
        begin
          br.close
        rescue java.io.IOException
        end
        isr.close
        java_io.close
      end
    end
  end

  def redirect_output(java_io, ruby_io)
    return unless ruby_io
    patchRubyIoClose(ruby_io)
    start_thread do
      begin
        isr = java.io.InputStreamReader.new(java_io)
        br = java.io.BufferedReader.new(isr)
        while (char = br.read) != -1
          begin
            ruby_io.putc(char)
          rescue IOError, Errno::EPIPE
            break
          end
        end
      ensure
        ruby_io._close rescue nil
        begin
          br.close
        rescue java.io.IOException
        end
        isr.close
        java_io.close
      end
    end
  end

  def start_thread(&block)
    Thread.new(&block)
  end
end
