# frozen_string_literal: true

namespace :claims do
  namespace :external_references do
    desc "Import BC Hydro heat pump product lists from configured remote source URLs"
    task import_heat_pump_products: :environment do
      sources =
        if ENV["AHRI_SOURCE_ID"].present?
          Claims::AhriSource.where(id: ENV["AHRI_SOURCE_ID"])
        else
          Claims::AhriSource.order(:description, :id)
        end

      abort("No AHRI sources matched") if sources.empty?

      results =
        sources.map do |source|
          Claims::ExternalReferences::ImportBcHydroHeatPumpProducts.call(
            ahri_source_id: source.id,
            publishing_date: ENV["PUBLISHING_DATE"],
            publishing_notes: ENV["PUBLISHING_NOTES"],
            pdf_path: ENV["PDF_PATH"]
          ).merge(source_description: source.description)
        end

      puts JSON.pretty_generate(results)

      failures = results.reject { |result| result[:ok] }
      abort(failures.map { |result| result[:error] }.join("\n")) if failures.any?
    end

    desc "Import NRCan ENERGY STAR heat/energy recovery ventilator products from configured remote source URLs"
    task import_herv_products: :environment do
      sources =
        if ENV["HERV_SOURCE_ID"].present?
          Claims::HervSource.where(id: ENV["HERV_SOURCE_ID"])
        else
          Claims::HervSource.order(:description, :id)
        end

      abort("No HERV sources matched") if sources.empty?

      results =
        sources.map do |source|
          Claims::ExternalReferences::ImportHervProducts.call(
            herv_source_id: source.id,
            publishing_date: ENV["PUBLISHING_DATE"],
            publishing_notes: ENV["PUBLISHING_NOTES"],
            csv_path: ENV["CSV_PATH"]
          ).merge(source_description: source.description)
        end

      puts JSON.pretty_generate(results)

      failures = results.reject { |result| result[:ok] }
      abort(failures.map { |result| result[:error] }.join("\n")) if failures.any?
    end

    desc "Import ENERGY STAR certified ventilating fan products from configured remote source URLs"
    task import_vent_fan_products: :environment do
      sources =
        if ENV["VENT_FAN_SOURCE_ID"].present?
          Claims::VentFanSource.where(id: ENV["VENT_FAN_SOURCE_ID"])
        else
          Claims::VentFanSource.order(:description, :id)
        end

      abort("No ENERGY STAR ventilating fan sources matched") if sources.empty?

      results =
        sources.map do |source|
          Claims::ExternalReferences::ImportVentFanProducts.call(
            vent_fan_source_id: source.id,
            publishing_date: ENV["PUBLISHING_DATE"],
            publishing_notes: ENV["PUBLISHING_NOTES"],
            csv_path: ENV["CSV_PATH"]
          ).merge(source_description: source.description)
        end

      puts JSON.pretty_generate(results)

      failures = results.reject { |result| result[:ok] }
      abort(failures.map { |result| result[:error] }.join("\n")) if failures.any?
    end
  end
end
