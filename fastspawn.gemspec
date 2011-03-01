Gem::Specification.new do |s|
  s.name = 'fastspawn'
  s.version = '0.2.0'
  s.summary = "Fast process spawner"
  s.date = '2011-02-28'
  s.email = 'r@tomayko.com'
  s.homepage = 'http://github.com/rtomayko/fastspawn'
  s.has_rdoc = false
  s.authors = ["Ryan Tomayko", "Aman Gupta"]
  # = MANIFEST =
  s.files = %w[
    COPYING
    HACKING
    README
    Rakefile
    bin/fastspawn-bm
    ext/extconf.rb
    ext/fastspawn.c
    fastspawn.gemspec
    lib/fastspawn.rb
    lib/fastspawn/process.rb
    test/test_fastspawn.rb
    test/test_fastspawn_process.rb
  ]
  # = MANIFEST =
  s.test_files = []
  s.extra_rdoc_files = ["COPYING"]
  s.extensions = ["ext/extconf.rb"]
  s.executables = []
  s.require_paths = ["lib"]
end
