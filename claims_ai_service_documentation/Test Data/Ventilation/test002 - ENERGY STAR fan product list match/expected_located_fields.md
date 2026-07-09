# Expected Located Fields

Invoice located fields:

```text
vent_system_type = bathroom fan / utility room ventilating fan
vent_manufacturer = ACIQ
vent_model_number = AEP110
vent_make_model = ACIQ AEP110
vent_energy_star_reference = EPA/DOE certified ventilating fans searchable product list
vent_bathroom_fan_cfm = 110 CFM
vent_line_amount = 1600.00
upgrade_specific_rebate_line_amount = 1000.00
```

Supporting document located fields:

```text
brand_and_model = ACIQ AEP110
model_number = AEP110
product_category_or_system_type = Bathroom/Utility Room ventilating fan
energy_star_reference = ENERGY STAR certified ventilating fan
product_list_reference = ENERGY STAR certified ventilating fans searchable product list
```

Expected code rule:

```text
vent_fan_energy_star_product_list_match = pass
```
