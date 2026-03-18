require "test_helper"

module ClinicManagement
  class RegionsControllerTest < ActionDispatch::IntegrationTest
    include Engine.routes.url_helpers

    setup do
      @region = clinic_management_regions(:one)
    end

    test "should get index" do
      get regions_url
      assert_response :success
    end

    test "should get new" do
      get new_region_url
      assert_response :success
    end

    test "should create region" do
      assert_difference("Region.count") do
        post regions_url, params: { region: { name: @region.name } }
      end

      assert_redirected_to regions_url
    end

    test "should show region" do
      get region_url(@region)
      assert_response :success
    end

    test "should get edit" do
      get edit_region_url(@region)
      assert_response :success
    end

    test "should update region" do
      patch region_url(@region), params: { region: { name: @region.name } }
      assert_redirected_to region_url(@region)
    end

    test "should destroy region" do
      delete region_url(@region)
      assert_redirected_to regions_url

      # With invitations: soft delete (deleted_at set). Without: hard delete (record removed).
      if @region.invitations.any?
        assert Region.unscoped.find(@region.id).deleted?, "Region with invitations should be soft-deleted"
      else
        assert_nil Region.find_by(id: @region.id), "Region without invitations should be hard-deleted"
      end
    end
  end
end
