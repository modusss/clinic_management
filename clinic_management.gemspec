require_relative "lib/clinic_management/version"

Gem::Specification.new do |spec|
  spec.name        = "clinic_management"
  spec.version     = ClinicManagement::VERSION
  spec.authors     = ["fillype"]
  spec.email       = ["fillype1@hotmail.com"]
  spec.homepage    = "https://www.lipepay.com"
  spec.summary     = "Some summary."
  spec.description = "Some description."
  
  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the "allowed_push_host"
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://www.lipepay.com"
  spec.metadata["changelog_uri"] = "https://www.lipepay.com"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 7.0.3"
end
