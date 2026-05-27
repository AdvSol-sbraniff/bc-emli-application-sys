# frozen_string_literal: true

namespace :claims do
  namespace :external_references do
    desc "Import the downloaded BC Hydro heat pump product-list PDF"
    task import_heat_pump_products: :environment do
      result =
        Claims::ExternalReferences::ImportBcHydroHeatPumpProducts.call(
          pdf_path:
            ENV.fetch(
              "PDF_PATH",
              Claims::ExternalReferences::ImportBcHydroHeatPumpProducts::DEFAULT_PDF_PATH
            )
        )

      puts JSON.pretty_generate(result)

      abort(result[:error]) unless result[:ok]
    end
  end
end
