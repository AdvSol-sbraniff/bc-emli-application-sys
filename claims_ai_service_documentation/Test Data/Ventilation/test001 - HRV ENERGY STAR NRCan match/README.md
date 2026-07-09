# Ventilation Test 001 - HRV ENERGY STAR NRCan Match

Purpose: faux source documents for the planned ventilation HRV/ERV NRCan ENERGY STAR product-list rule.

This test is designed to exercise a positive HERV product-list match after the planned `herv` external-reference catalogue and code rule are implemented.

Expected classification:

- Upgrade type: `ventilation`
- Ventilation system type: HRV / heat recovery ventilator
- Product manufacturer: `Airflow`
- Product model number: `AIR205-R`
- Associated eligible upgrade: air-source heat pump
- Product-list source segment: `ES.Ventilators.HeatEnergyRecovery`
- Expected HERV product-list match: pass when the imported NRCan ENERGY STAR H/ERV list contains `BrandName=Airflow` and `ModelNumber=AIR205-R`

Files:

- `faux_invoice.txt`: contractor invoice text with ventilation line item, associated heat pump line item, rebate line, and total arithmetic.
- `faux_supporting_doc_product_spec_sheet.txt`: product spec sheet text with HRV/ERV manufacturer, model, ENERGY STAR, NRCan, SRE, airflow, and power evidence.
- `faux_supporting_doc_energy_star_label.txt`: ENERGY STAR label text fixture with brand/model and NRCan searchable product-list reference.
- `expected_located_fields.md`: expected named fields and expected future code-rule outcome.

These are text fixtures, not real PDFs. If a PDF-ingestion smoke test is needed later, convert these documents into PDFs without changing their visible wording.
