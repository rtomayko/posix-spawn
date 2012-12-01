require 'test/unit'
require 'posix-spawn'

if POSIX::Spawn::Util.win?
  if Module.const_defined?(:MiniTest)
    puts "Patching MiniTest"
    module Test
      module Unit
        class Runner
          remove_method :puke
          def puke klass, meth, e
            e = case e
                when NotImplementedError, MiniTest::Skip then
                  @skips += 1
                  return "S" unless @verbose
                  "Skipped:\n#{meth}(#{klass}) [#{location e}]:\n#{e.message}\n"
                when MiniTest::Assertion then
                  @failures += 1
                  "Failure:\n#{meth}(#{klass}) [#{location e}]:\n#{e.message}\n"
                else
                  @errors += 1
                  bt = MiniTest::filter_backtrace(e.backtrace).join "\n    "
                  "Error:\n#{meth}(#{klass}):\n#{e.class}: #{e.message}\n    #{bt}\n"
                end
            @report << e
            e[0, 1]
          end
        end
      end
    end
  else
    # TODO
  end
end
      