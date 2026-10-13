# frozen_string_literal: true

require "test_helper"

class ClinicManagement::ServicesStatsHelperTest < ActionView::TestCase
  include ClinicManagement::ServicesStatsHelper

  test "services_conversion_rate returns zero when denominator is zero" do
    assert_equal 0.0, services_conversion_rate(5, 0)
  end

  test "services_conversion_rate calculates percentage with one decimal" do
    assert_equal 52.6, services_conversion_rate(41, 78)
    assert_equal 14.7, services_conversion_rate(41, 279)
  end

  test "services_attendance_rate_tone follows funnel thresholds" do
    assert_equal "red", services_attendance_rate_tone(28.0)
    assert_equal "orange", services_attendance_rate_tone(34.4)
    assert_equal "green", services_attendance_rate_tone(56.8)
  end

  test "services_final_rate_tone uses lower compound funnel thresholds" do
    assert_equal "red", services_final_rate_tone(8.0)
    assert_equal "orange", services_final_rate_tone(14.7)
    assert_equal "green", services_final_rate_tone(24.7)
  end

  test "service_day_metrics computes operational breakdown and respects referral filter" do
    lead_record = Struct.new(:name).new("Paciente Lead")
    inv_a = Struct.new(:patient_name).new("Maria")
    inv_b = Struct.new(:patient_name).new("João")
    inv_c = Struct.new(:patient_name).new("Ana")
    inv_d = Struct.new(:patient_name).new("Carlos")

    ap_present = Struct.new(:invitation, :lead, :status, :confirmed, :attendance, :referral_code)
                       .new(inv_a, lead_record, "agendado", true, true, "REF1")
    ap_waiting = Struct.new(:invitation, :lead, :status, :confirmed, :attendance, :referral_code)
                       .new(inv_b, lead_record, "agendado", true, false, "REF1")
    ap_canceled = Struct.new(:invitation, :lead, :status, :confirmed, :attendance, :referral_code)
                        .new(inv_c, lead_record, "cancelado", false, false, "REF1")
    ap_rescheduled = Struct.new(:invitation, :lead, :status, :confirmed, :attendance, :referral_code)
                           .new(inv_d, lead_record, "remarcado", false, false, "REF2")

    service = Struct.new(:date, :appointments).new(
      Date.current,
      [ap_present, ap_waiting, ap_canceled, ap_rescheduled]
    )

    metrics = service_day_metrics([service])
    assert_equal 4, metrics[:total]
    assert_equal 2, metrics[:active]
    assert_equal 2, metrics[:confirmed]
    assert_equal 2, metrics[:confirmed_active]
    assert_equal 50.0, metrics[:confirmation_rate]
    assert_equal 1, metrics[:attended]
    assert_equal 50.0, metrics[:attendance_rate]
    assert_equal 1, metrics[:pending_or_absent]
    assert_equal "Aguardando", metrics[:pending_label]
    assert_equal 1, metrics[:rescheduled]
    assert_equal 1, metrics[:canceled]

    referral = Struct.new(:code).new("REF1")
    scoped = service_day_metrics([service], referral: referral)
    assert_equal 3, scoped[:total]
    assert_equal 2, scoped[:active]
    assert_equal 0, scoped[:rescheduled]
    assert_equal 1, scoped[:canceled]
  end
end
