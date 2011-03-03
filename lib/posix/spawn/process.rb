module POSIX
  module Spawn
    # POSIX::Spawn::Process includes logic for executing child processes and
    # reading/writing from their standard input, output, and error streams.
    #
    # Create an run a process to completion:
    #
    #   >> process = POSIX::Spawn::Process.new(['git', '--help'])
    #
    # Retrieve stdout or stderr output:
    #
    #   >> process.out
    #   => "usage: git [--version] [--exec-path[=GIT_EXEC_PATH]]\n ..."
    #   >> process.err
    #   => ""
    #
    # Check process exit status information:
    #
    #   >> process.status
    #   => #<Process::Status: pid=80718,exited(0)>
    #
    # POSIX::Spawn::Process is designed to take all input in a single string and
    # provides all output as single strings. It is therefore not well suited
    # to streaming large quantities of data in and out of commands.
    #
    # Q: Why not use popen3 or hand-roll fork/exec code?
    #
    # - It's more efficient than popen3 and provides meaningful process
    #   hierarchies because it performs a single fork/exec. (popen3 double forks
    #   to avoid needing to collect the exit status and also calls
    #   Process::detach which creates a Ruby Thread!!!!).
    #
    # - It's more portable than hand rolled pipe, fork, exec code because
    #   fork(2) and exec(2) aren't available on all platforms. In those cases,
    #   POSIX::Spawn::Process falls back to using whatever janky substitutes the platform
    #   provides.
    #
    # - It handles all max pipe buffer hang cases, which is non trivial to
    #   implement correctly and must be accounted for with either popen3 or
    #   hand rolled fork/exec code.
    class Process
      include POSIX::Spawn

      # Create and execute a new process.
      #
      # argv    - Array of [command, arg1, ...] strings to use as the new
      #           process's argv. When argv is a String, the shell is used
      #           to interpret the command.
      # env     - The new process's environment variables. This is merged with
      #           the current environment as if by ENV.merge(env).
      # options - Additional options:
      #             :input   => str to write str to the process's stdin.
      #             :timeout => int number of seconds before we given up.
      #             :max     => total number of output bytes
      #           A subset of Process::spawn options are also supported on all
      #           platforms:
      #             :chdir => str to start the process in different working dir.
      #
      # Returns a new Process instance that has already executed to completion.
      # The out, err, and status attributes are immediately available.
      def initialize(*argv)
        env, argv, options = extract_process_spawn_arguments(*argv)
        @argv = argv
        @env = env

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

      # Exception raised when the total number of bytes output on the command's
      # stderr and stdout streams exceeds the maximum output size (:max option).
      class MaximumOutputExceeded < StandardError
      end

      # Exception raised when timeout is exceeded.
      class TimeoutExceeded < StandardError
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
        input ||= ''
        max = nil if max && max <= 0
        out, err = '', ''
        offset = 0

        timeout = nil if timeout && timeout <= 0.0
        @runtime = 0.0
        start = Time.now

        writers = [stdin]
        readers = [stdout, stderr]
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
