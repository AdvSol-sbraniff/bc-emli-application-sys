# Demo 4 — Heat pump water heater

This package fills the largest primary upgrade-type gap left by Demos 1–3.

- Demo 1: air-source heat pump conversion from wood + ventilation
- Demo 2: air-source heat pump conversion from natural gas + health and safety remediation
- Demo 3: electrical service upgrade associated with a heat-pump conversion
- Demo 4: heat pump water heater replacing the home's primary electric resistance water heater

## Demo 4 identity

- Participant: Doreen Visia
- Eligibility code: `ESP1-7a1899b2`
- Income level: 1
- Contractor: Mini Home Energy Solutions (branded on the invoice as MiniMe Contracting Company)
- Invoice date: August 12, 2026
- Work completed: August 8, 2026

The equipment and price basis comes from `Test Data/Heat Pump/test010/Invoice 5 - Heat Pump Water Heater and Ventilation.pdf`. The invoice uses the exact Midea `MCHW-50VN3A` model found in the local NEEA download as a Tier 4 product, but narrows the scope to one residential heat pump water heater so the demo exercises that upgrade type cleanly.

For a local database that does not already contain the eligibility code, run `_source_templates/seed_local_participant.sql` against `app_development`. Doreen Visia is an existing public seed user and is not the participant in Demos 1–3.
