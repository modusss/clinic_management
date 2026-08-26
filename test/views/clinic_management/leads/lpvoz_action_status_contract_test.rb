# frozen_string_literal: true

require "test_helper"

class LpvozActionStatusContractTest < ActiveSupport::TestCase
  self.fixture_table_names = []

  test "active operations opt in to isolated status polling" do
    source = ClinicManagement::Engine.root.join(
      "app/views/clinic_management/leads/_lpvoz_action.html.erb"
    ).read

    assert_includes source, 'lpvoz-operation-#{operation.public_id}'
    assert_includes source, 'data-controller="lpvoz-operation-status"'
    assert_includes source, "%w[queued dispatching accepted in_progress]"
  end
end
