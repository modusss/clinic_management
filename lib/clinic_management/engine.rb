module ClinicManagement
  class Engine < ::Rails::Engine
    isolate_namespace ClinicManagement

    initializer "clinic_management.assets.precompile" do |app|
      app.config.assets.precompile += %w( clinic_management/main.css )
    end
  end
end
