module ClinicManagement
  class Engine < ::Rails::Engine
    isolate_namespace ClinicManagement

    initializer "clinic_management.assets.precompile" do |app|
      app.config.assets.precompile += %w( clinic_management/main.css )
    end

    # ESSENTIAL: Refresh cached service sales metrics when retail orders/payments change.
    initializer "clinic_management.service_statistics_hooks" do
      ActiveSupport.on_load(:active_record) do
        if defined?(Order)
          Order.after_commit lambda { |record|
            ClinicManagement::ServiceStatistics::Refresher.enqueue_for_customer(record.customer_id)
          }, on: %i[create update]
        end

        if defined?(EarlyPayment)
          EarlyPayment.after_commit lambda { |record|
            customer_id = record.order&.customer_id
            ClinicManagement::ServiceStatistics::Refresher.enqueue_for_customer(customer_id)
          }, on: %i[create update]
        end

        if defined?(PickupPayment)
          PickupPayment.after_commit lambda { |record|
            customer_id = record.order&.customer_id
            ClinicManagement::ServiceStatistics::Refresher.enqueue_for_customer(customer_id)
          }, on: %i[create update]
        end

        if defined?(Installment)
          Installment.after_commit lambda { |record|
            customer_id = record.payment_book&.order&.customer_id
            ClinicManagement::ServiceStatistics::Refresher.enqueue_for_customer(customer_id)
          }, on: %i[create update]
        end
      end
    end
  end
end
