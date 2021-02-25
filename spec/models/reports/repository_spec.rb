require "rails_helper"

RSpec.describe Reports::Repository, type: :model do
  let(:organization) { create(:organization, name: "org-1") }
  let(:user) { create(:admin, :manager, :with_access, resource: organization, organization: organization) }
  let(:facility_group_1) { FactoryBot.create(:facility_group, name: "facility_group_1", organization: organization) }

  let(:june_1_2018) { Time.parse("June 1, 2018 00:00:00+00:00") }
  let(:june_1_2020) { Time.parse("June 1, 2020 00:00:00+00:00") }
  let(:june_30_2020) { Time.parse("June 30, 2020 00:00:00+00:00") }
  let(:july_2020) { Time.parse("July 15, 2020 00:00:00+00:00") }
  let(:jan_2019) { Time.parse("January 1st, 2019 00:00:00+00:00") }
  let(:jan_2020) { Time.parse("January 1st, 2020 00:00:00+00:00") }
  let(:july_2018) { Time.parse("July 1st, 2018 00:00:00+00:00") }
  let(:july_2020) { Time.parse("July 1st, 2020 00:00:00+00:00") }

  def refresh_views
    ActiveRecord::Base.transaction do
      LatestBloodPressuresPerPatientPerMonth.refresh
      LatestBloodPressuresPerPatientPerQuarter.refresh
      PatientRegistrationsPerDayPerFacility.refresh
    end
  end

  context "counts and rates" do
    it "gets assigned patient counts for single region" do
      facilities = FactoryBot.create_list(:facility, 2, facility_group: facility_group_1).sort_by(&:slug)
      facility_1, facility_2 = facilities.take(2)

      _facility_1_registered = create_list(:patient, 2, full_name: "controlled", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)
      create_list(:patient, 2, full_name: "controlled", recorded_at: jan_2019.advance(months: -4), assigned_facility: facility_1, registration_user: user)
      _facility_2_registered = create(:patient, full_name: "other facility", recorded_at: jan_2019, assigned_facility: facility_2, registration_user: user)

      repo = Reports::Repository.new(facility_1.region, periods: jan_2019.to_period)
      expected = {
        facility_1.slug => {
          jan_2019.to_period => 2
        }
      }
      expect(repo.assigned_patients_count).to eq(expected)
    end

    it "gets controlled counts and rates for single region" do
      facilities = FactoryBot.create_list(:facility, 2, facility_group: facility_group_1).sort_by(&:slug)
      facility_1, facility_2 = facilities.take(2)
      facility_1_controlled = create_list(:patient, 2, full_name: "controlled", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)
      facility_1_uncontrolled = create_list(:patient, 2, full_name: "uncontrolled", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)
      facility_2_controlled = create(:patient, full_name: "other facility", recorded_at: jan_2019, assigned_facility: facility_2, registration_user: user)
      Timecop.freeze(jan_2020) do
        (facility_1_controlled << facility_2_controlled).map do |patient|
          create(:blood_pressure, :under_control, facility: facility_1, patient: patient, recorded_at: 15.days.ago, user: user)
        end
        facility_1_uncontrolled.map do |patient|
          create(:blood_pressure, :hypertensive, facility: facility_1, patient: patient, recorded_at: 15.days.ago)
        end
      end
      refresh_views

      expected_counts = {
        facility_1.slug => {
          jan_2020.to_period => 2
        }
      }
      expected_rates = {
        facility_1.slug => {
          jan_2020.to_period => 50
        }
      }
      repo = Reports::Repository.new(facility_1.region, periods: jan_2020.to_period)
      (jan_2019.to_period..jan_2020.to_period).each do |period|
        expect(repo.cumulative_assigned_patients_count[facility_1.region.slug][period]).to eq(4)
      end
      expect(repo.controlled_patients_count).to eq(expected_counts)
      expect(repo.controlled_patient_rates).to eq(expected_rates)
    end

    it "gets controlled counts and rates for one month" do
      facilities = FactoryBot.create_list(:facility, 3, facility_group: facility_group_1).sort_by(&:slug)
      facility_1, facility_2, facility_3 = *facilities.take(3)
      regions = facilities.map(&:region)

      facility_1_controlled = create_list(:patient, 2, full_name: "controlled", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)
      facility_1_uncontrolled = create_list(:patient, 2, full_name: "uncontrolled", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)
      facility_2_controlled = create(:patient, full_name: "other facility", recorded_at: jan_2019, assigned_facility: facility_2, registration_user: user)

      Timecop.freeze(jan_2020) do
        (facility_1_controlled << facility_2_controlled).map do |patient|
          create(:blood_pressure, :under_control, facility: facility_1, patient: patient, recorded_at: 15.days.ago, user: user)
        end
        facility_1_uncontrolled.map do |patient|
          create(:blood_pressure, :hypertensive, facility: facility_1, patient: patient, recorded_at: 15.days.ago)
        end
      end

      refresh_views

      jan = Period.month(jan_2020)
      repo = Reports::Repository.new(regions, periods: Period.month(jan))
      controlled = repo.controlled_patients_count
      uncontrolled = repo.uncontrolled_patients_count
      expect(controlled[facility_1.slug].fetch(jan)).to eq(2)
      expect(controlled[facility_2.slug].fetch(jan)).to eq(1)
      expect(controlled[facility_3.slug].fetch(jan)).to eq(0)
      expect(uncontrolled[facility_1.slug].fetch(jan)).to eq(2)
      expect(uncontrolled[facility_2.slug].fetch(jan)).to eq(0)
      expect(uncontrolled[facility_3.slug].fetch(jan)).to eq(0)
    end

    it "gets controlled info for range of month periods" do
      facilities = FactoryBot.create_list(:facility, 3, facility_group: facility_group_1)
      facility_1, facility_2, facility_3 = *facilities.take(3)
      regions = facilities.map(&:region)

      controlled_in_jan_and_june = create_list(:patient, 2, full_name: "controlled", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)
      uncontrolled_in_jan = create_list(:patient, 2, full_name: "uncontrolled", recorded_at: jan_2019, assigned_facility: facility_2, registration_user: user)
      controlled_just_for_june = create(:patient, full_name: "just for june", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)
      patient_from_other_facility = create(:patient, full_name: "other facility", recorded_at: jan_2019, assigned_facility: create(:facility), registration_user: user)

      Timecop.freeze(jan_2020) do
        controlled_in_jan_and_june.map do |patient|
          create(:blood_pressure, :hypertensive, facility: facility_1, patient: patient, recorded_at: 3.days.from_now, user: user)
          create(:blood_pressure, :under_control, facility: facility_1, patient: patient, recorded_at: 4.days.from_now, user: user)
        end
        uncontrolled_in_jan.map { |patient| create(:blood_pressure, :hypertensive, facility: facility_2, patient: patient, recorded_at: 4.days.from_now) }
        create(:blood_pressure, :under_control, facility: patient_from_other_facility.assigned_facility, patient: patient_from_other_facility, recorded_at: 4.days.from_now)
      end

      Timecop.freeze(june_1_2020) do
        controlled_in_jan_and_june.map do |patient|
          create(:blood_pressure, :under_control, facility: facility_1, patient: patient, recorded_at: 2.days.ago, user: user)
          create(:blood_pressure, :hypertensive, facility: facility_1, patient: patient, recorded_at: 4.days.ago, user: user)
          create(:blood_pressure, :hypertensive, facility: facility_1, patient: patient, recorded_at: 35.days.ago, user: user)
        end

        create(:blood_pressure, :under_control, facility: facility_3, patient: controlled_just_for_june, recorded_at: 4.days.ago, user: user)

        uncontrolled_in_june = create_list(:patient, 5, recorded_at: 4.months.ago, assigned_facility: facility_1, registration_user: user)
        uncontrolled_in_june.map do |patient|
          create(:blood_pressure, :hypertensive, facility: facility_1, patient: patient, recorded_at: 1.days.ago, user: user)
          create(:blood_pressure, :under_control, facility: facility_1, patient: patient, recorded_at: 2.days.ago, user: user)
        end
      end

      refresh_views

      start_range = july_2020.advance(months: -24)
      range = (Period.month(start_range)..Period.month(july_2020))
      repo = Reports::Repository.new(regions, periods: range)
      result = repo.controlled_patients_count

      facility_1_results = result[facility_1.slug]
      controlled_periods = [jan_2020.to_period.advance(months: 2), june_1_2020.to_period.advance(months: 2)]
      range.each do |period|
        expect(facility_1_results[period]).to_not be_nil
      end
      expect(facility_1_results[Period.month(jan_2020)]).to eq(controlled_in_jan_and_june.size)
      expect(facility_1_results[Period.month(june_1_2020)]).to eq(3)
    end

    it "excludes dead patients with_exclusions from control info" do
      facility_1 = FactoryBot.create_list(:facility, 1, facility_group: facility_group_1).first
      facility_1_controlled = create_list(:patient, 1, full_name: "controlled", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)
      facility_1_controlled_dead = create_list(:patient, 1, status: :dead, full_name: "controlled", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)

      Timecop.freeze(jan_2020) do
        facility_1_controlled.concat(facility_1_controlled_dead).map do |patient|
          create(:blood_pressure, :under_control, facility: facility_1, patient: patient, recorded_at: 15.days.ago, user: user)
        end
      end

      refresh_views
      jan = Period.month(jan_2020)
      repo = Reports::Repository.new(facility_1, periods: Period.month(jan), with_exclusions: true)
      controlled = repo.controlled_patients_count
      uncontrolled = repo.uncontrolled_patients_count

      region = facility_1.region
      expect(controlled[region.slug].fetch(jan)).to eq(1)
      expect(uncontrolled[region.slug].fetch(jan)).to eq(0)
    end

    it "gets no bp measure counts" do
      facility_1 = FactoryBot.create_list(:facility, 1, facility_group: facility_group_1).first
      facility_1_no_bp = create_list(:patient, 1, full_name: "controlled", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)
      facility_1_with_bp = create_list(:patient, 1, full_name: "controlled", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)

      Timecop.freeze(jan_2020) do
        create(:appointment, patient: facility_1_no_bp.first)
        facility_1_with_bp.map do |patient|
          create(:blood_pressure, :under_control, facility: facility_1, patient: patient, recorded_at: 15.days.ago, user: user)
        end
      end

      refresh_views
      jan = Period.month(jan_2020)
      repo = Reports::Repository.new(facility_1, periods: (Period.month(jan.advance(months: -3))..Period.month(jan)), with_exclusions: true)
      expect(repo.missed_visits_count[facility_1.region.slug][Period.month(jan.advance(months: -1))]).to eq(0)
      expect(repo.missed_visits_count[facility_1.region.slug][Period.month(jan)]).to eq(1)
    end
  end

  context "caching" do
    let(:facility_1) { create(:facility) }
    let(:july_2020_range) { (Period.month(july_2020.advance(months: -24))..Period.month(july_2020)) }

    it "incorporates optional args into the cache keys" do
      with_exclusions_repo = Reports::Repository.new(facility_1, periods: Period.month("June 1 2019")..Period.month("Jan 1 2020"), with_exclusions: true)
      cache_keys = with_exclusions_repo.send(:cache_entries, :controlled).map(&:cache_key)
      cache_keys.each do |key|
        expect(key).to include("controlled/with_exclusions/true")
      end

      without_exclusions_repo = Reports::Repository.new(facility_1, periods: Period.month("June 1 2019")..Period.month("Jan 1 2020"), with_exclusions: false)
      cache_keys = without_exclusions_repo.send(:cache_entries, :controlled).map(&:cache_key)
      cache_keys.each do |key|
        expect(key).to include("controlled/with_exclusions/false")
      end
    end

    it "memoizes calls and will ignore memoization via force_cache" do
      controlled_in_jan = create_list(:patient, 2, full_name: "controlled", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)
      Timecop.freeze(jan_2020) do
        controlled_in_jan.map do |patient|
          create(:blood_pressure, :under_control, facility: facility_1, patient: patient, recorded_at: 4.days.from_now, user: user)
        end
      end
      refresh_views

      repo = Reports::Repository.new(facility_1.region, periods: july_2020_range)

      allow(repo).to receive(:cached_query).and_call_original
      expect(repo).to receive(:cached_query).with(:controlled_patients_count).exactly(1).times.and_call_original

      3.times { _result = repo.controlled_patients_count }
      3.times { _result = repo.controlled_patient_rates }
    end

    it "will ignore memoization via force_cache" do
      controlled_in_jan = create_list(:patient, 2, full_name: "controlled", recorded_at: jan_2019, assigned_facility: facility_1, registration_user: user)
      Timecop.freeze(jan_2020) do
        controlled_in_jan.map do |patient|
          create(:blood_pressure, :under_control, facility: facility_1, patient: patient, recorded_at: 4.days.from_now, user: user)
        end
      end
      refresh_views

      RequestStore[:force_cache] = true
      repo = Reports::Repository.new(facility_1.region, periods: july_2020_range)
      expect(repo).to receive(:cached_query).with(:controlled_patients_count).exactly(3).times

      3.times { _result = repo.controlled_patients_count }
    end
  end
end
