# Ventilation Test 002 - ENERGY STAR Fan Product List Match

Purpose: full ingest smoke test for `vent_fan_energy_star_product_list_match`.

Expected outcome:

```text
1. The invoice is classified as the primary invoice.
2. The two product documents are classified as supporting documents.
3. GenAI extracts ventilation fan identity from the invoice:
   - vent_manufacturer = ACIQ
   - vent_model_number = AEP110
   - vent_make_model = ACIQ AEP110
4. Supporting-document extraction finds fan product evidence:
   - brand_and_model = ACIQ AEP110
   - model_number = AEP110
   - energy_star_reference = ENERGY STAR certified ventilating fan
5. Product lookup sets invoice_versions.vent_fan_product_id to the imported ENERGY STAR fan row for ACIQ AEP110.
6. Code rule vent_fan_energy_star_product_list_match returns pass.
```

Reference product row from ENERGY STAR Certified Ventilating Fans Product List:

```text
ENERGY STAR Unique ID: 3629726
Brand Name: ACIQ
Model Name: AEP
Model Number: AEP110
Type: Bathroom/Utility Room
Airflow 1 (cfm): 110
Efficacy 1 (cfm/Watt): 4.2
CB Model Identifier: ES_1151218_AEP110_09272024000000_1008147
```
