require 'jruby'
require 'delegate'

module ::Process
  class JRubyPid < SimpleDelegator
    java_import org.jruby.util.ShellLauncher

    attr_reader :jruby_process

    def initialize(process)
      super(ShellLauncher.reflectPidFromProcess(process))
      @jruby_process = process
    end
  end

  class << self
    alias_method :orig_wait, :wait
    alias_method :orig_waitpid, :waitpid

    def wait(*args)
      if args.first.respond_to?(:jruby_process)
        javaWaitFor(args.first)
      else
        orig_wait(*args)
      end
    end

    def waitpid(*args)
      if args.first.respond_to?(:jruby_process)
        javaWaitFor(args.first)
      else
        orig_waitpid(*args)
      end
    end

  private
    def javaWaitFor(javaPid)
      pid = javaPid.__getobj__
      exitstatus = javaPid.jruby_process.waitFor
      # set $?
      JRuby.runtime.getCurrentContext.setLastExitStatus(
        org.jruby.RubyProcess::RubyStatus.newProcessStatus(JRuby.runtime,
        exitstatus, pid))
      pid
    end
  end
end

class POSIX::Spawn::JRuby
  class << self
    java_import org.jruby.util.ShellLauncher
    java_import org.jruby.runtime.builtin.IRubyObject
    java_import java.io.InputStreamReader
    java_import java.io.BufferedReader
    java_import java.io.OutputStreamWriter
    java_import java.io.BufferedWriter

    LaunchConfig = ShellLauncher::LaunchConfig
    JFile = java.io.File

    def spawn(*args)
      # unsupported options: :pgroup, :new_pgroup, :rlimit_, :umask, :close_others
      # IO redirection except for :in, :out, :err
      runtime = JRuby.runtime

      env = args[0].kind_of?(Hash) ? args.shift : {}
      options = args[-1].kind_of?(Hash) ? args.pop : {}
      chdir = options.delete(:chdir)
      chdir ||= runtime.getCurrentDirectory

      env = ENV.merge(env) unless options[:unsetenv_others]

      # redirection
      stdin = options.delete(:in)
      stdout = options.delete(:out)
      stderr = options.delete(:err)

      # FD => :close has no effect, since we are not forking
      options.delete_if { |k, v| v == :close }

      raise ArgumentError, "spawn: unsupported options " + options.keys.map(&:to_s).join(', ') unless options.empty?

      start(runtime, chdir, env, args, stdin, stdout, stderr)
    end

    def start(runtime, pwd, env, args, stdin, stdout, stderr)
      pwd = JFile.new(pwd)
      argEnv = env.each_pair.map { |k, v| "#{k}=#{v}" }.to_java(:string)
      # TODO: support [[,], ...]
      args[0] = args[0][0] if args[0].is_a?(Array)
      rawArgs = args.to_java(IRubyObject)

      cfg = LaunchConfig.new(runtime, rawArgs, true)

      if cfg.shouldRunInShell
        cfg.verifyExecutableForShell
      else
        cfg.verifyExecutableForDirect
      end

      aProcess = ShellLauncher.buildProcess(runtime,
        cfg.getExecArgs, argEnv, pwd)

      handleStreamsNonblocking(aProcess, stdin, stdout, stderr)
      Process::JRubyPid.new(aProcess)
    end

  private
    def handleStreamsNonblocking(process, stdin, stdout, stderr)
      [stdin, stdout, stderr].each { |io| patchIO(io) }
      Pump.new(stdin.to_inputstream, process.getOutputStream)
      Pump.new(process.getInputStream, stdout.to_outputstream)
      Pump.new(process.getErrorStream, stderr.to_outputstream)
    end

    def patchIO(ruby_io)
      if ruby_io
        class << ruby_io
          alias_method :_close, :close
          define_method(:close) { }
        end
      end
    end

    class Pump < Thread
      def initialize(input, output)
        if output
          @input = input
          @output = output
          super(&method(:main))
        else
          close_stream(input)
        end
      end

    private
      def main
        while (char = @input.read) != -1
          @output.write(char)
        end
      rescue IOError, Errno::EPIPE, java.io.IOException
      ensure
        close_stream(@output)
        close_stream(@input)
      end

      def close_stream(stream)
        stream.respond_to?(:_close) ? stream._close : stream.close
      rescue
      end
    end
  end
end
