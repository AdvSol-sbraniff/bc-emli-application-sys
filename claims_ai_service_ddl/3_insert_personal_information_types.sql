BEGIN;

INSERT INTO claims.personal_information_types (
  id,
  type_key,
  display_name,
  description,
  enabled,
  sort_order,
  created_at,
  updated_at
)
VALUES
  (
    '3e58ca81-e14f-4d41-97d4-a10c00000001'::uuid,
    'authentication_secret',
    'Authentication secret',
    'Passwords, credentials, authentication secrets, password hints, or similar access information that is unnecessary for validating the supplied document.',
    true,
    10,
    NOW(),
    NOW()
  ),
  (
    '3e58ca81-e14f-4d41-97d4-a10c00000002'::uuid,
    'government_identifier',
    'Government identifier',
    'SIN, passport, driver licence, health number, or another government-issued identifier that is unnecessary for validating the supplied document.',
    true,
    20,
    NOW(),
    NOW()
  ),
  (
    '3e58ca81-e14f-4d41-97d4-a10c00000003'::uuid,
    'health_or_medical_information',
    'Health or medical information',
    'Health, medical, diagnosis, treatment, medication, or disability information that is unnecessary for validating the supplied document.',
    true,
    30,
    NOW(),
    NOW()
  ),
  (
    '3e58ca81-e14f-4d41-97d4-a10c00000004'::uuid,
    'financial_or_payment_information',
    'Financial or payment information',
    'Bank account, routing, full payment-card, or similar financial information beyond ordinary invoice totals and payment terms.',
    true,
    40,
    NOW(),
    NOW()
  ),
  (
    '3e58ca81-e14f-4d41-97d4-a10c00000005'::uuid,
    'signature_or_biometric_information',
    'Signature or biometric information',
    'A signature, biometric characteristic, or similar identity evidence that is not normally required for this document type.',
    true,
    50,
    NOW(),
    NOW()
  ),
  (
    '3e58ca81-e14f-4d41-97d4-a10c00000006'::uuid,
    'date_of_birth',
    'Date of birth',
    'A date of birth or age detail that is unnecessary for validating the supplied document.',
    true,
    60,
    NOW(),
    NOW()
  ),
  (
    '3e58ca81-e14f-4d41-97d4-a10c00000007'::uuid,
    'unrelated_third_party_information',
    'Unrelated third-party information',
    'Personal information about children or minors is high risk when unrelated to the supplied document; also includes other unrelated third-party personal information.',
    true,
    70,
    NOW(),
    NOW()
  ),
  (
    '3e58ca81-e14f-4d41-97d4-a10c00000008'::uuid,
    'other_unnecessary_personal_information',
    'Other unnecessary personal information',
    'Other personal information that appears unnecessary or unrelated in the context of the supplied document.',
    true,
    80,
    NOW(),
    NOW()
  )
ON CONFLICT (type_key) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  description = EXCLUDED.description,
  enabled = EXCLUDED.enabled,
  sort_order = EXCLUDED.sort_order,
  updated_at = NOW();

COMMIT;
