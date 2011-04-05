require 'posix/spawn'

module POSIX
  module Spawn
    # POSIX::Spawn::Child includes logic for executing child processes and
    # reading/writing from their standard input, output, and error streams. It's
    # designed to take all input in a single string and provides all output
    # (stderr and stdout) as single strings and is therefore not well-suited
    # to streaming large quantities of data in and out of commands.
    #
    # Create and run a process to completion:
    #
    #   >> child = POSIX::Spawn::Child.new('git', '--help')
    #
    # Retrieve stdout or stderr output:
    #
    #   >> child.out
    #   => "usage: git [--version] [--exec-path[=GIT_EXEC_PATH]]\n ..."
    #   >> child.err
    #   => ""
    #
    # Check process exit status information:
    #
    #   >> child.status
    #   => #<Process::Status: pid=80718,exited(0)>
    #
    # To write data on the new process's stdin immediately after spawning:
    #
    #   >> child = POSIX::Spawn::Child.new('bc', :input => '40 + 2')
    #   >> child.out
    #   "42\n"
    #
    # Q: Why use POSIX::Spawn::Child instead of popen3, hand rolled fork/exec
    # code, or Process::spawn?
    #
    # - It's more efficient than popen3 and provides meaningful process
    #   hierarchies because it performs a single fork/exec. (popen3 double forks
    #   to avoid needing to collect the exit status and also calls
    #   Process::detach which creates a Ruby Thread!!!!).
    #
    # - It handles all max pipe buffer (PIPE_BUF) hang cases when reading and
    #   writing semi-large amounts of data. This is non-trivial to implement
    #   correctly and must be accounted for with popen3, spawn, or hand rolled
    #   fork/exec code.
    #
    # - It's more portable than hand rolled pipe, fork, exec code because
    #   fork(2) and exec aren't available on all platforms. In those cases,
    #   POSIX::Spawn::Child falls back to using whatever janky substitutes
    #   the platform provides.
    class Child
      include POSIX::Spawn

      # Spawn a new process, write all input and read all output, and wait for
      # the program to exit. Supports the standard spawn interface as described
      # in the POSIX::Spawn module documentation:
      #
      #   new([env], command, [argv1, ...], [options])
      #
      # The following options are supported in addition to the standard
      # POSIX::Spawn options:
      #
      #   :input   => str      Write str to the new process's standard input.
      #   :timeout => int      Maximum number of seconds to allow the process
      #                        to execute before aborting with a TimeoutExceeded
      #                        exception.
      #   :max     => total    Maximum number of bytes of output to allow the
      #                        process to generate before aborting with a
      #                        MaximumOutputExceeded exception.
      #
      # Returns a new Child instance whose underlying process has already
      # executed to completion. The out, err, and status attributes are
      # immediately available.
      def initialize(*args)
        @env, @argv, options = extract_process_spawn_arguments(*args)
        @options = options.dup
        @input = @options.delete(:input)
        @timeout = @options.delete(:timeout)
        @max = @options.delete(:max)
        @options.delete(:chdir) if @options[:chdir].nil?
        exec!
      end

      # All data written to the child process's stdout stream as a String.
      attr_reader :out

      # All data written to the child process's stderr stream as a String.
      attr_reader :err

      # A Process::Status object with information on how the child exited.
      attr_reader :status

      # Total command execution time (wall-clock time)
      attr_reader :runtime

      # Determine if the process did exit with a zero exit status.
      def success?
        @status && @status.success?
      end

    private
      # Execute command, write input, and read output. This is called
      # immediately when a new instance of this object is initialized.
      def exec!
        # spawn the process and hook up the pipes
        pid, stdin, stdout, stderr = popen4(@env, *(@argv + [@options]))

        # async read from all streams into buffers
        @out, @err = read_and_write(@input, stdin, stdout, stderr, @timeout, @max)

        # grab exit status
        @status = waitpid(pid)
      rescue Object => boom
        [stdin, stdout, stderr].each { |fd| fd.close rescue nil }
        if @status.nil?
          ::Process.kill('TERM', pid) rescue nil
          @status = waitpid(pid)      rescue nil
        end
        raise
      ensure
        # let's be absolutely certain these are closed
        [stdin, stdout, stderr].each { |fd| fd.close rescue nil }
      end

      # Maximum buffer size for reading
      BUFSIZE = (32 * 1024)

      # Start a select loop writing any input on the child's stdin and reading
      # any output from the child's stdout or stderr.
      #
      # input   - String input to write on stdin. May be nil.
      # stdin   - The write side IO object for the child's stdin stream.
      # stdout  - The read side IO object for the child's stdout stream.
      # stderr  - The read side IO object for the child's stderr stream.
      # timeout - An optional Numeric specifying the total number of seconds
      #           the read/write operations should occur for.
      #
      # Returns an [out, err] tuple where both elements are strings with all
      #   data written to the stdout and stderr streams, respectively.
      # Raises TimeoutExceeded when all data has not been read / written within
      #   the duration specified in the timeout argument.
      # Raises MaximumOutputExceeded when the total number of bytes output
      #   exceeds the amount specified by the max argument.
      def read_and_write(input, stdin, stdout, stderr, timeout=nil, max=nil)
        max = nil if max && max <= 0
        out, err = '', ''
        offset = 0

        # force all string and IO encodings to BINARY under 1.9 for now
        if out.respond_to?(:force_encoding)
          [stdin, stdout, stderr].each do |fd|
            fd.set_encoding('BINARY', 'BINARY')
          end
          out.force_encoding('BINARY')
          err.force_encoding('BINARY')
          input = input.dup.force_encoding('BINARY') if input
        end

        timeout = nil if timeout && timeout <= 0.0
        @runtime = 0.0
        start = Time.now

        readers = [stdout, stderr]
        writers =
          if input
            [stdin]
          else
            stdin.close
            []
          end
        t = timeout
        while readers.any? || writers.any?
          ready = IO.select(readers, writers, readers + writers, t)
          raise TimeoutExceeded if ready.nil?

          # write to stdin stream
          ready[1].each do |fd|
            begin
              boom = nil
              size = fd.write_nonblock(input)
              input = input[size, input.size]
            rescue Errno::EPIPE => boom
            rescue Errno::EAGAIN, Errno::EINTR
            end
            if boom || input.size == 0
              stdin.close
              writers.delete(stdin)
            end
          end

          # read from stdout and stderr streams
          ready[0].each do |fd|
            buf = (fd == stdout) ? out : err
            begin
              buf << fd.readpartial(BUFSIZE)
            rescue Errno::EAGAIN, Errno::EINTR
            rescue EOFError
              readers.delete(fd)
              fd.close
            end
          end

          # keep tabs on the total amount of time we've spent here
          @runtime = Time.now - start
          if timeout
            t = timeout - @runtime
            raise TimeoutExceeded if t < 0.0
          end

          # maybe we've hit our max output
          if max && ready[0].any? && (out.size + err.size) > max
            raise MaximumOutputExceeded
          end
        end

        [out, err]
      end

      # Wait for the child process to exit
      #
      # Returns the Process::Status object obtained by reaping the process.
      def waitpid(pid)
        ::Process::waitpid(pid)
        $?
      end
    end
  end
end

# On JRuby, there is no easy way to use posix_spawn(2) with i/o redirection,
# since java IO objects cannot be translated to native file descriptors.
#
# Instead, we use The Java Way and spawn up three threads to handle stdin, out
# and err. These threads use standard blocking i/o and run in parallel to avoid
# the PIPE_BUF deadlock problem.
#
# The only caveat with this approach is that there is no clean way to kill these
# threads in the case of a timeout or max output error. JRuby's Thread#kill does
# not interrupt blocking i/o calls, so it is useless here. Java's #interrupt
# does work, but also closes the underlying i/o object on interrupt. This
# confuses IO.popen4 when it tries to clean up after the process.
#
# So, instead of trying to clean up the threads, we simply kill the underlying
# process. The dead process surfaces an EPIPE to the worker threads and they die
# gracefully. However, if the process ignores our SIGTERM or refuses to die, we
# will deadlock.
if defined? JRUBY_VERSION
  class POSIX::Spawn::Child
    def exec!
      # Update the environment.
      if @env
        env = ENV
        ENV.replace(env.merge(@env))
      end

      # Switch directories.
      if chdir = @options[:chdir]
        dir = Dir.pwd
        Dir.chdir(chdir)
      end

      # Translate [['echo','echo'], 'abc'] into ['echo', 'abc'].
      @argv[0] = @argv[0].first if @argv[0].is_a?(Array)

      # Must use the block form of IO.popen4 due to JRUBY-5684
      IO.popen4(*@argv) do |pid, stdin, stdout, stderr|
        @pid = pid
        @out, @err = read_and_write(@input, stdin, stdout, stderr, @timeout, @max)
      end

      # At the end of the block above, JRuby will call Process.waitpid for us
      # and set $? accordingly.
      @status = $?
    ensure
      ENV.replace(env) if @env
      Dir.chdir(dir) if @options[:chdir]
    end

    def read_and_write(input, stdin, stdout, stderr, timeout=nil, max=nil)
      max = nil if max && max <= 0
      out, err = '', ''
      offset = 0

      # force all string and IO encodings to BINARY under 1.9 for now
      if out.respond_to?(:force_encoding)
        [stdin, stdout, stderr].each do |fd|
          fd.set_encoding('BINARY', 'BINARY')
        end
        out.force_encoding('BINARY')
        err.force_encoding('BINARY')
        input = input.dup.force_encoding('BINARY') if input
      end

      timeout = nil if timeout && timeout <= 0.0
      @runtime = 0.0
      start = Time.now

      threads = []

      if input
        threads << Thread.new do
          begin
            while input and input.size > 0
              bytes = stdin.write(input)
              input = input[bytes+1, -1]
            end
          rescue Errno::EPIPE
          ensure
            stdin.close rescue nil
          end
        end
      else
        stdin.close
      end

      {stdout => out, stderr => err}.each do |stream, buf|
        threads << Thread.new do
          while true
            begin
              buf << stream.readpartial(BUFSIZE)

              if max && (out.size + err.size) > max
                # Killing the process is the only way to signal the other
                # threads that are blocking on read/writes.
                kill
                raise MaximumOutputExceeded
              end
            rescue EOFError, Errno::EPIPE
              break
            end
          end
        end
      end

      boom = nil

      if timeout
        while timeout > 0
          sleep(0.1)
          timeout -= 0.1

          # Poll to see if the process is dead yet.
          break if threads.all?{ |th| !th.alive? }
          # begin
          #   Process.kill(0, @pid)
          # rescue Errno::ESRCH
          #   # Process is gone.
          #   break
          # end
        end

        if threads.find{ |th| th.alive? }
          # Found atleast one thread still working. Kill the process to
          # release the worker threads.
          kill
          boom = TimeoutExceeded.new
        end
      end

      threads.each do |th|
        begin
          th.join
        rescue => boom
          # Catch the MaximumOutputExceeded and re-raise it below.
        end
      end

      @runtime = Time.now - start

      [out, err]
    ensure
      raise(boom) if boom
    end
  end

  private

  def kill
    ::Process.kill('TERM', @pid)
  rescue Errno::ESRCH
  end
end
