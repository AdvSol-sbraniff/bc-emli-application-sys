INSERT INTO claims.vent_fan_sources (id, description, source_url)
VALUES (
  '840d8396-3103-428b-bf56-04a42aadc07f'::uuid,
  'ENERGY STAR Certified Ventilating Fans Product List',
  'https://www.energystar.gov/productfinder/product/certified-ventilating-fans/results?SetLanguage=English&NRCAN=on'
)
ON CONFLICT (id) DO UPDATE
SET
  description = EXCLUDED.description,
  source_url = EXCLUDED.source_url,
  updated_at = now();
