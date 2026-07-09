# Expected Located Fields

Expected invoice upgrade type:

- `ventilation`

Expected invoice-level GenAI located fields:

| Field key                                | Expected value                                                                                                      | Evidence                                                                                                                                                                          |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `vent_associated_upgrade_evidence`       | `installed ... as part of the same CleanBC Energy Savings Program project as the air-source heat pump installation` | `Installed one Airflow AIR205-R heat recovery ventilator (HRV) as part of the same CleanBC Energy Savings Program project as the air-source heat pump installation listed below.` |
| `vent_system_type`                       | `heat recovery ventilator / HRV`                                                                                    | `Ventilation upgrade - Airflow AIR205-R heat recovery ventilator (HRV)`                                                                                                           |
| `vent_manufacturer`                      | `Airflow`                                                                                                           | `Airflow AIR205-R heat recovery ventilator (HRV)`                                                                                                                                 |
| `vent_model_number`                      | `AIR205-R`                                                                                                          | `Airflow AIR205-R heat recovery ventilator (HRV)`                                                                                                                                 |
| `vent_make_model`                        | `Airflow AIR205-R`                                                                                                  | `Installed one Airflow AIR205-R heat recovery ventilator (HRV)`                                                                                                                   |
| `vent_energy_star_reference`             | `ENERGY STAR certified`                                                                                             | `The Airflow AIR205-R HRV is ENERGY STAR certified...`                                                                                                                            |
| `vent_nrcan_or_product_list_reference`   | `Natural Resources Canada searchable product list`                                                                  | `...listed on the Natural Resources Canada searchable product list for heat/energy recovery ventilators.`                                                                         |
| `vent_improved_air_circulation_evidence` | `improves air circulation in the home`                                                                              | `The ventilation upgrade improves air circulation in the home...`                                                                                                                 |
| `vent_line_amount`                       | `$2,000.00`                                                                                                         | `Ventilation upgrade - Airflow AIR205-R heat recovery ventilator (HRV)... Amount: $2,000.00`                                                                                      |
| `upgrade_specific_rebate_line_amount`    | `$1,600.00`                                                                                                         | `Ventilation rebate: -$1,600.00`                                                                                                                                                  |

Expected supporting-document located fields:

| Supporting document type | Field key                         | Expected value                                       |
| ------------------------ | --------------------------------- | ---------------------------------------------------- |
| `product_spec_sheet`     | `brand_and_model`                 | `Airflow AIR205-R`                                   |
| `product_spec_sheet`     | `model_number`                    | `AIR205-R`                                           |
| `product_spec_sheet`     | `energy_star_reference`           | `ENERGY STAR certified for Canada`                   |
| `product_spec_sheet`     | `nrcan_reference`                 | `Natural Resources Canada's searchable product list` |
| `product_spec_sheet`     | `product_category_or_system_type` | `Heat Recovery Ventilator (HRV)`                     |
| `product_spec_sheet`     | `efficiency_or_capacity_rating`   | `SRE at 0 C: 76.0%; airflow 64 CFM`                  |
| `energy_star_label`      | `brand_and_model`                 | `Airflow AIR205-R`                                   |
| `energy_star_label`      | `model_number`                    | `AIR205-R`                                           |
| `energy_star_label`      | `energy_star_reference`           | `ENERGY STAR Canada`                                 |
| `energy_star_label`      | `nrcan_reference`                 | `ES.Ventilators.HeatEnergyRecovery`                  |

Expected future code-rule result:

- `vent_associated_upgrade_present`: `pass`
- `vent_herv_nrcan_energy_star_product_list_match`: `pass`, after the `herv` importer loads the NRCan ENERGY STAR H/ERV list and product lookup matches `Airflow` / `AIR205-R`.

Expected future product-list match:

- Source segment: `ES.Ventilators.HeatEnergyRecovery`
- Brand: `Airflow`
- Model number: `AIR205-R`
- Match storage: `invoice_versions.herv_product_id`
