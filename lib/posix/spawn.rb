require 'posix_spawn_ext'
require 'posix/spawn/version'
require 'posix/spawn/process'

module POSIX
  module Spawn
    extend self

    # Spawn a child using the best method available.
    #
    # argv - Array of command line arguments passed to exec.
    #
    # Returns the pid of the newly spawned process.
    def spawn(*argv)
      if respond_to?(:_pspawn)
        pspawn(*argv)
      elsif ::Process.respond_to?(:spawn)
        ::Process::spawn(*argv)
      else
        fspawn(*argv)
      end
    end

    # Spawn a child process using posix_spawn.
    #
    # Returns the pid of the newly spawned process.
    # Raises NotImplemented when pfork is not supported on the current platform.
    def pspawn(*argv)
      env, argv, options = extract_process_spawn_arguments(*argv)
      raise NotImplementedError unless respond_to?(:_pspawn)
      _pspawn(env, argv, options)
    end

    # Spawn a child process using a normal fork + exec.
    #
    # Returns the pid of the newly spawned process.
    def fspawn(*argv)
      env, argv, options = extract_process_spawn_arguments(*argv)
      if badopt = options.find{ |key,val| !fd?(key) && ![:chdir,:unsetenv_others].include?(key) }
        raise ArgumentError, "Invalid option: #{badopt[0].inspect}"
      end

      fork do
        begin
          # handle FD => {FD, :close, [file,mode,perms]} options
          options.map do |key, val|
            if fd?(key)
              key = fd_to_io(key)

              if fd?(val)
                val = fd_to_io(val)
                key.reopen(val)
              elsif val == :close
                if key.respond_to?(:close_on_exec=)
                  key.close_on_exec = true
                else
                  key.close
                end
              elsif val.is_a?(Array)
                file, mode_string, perms = *val
                key.reopen(File.open(file, mode_string, perms))
              end
            end
          end

          # setup child environment
          ENV.replace({}) if options[:unsetenv_others] == true
          env.each { |k, v| ENV[k] = v }

          # { :chdir => '/' } in options means change into that dir
          ::Dir.chdir(options[:chdir]) if options[:chdir]

          # do the deed
          ::Kernel::exec(*argv)
        rescue
          exit!(127)
        end
      end
    end

    # Executes a command in a subshell. The command's exit status is
    # available as $?.
    #
    # Returns true if the command returns a zero exit status, or false for non-zero exit.
    def system(*argv)
      pid = spawn(*argv)
      return false if pid <= 0
      ::Process.waitpid(pid)
      $?.exitstatus == 0
    rescue Errno::ENOENT
      false
    end

    # Executes a command in a subshell and returns stdout.
    #
    # Returns the String output of the command.
    def `(cmd)
      r, w = IO.pipe
      pid = spawn(['/bin/sh', '/bin/sh'], '-c', cmd, :out => w, r => :close)

      if pid > 0
        w.close
        out = r.read
        ::Process.waitpid(pid)
        out
      else
        ''
      end
    ensure
      [r, w].each{ |io| io.close rescue nil }
    end

    private

    # Turns the various varargs incantations supported by Process::spawn into a
    # simple [env, argv, options] tuple. This just makes life easier for the
    # extension functions.
    #
    # The following method signature is supported:
    #   Process::spawn([env], command, ..., [options])
    #
    # The env and options hashes are optional. The command may be a variable
    # number of strings or an Array full of strings that make up the new process's
    # argv.
    #
    # Returns an [env, argv, options] tuple. All elements are guaranteed to be
    # non-nil. When no env or options are given, empty hashes are returned.
    def extract_process_spawn_arguments(*args)
      # pop the options hash off the end if it's there
      options =
        if args[-1].respond_to?(:to_hash)
          args.pop.to_hash
        else
          {}
        end
      flatten_process_spawn_options!(options)
      normalize_process_spawn_redirect_file_options!(options)

      # shift the environ hash off the front if it's there and account for
      # possible :env key in options hash.
      env =
        if args[0].respond_to?(:to_hash)
          args.shift.to_hash
        else
          {}
        end
      env.merge!(options.delete(:env)) if options.key?(:env)

      # remaining arguments are the argv supporting a number of variations.
      argv = adjust_process_spawn_argv(args)

      [env, argv, options]
    end

    # Convert { [fd1, fd2, ...] => (:close|fd) } options to individual keys,
    # like: { fd1 => :close, fd2 => :close }. This just makes life easier for the
    # spawn implementations.
    #
    # options - The options hash. This is modified in place.
    #
    # Returns the modified options hash.
    def flatten_process_spawn_options!(options)
      options.to_a.each do |key, value|
        if key.respond_to?(:to_ary)
          key.to_ary.each { |fd| options[fd] = value }
          options.delete(key)
        end
      end
    end

    # Mapping of string open modes to integer oflag versions.
    OFLAGS = {
      "r"  => File::RDONLY,
      "r+" => File::RDWR   | File::CREAT,
      "w"  => File::WRONLY | File::CREAT  | File::TRUNC,
      "w+" => File::RDWR   | File::CREAT  | File::TRUNC,
      "a"  => File::WRONLY | File::APPEND | File::CREAT,
      "a+" => File::RDWR   | File::APPEND | File::CREAT
    }

    # Convert variations of redirecting to a file to a standard tuple.
    #
    # :in   => '/some/file'   => ['/some/file', 'r', 0644]
    # :out  => '/some/file'   => ['/some/file', 'w', 0644]
    # :err  => '/some/file'   => ['/some/file', 'w', 0644]
    # STDIN => '/some/file'   => ['/some/file', 'r', 0644]
    #
    # Returns the modified options hash.
    def normalize_process_spawn_redirect_file_options!(options)
      options.to_a.each do |key, value|
        next if !fd?(key)

        # convert string and short array values to
        if value.respond_to?(:to_str)
          value = default_file_reopen_info(key, value)
        elsif value.respond_to?(:to_ary) && value.size < 3
          defaults = default_file_reopen_info(key, value[0])
          value += defaults[value.size..-1]
        else
          value = nil
        end

        # replace string open mode flag maybe and replace original value
        if value
          value[1] = OFLAGS[value[1]] if value[1].respond_to?(:to_str)
          options[key] = value
        end
      end
    end

    # The default [file, flags, mode] tuple for a given fd and filename. The
    # default flags vary based on the what fd is being redirected. stdout and
    # stderr default to write, while stdin and all other fds default to read.
    #
    # fd   - The file descriptor that is being redirected. This may be an IO
    #        object, integer fd number, or :in, :out, :err for one of the standard
    #        streams.
    # file - The string path to the file that fd should be redirected to.
    #
    # Returns a [file, flags, mode] tuple.
    def default_file_reopen_info(fd, file)
      case fd
      when :in, STDIN, $stdin, 0
        [file, "r", 0644]
      when :out, STDOUT, $stdout, 1
        [file, "w", 0644]
      when :err, STDERR, $stderr, 2
        [file, "w", 0644]
      else
        [file, "r", 0644]
      end
    end

    # Determine whether object is fd-like.
    #
    # Returns true if object is an instance of IO, Fixnum >= 0, or one of the
    # the symbolic names :in, :out, or :err.
    def fd?(object)
      case object
      when Fixnum
        object >= 0
      when :in, :out, :err, STDIN, STDOUT, STDERR, $stdin, $stdout, $stderr, IO
        true
      else
        object.respond_to?(:to_io) && !object.to_io.nil?
      end
    end

    # Convert a fd identifier to an IO object.
    #
    # Returns nil or an instance of IO.
    def fd_to_io(object)
      case object
      when STDIN, STDOUT, STDERR, $stdin, $stdout, $stderr
        object
      when :in, 0
        STDIN
      when :out, 1
        STDOUT
      when :err, 2
        STDERR
      when Fixnum
        object >= 0 ? IO.for_fd(object) : nil
      when IO
        object
      else
        object.respond_to?(:to_io) ? object.to_io : nil
      end
    end

    # Converts the various supported command argument variations into a
    # standard argv suitable for use with exec. This includes detecting commands
    # to be run through the shell (single argument strings with spaces).
    #
    # The args array may follow any of these variations:
    #
    # 'true'                     => [['true', 'true']]
    # 'echo', 'hello', 'world'   => [['echo', 'echo'], 'hello', 'world']
    # 'echo hello world'         => [['/bin/sh', '/bin/sh'], '-c', 'echo hello world']
    # ['echo', 'fuuu'], 'hello'  => [['echo', 'fuuu'], 'hello']
    #
    # Returns a [[cmdname, argv0], argv1, ...] array.
    def adjust_process_spawn_argv(args)
      if args.size == 1 && args[0] =~ /[ |>]/
        # single string with these characters means run it through the shell
        [['/bin/sh', '/bin/sh'], '-c', args[0]]
      elsif !args[0].respond_to?(:to_ary)
        # [argv0, argv1, ...]
        [[args[0], args[0]], *args[1..-1]]
      else
        # [[cmdname, argv0], argv1, ...]
        args
      end
    end
  end
end
