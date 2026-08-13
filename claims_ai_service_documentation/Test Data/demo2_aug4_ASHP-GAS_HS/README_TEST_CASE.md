# Demo 20260804 - Gas-to-Heat-Pump + Health and Safety

## Scenario

This is a complex, internally consistent upload package for Jordan Lee at 27 Cedar Ridge Road, Port Hardy, BC.

- Income Level 1 eligibility code: `ESP1-DEMO0730`
- Contractor brand: MiniMe Contracting Company
- Registered business name: Mini Home Energy Solutions
- Main upgrade: natural-gas furnace conversion to a central ducted air-source heat pump
- Associated upgrade: attic mould remediation required to enable safe HVAC installation
- Northern top-up: claimed for a Port Hardy home connected to BC Hydro
- AHRI reference: `203380999`
- Equipment: Bryant `38MAQB18R--3` with indoor air handler `FMC4Z1800AL`

## Upload These Seven Files

1. `01_Minime_Contracting_Company_Invoice.pdf`
2. `02_Health_Safety_Remediation_Photo_Report.pdf`
3. `03_ESP_Health_Safety_Preapproval.pdf`
4. `04_Natural_Gas_Furnace_Removal_Inspection.pdf`
5. `05_Bryant_AHRI_Product_Submittal.pdf`
6. `06_Heat_Load_and_Commissioning_Report.pdf`
7. `07_BC_Hydro_Service_Confirmation.pdf`

Do not upload `README_TEST_CASE.md`, `_source_assets`, `_source_templates`, or `archive`.

## Evidence Chain

- The invoice explicitly identifies the former natural-gas furnace as the home's primary heating system and states that it served more than 50% of the home throughout the heating season to 21 C.
- The invoice and heat-load report show that the new central ducted heat pump serves all conditioned space and uses electric-only backup heat.
- The removal inspection records the date, address, removed equipment and final accepted status.
- The invoice and product submittal carry the same AHRI reference and matched equipment components; that AHRI reference exists in the imported heat-pump product list.
- The pre-approval predates remediation, and the photo report shows the same attic area before and after mould treatment.
- The health-and-safety work is explicitly tied to the heat-pump air-handler/duct route and is not a standalone claim.
- The BC Hydro document and invoice support the northern location and utility-service checks.

## Invoice Arithmetic

- Heat pump: `$19,850.00`
- Health and safety remediation: `$840.00`
- Subtotal: `$20,690.00`
- GST: `$1,034.50`
- Invoice total before rebates: `$21,724.50`
- Central ducted heat-pump rebate: `-$16,000.00`
- Northern top-up: `-$3,000.00`
- Health and safety rebate: `-$800.00`
- Customer amount due after rebates: `$1,924.50`

## Rebuild

The PDFs can be regenerated after editing their HTML sources:

```bash
bash "claims_ai_service_documentation/Test Data/demo_20260804/_source_templates/render_package.sh"
```

The generated package can be checked for required files and evidence text with:

```bash
bash "claims_ai_service_documentation/Test Data/demo_20260804/_source_templates/validate_package.sh"
```
