lib = "devdigest"
lib_file = File.expand_path("../lib/#{lib}.rb", __FILE__)
File.read(lib_file) =~ /\bVERSION\s*=\s*["'](.+?)["']/
version = $1

Gem::Specification.new do |spec|
  spec.name        = lib
  spec.version     = version

  spec.summary     = "A daily digest for development teams."
  spec.description = "A daily digest for development teams."

  spec.authors     = ["Pedro Belo"]
  spec.email       = "pedro@heroku.com"
  spec.homepage    = "https://github.com/pedro/devdigest"
  spec.license     = "MIT"

  spec.add_dependency "github_api", "~> 0.8.9"
  spec.add_dependency "netrc",      "~> 0.7.7"

  spec.files = %w(Gemfile README.md)
  spec.files << "#{lib}.gemspec"
  spec.files += Dir.glob("man/*")
  spec.files += Dir.glob("lib/**/*.rb")

  dev_null    = File.exist?("/dev/null") ? "/dev/null" : "NUL"
  git_files   = `git ls-files -z 2>#{dev_null}`
  spec.files &= git_files.split("\0") if $?.success?

  spec.executables << "devdigest"
end
