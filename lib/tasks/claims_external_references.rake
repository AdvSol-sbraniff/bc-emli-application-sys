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
  end
end
