module POSIX
  module Spawn
    module Util
      extend self

      def win?
        @win ||= RUBY_PLATFORM =~ /(mswin|mingw|cygwin|bccwin)/
      end

      def bin_sh
        win? ? 'sh' : '/bin/sh'
      end

      def null
        win? ? 'NUL' : '/dev/null'
      end
    end
  end
end
