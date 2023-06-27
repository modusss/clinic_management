require "test_helper"

module ClinicManagement
  class PrescriptionControllerTest < ActionDispatch::IntegrationTest
    include Engine.routes.url_helpers

    test "should get index" do
      get prescription_index_url
      assert_response :success
    end

    test "should get show" do
      get prescription_show_url
      assert_response :success
    end

    test "should get new" do
      get prescription_new_url
      assert_response :success
    end

    test "should get create" do
      get prescription_create_url
      assert_response :success
    end

    test "should get update" do
      get prescription_update_url
      assert_response :success
    end

    test "should get destroy" do
      get prescription_destroy_url
      assert_response :success
    end
  end
end
