BEGIN;

-- ============================================================
-- SEED IDs (fixed, repeatable)
-- ============================================================
-- sessions.id         = bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
-- invoices.id         = cccccccc-cccc-cccc-cccc-cccccccccccc
-- invoice_versions.id = dddddddd-dddd-dddd-dddd-dddddddddddd
-- lineitems.id        = eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1
--                      eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2
--
-- FK assumptions from your earlier seed script:
-- public.contractors.id = aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
-- public.users.id:
--   admin       = 11111111-1111-1111-1111-111111111111
--   contractor  = 22222222-2222-2222-2222-222222222222
--   participant = 33333333-3333-3333-3333-333333333333


-- Lineitems (child of invoice_versions)
DELETE FROM claims.lineitems;

--UPDATE claims.invoices	
--SET current_invoice_version_id = NULL;

DELETE FROM claims.invoice_versions;
DELETE FROM claims.invoices;
DELETE FROM claims.sessions;


-- ... keep your INSERTS exactly as they were ...


-- ============================================================
-- INSERT sessions
-- Must satisfy:
--   status in (OPENBUTNOTSUBMITTED, OPENANDSUBMITTED, CLOSED)
--   and check constraint tying status <-> submitter_id/submitted_at
-- ============================================================

-- \set session_id1    '00000001-0000-0000-0000-000000000000'



INSERT INTO claims.sessions (
  id,
  contractor_id,
  submitter_id,
  status,
  created_at,
  updated_at,
  submitted_at
) VALUES (
'00000001-0000-0000-0000-000000000000',
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',   -- contractor
  NULL,                                     -- must be NULL when OPENBUTNOTSUBMITTED
  'OPENBUTNOTSUBMITTED',
  now(), now(),
  NULL                                      -- must be NULL when OPENBUTNOTSUBMITTED
);



-- ============================================================
-- INSERT invoice 1
-- ============================================================

INSERT INTO claims.invoices (
  id,
  session_id,

  system_help_notes,
--  current_invoice_version_id,
  status,
  status_updated_at,
  created_at,
  updated_at
) VALUES (
'00000001-0001-0000-0000-000000000000',
'00000001-0000-0000-0000-000000000000',

  'Seed invoice for dev/testing.',
  'awaiting_contractor_submit',
  now(),
  now(), now()
);


INSERT INTO claims.invoice_versions (
  id,
  invoice_id,
  invoice_versionno,

  storage_provider,
  storage_key,
  original_filename,
  content_type,
  byte_size,
  sha256,

  di_raw_json,

  di_ocr_invoice_id,
  di_ocr_invoice_id_page,
  di_ocr_invoice_id_polygon,
  di_ocr_invoice_date,
  di_ocr_invoice_date_page,
  di_ocr_invoice_date_polygon,
  di_ocr_vendor_name,
  di_ocr_vendor_name_page,
  di_ocr_vendor_name_polygon,
  di_ocr_vendor_address,
  di_ocr_vendor_address_page,
  di_ocr_vendor_address_polygon,
  di_ocr_customer_name,
  di_ocr_customer_name_page,
  di_ocr_customer_name_polygon,
  di_ocr_billing_address,
  di_ocr_billing_address_page,
  di_ocr_billing_address_polygon,
  di_ocr_sub_total,
  di_ocr_sub_total_page,
  di_ocr_sub_total_polygon,
  di_ocr_total_tax,
  di_ocr_total_tax_page,
  di_ocr_total_tax_polygon,
  di_ocr_invoice_total,
  di_ocr_invoice_total_page,
  di_ocr_invoice_total_polygon,
  di_ocr_amount_due,
  di_ocr_amount_due_page,
  di_ocr_amount_due_polygon,

  created_at,
  updated_at
) VALUES (
'00000001-0001-0001-0000-000000000000',
'00000001-0001-0000-0000-000000000000',
  1,

  'azure_blob',
  'dev/claims/invoices/cccccccc-cccc-cccc-cccc-cccccccccccc/v1/invoice.pdf',
  'sample_invoice.pdf',
  'application/pdf',
  123456,
  NULL,

  NULL,

  'INV-10001',
  1,
  NULL,
  now()::timestamp,
  1,
  NULL,
  'we are at invoice1 the first version- Acme Windows Ltd',
  1,
  NULL,
  '123 Main St, Victoria BC',
  1,
  NULL,
  'Pat Participant',
  1,
  NULL,
  '456 Home Rd, Victoria BC',
  1,
  NULL,
  1000.00,
  1,
  NULL,
  50.00,
  1,
  NULL,
  1050.00,
  1,
  NULL,
  1050.00,
  1,
  NULL,

  now(),
  now()
);


INSERT INTO claims.lineitems (
  id,
  invoice_version_id,
  lineitem_seqno,
  ocr_description,
  ocr_quantity,
  ocr_unit_price,
  ocr_amount,
  created_at,
  updated_at
) VALUES
(
'00000001-0001-0001-0001-000000000000',
'00000001-0001-0001-0000-000000000000',
  1,
  'Window unit - supply',
  2.000,
  350.0000,
  700.00,
  now(), now()
),
(
'00000001-0001-0001-0002-000000000000',
'00000001-0001-0001-0000-000000000000',
  2,
  'Labour - install windows',
  2.000,
  150.0000,
  300.00,
  now(), now()
);

INSERT INTO claims.invoice_versions (
  id,
  invoice_id,
  invoice_versionno,

  storage_provider,
  storage_key,
  original_filename,
  content_type,
  byte_size,
  sha256,

  di_raw_json,

  di_ocr_invoice_id,
  di_ocr_invoice_id_page,
  di_ocr_invoice_id_polygon,
  di_ocr_invoice_date,
  di_ocr_invoice_date_page,
  di_ocr_invoice_date_polygon,
  di_ocr_vendor_name,
  di_ocr_vendor_name_page,
  di_ocr_vendor_name_polygon,
  di_ocr_vendor_address,
  di_ocr_vendor_address_page,
  di_ocr_vendor_address_polygon,
  di_ocr_customer_name,
  di_ocr_customer_name_page,
  di_ocr_customer_name_polygon,
  di_ocr_billing_address,
  di_ocr_billing_address_page,
  di_ocr_billing_address_polygon,
  di_ocr_sub_total,
  di_ocr_sub_total_page,
  di_ocr_sub_total_polygon,
  di_ocr_total_tax,
  di_ocr_total_tax_page,
  di_ocr_total_tax_polygon,
  di_ocr_invoice_total,
  di_ocr_invoice_total_page,
  di_ocr_invoice_total_polygon,
  di_ocr_amount_due,
  di_ocr_amount_due_page,
  di_ocr_amount_due_polygon,

  created_at,
  updated_at
) VALUES (
'00000001-0001-0002-0000-000000000000',
'00000001-0001-0000-0000-000000000000',
  2,

  'azure_blob',
  'dev/claims/invoices/cccccccc-cccc-cccc-cccc-cccccccccccc/v2/invoice.pdf',
  'sample_invoice.pdf',
  'application/pdf',
  123456,
  NULL,

  NULL,

  'INV-10001',
  1,
  NULL,
  now()::timestamp,
  1,
  NULL,
  'we are at invoice1 the second version - Acme Windows Ltd',
  1,
  NULL,
  '123 Main St, Victoria BC',
  1,
  NULL,
  'Pat Participant',
  1,
  NULL,
  '456 Home Rd, Victoria BC',
  1,
  NULL,
  1000.00,
  1,
  NULL,
  50.00,
  1,
  NULL,
  1050.00,
  1,
  NULL,
  1050.00,
  1,
  NULL,

  now(),
  now()
);


INSERT INTO claims.lineitems (
  id,
  invoice_version_id,
  lineitem_seqno,
  ocr_description,
  ocr_quantity,
  ocr_unit_price,
  ocr_amount,
  created_at,
  updated_at
) VALUES
(
'00000001-0001-0002-0001-000000000000',
'00000001-0001-0002-0000-000000000000',
  1,
  'Window unit - supply',
  2.000,
  350.0000,
  700.00,
  now(), now()
),
(
'00000001-0001-0002-0002-000000000000',
'00000001-0001-0002-0000-000000000000',
  2,
  'Labour - install windows',
  2.000,
  150.0000,
  300.00,
  now(), now()
);



-- ============================================================
-- INSERT invoice 2
-- ============================================================

INSERT INTO claims.invoices (
  id,
  session_id,

  system_help_notes,
 -- current_invoice_version_id,
  status,
  status_updated_at,
  created_at,
  updated_at
) VALUES (
'00000001-0002-0000-0000-000000000000',
'00000001-0000-0000-0000-000000000000',

  'Seed invoice for dev/testing.',
 -- NULL,                                     -- set after invoice_versions insert
  'awaiting_contractor_submit',
  now(),
  now(), now()
);


INSERT INTO claims.invoice_versions (
  id,
  invoice_id,
  invoice_versionno,

  storage_provider,
  storage_key,
  original_filename,
  content_type,
  byte_size,
  sha256,

  di_raw_json,
  di_page_map,
  di_ocr_invoice_id,
  di_ocr_invoice_id_page,
  di_ocr_invoice_id_polygon,
  di_ocr_invoice_date,
  di_ocr_invoice_date_page,
  di_ocr_invoice_date_polygon,
  di_ocr_vendor_name,
  di_ocr_vendor_name_page,
  di_ocr_vendor_name_polygon,
  di_ocr_vendor_address,
  di_ocr_vendor_address_page,
  di_ocr_vendor_address_polygon,
  di_ocr_customer_name,
  di_ocr_customer_name_page,
  di_ocr_customer_name_polygon,
  di_ocr_billing_address,
  di_ocr_billing_address_page,
  di_ocr_billing_address_polygon,
  di_ocr_sub_total,
  di_ocr_sub_total_page,
  di_ocr_sub_total_polygon,
  di_ocr_total_tax,
  di_ocr_total_tax_page,
  di_ocr_total_tax_polygon,
  di_ocr_invoice_total,
  di_ocr_invoice_total_page,
  di_ocr_invoice_total_polygon,
  di_ocr_amount_due,
  di_ocr_amount_due_page,
  di_ocr_amount_due_polygon,

  created_at,
  updated_at
) VALUES (
'00000001-0002-0001-0000-000000000000',
'00000001-0002-0000-0000-000000000000',
  1,

  'azure_blob',
  'dev/claims/invoices/cccccccc-cccc-cccc-cccc-cccccccccccc/v1/invoice.pdf',
  'sample_invoice.pdf',
  'application/pdf',
  123456,
  NULL,

  NULL,
  '[ { "pageNumber": 1, "width": 8.5, "height": 11, "unit": "inch" }]',

  'INV-10001',  -- di_ocr_invoice_id
  1,
  '[5.488, 1.6779, 6.292, 1.6774, 6.2918, 1.8324, 5.4879, 1.8324]'::jsonb,

  to_date('2025-03-21','YYYY-MM-DD'), -- di_ocr_invoice_date
  1,
  '[5.4878, 2.0141, 6.1149, 2.0119, 6.1149, 2.1637, 5.4878, 2.1642]'::jsonb,

  'Centra® WINDOWS',  --  di_ocr_vendor_name,
  1,
  '[0.9797, 0.537, 3.4301, 0.5511, 3.4255, 1.3663, 0.975, 1.3523]'::jsonb,

  '4705 102 Ave SE Calgary, AB T2C 2X7', --di_ocr_vendor_address
  1,
  '[ 0.1941, 1.7088, 1.621, 1.7053, 1.6218, 2.0417, 0.1949, 2.0453]'::jsonb,

  'EBY, JESSE & ERIN', --di_ocr_customer_name
  1,
  '[ 0.7911,2.5877, 2.092, 2.5892, 2.0918, 2.7464, 0.7909, 2.7449]'::jsonb,
  
  '561 6 AVENUE CAMPBELL RIVER, BC V9W 3Z6 Canada',  -- di_ocr_billing_address
  1,
  '[ 0.7786, 2.7537, 2.8887, 2.754, 2.8886, 3.2333, 0.7785, 3.2329]'::jsonb,

  4923.42, -- di_ocr_sub_total
  1,
  '[ 6.8528, 7.1741, 8.0716, 7.2019, 8.0678, 7.3691, 6.849, 7.3413]'::jsonb,

  246.17, -- di_ocr_total_tax
  1,
  '[ 6.8526, 7.5303, 8.0636, 7.5379, 8.0627, 7.6805, 6.8517, 7.6729]'::jsonb,

  5169.59, -- di_ocr_invoice_total
  1,
   '[6.8528, 7.9539, 8.1073, 7.9554, 8.1071, 8.103, 6.8526, 8.1015]'::jsonb,

  3269.59, -- di_ocr_amount_due
  1,
   '[6.8284, 8.7005, 8.0743, 8.7035, 8.0739, 8.8713, 6.828,8.8683]'::jsonb,

  now(),
  now()
);






-- Insert testdata into claims.invoice_version_located_fields
-- Assumptions:
-- 1) parent invoice_versions.id exists: 00000001-0002-0001-0000-000000000000
-- 2) you dropped scope and you are using line_number NULL for these rows
-- 3) value_type uses: text|number|currency|date|bool|json
-- 4) polygon stored as jsonb array of numbers

INSERT INTO claims.invoice_version_located_fields
(
  invoice_version_id,
  source_engine,
  field_key,
  line_number,
  value_type,
  value_text,
  value_json,
  confidence,
  page,
  polygon,
  evidence_text,
  created_at,
  updated_at
)
VALUES
(
  '00000001-0002-0001-0000-000000000000',
  'genai',
  'contractor_gst_number',
  NULL,
  'text',
  '105091532',
  NULL,
  95,
  1,
  '[1.2873, 8.6172, 1.9867, 8.6179, 1.9867, 8.7667, 1.2873, 8.7677]'::jsonb,
  'GST Number 105091532',
  now(),
  now()
),
(
  '00000001-0002-0001-0000-000000000000',
  'genai',
  'eligibility_code',
  NULL,
  'text',
  'ESP1-136a31ba',
  NULL,
  94,
  1,
  '[0.2853, 3.9889, 1.3226, 3.9911, 1.3226, 4.1401, 0.2853, 4.1358]'::jsonb,
  'ESP1-136a31ba',
  now(),
  now()
),
(
  '00000001-0002-0001-0000-000000000000',
  'genai',
  'labour_cost_invoice_total',
  NULL,
  'currency',
  NULL,
  NULL,
  40,
  NULL,
  NULL,
  'No explicit labour total shown. Invoice shows supply and install but does not separately itemize labour cost.',
  now(),
  now()
),
(
  '00000001-0002-0001-0000-000000000000',
  'genai',
  'customer_deposit',
  NULL,
  'currency',
  NULL,
  NULL,
  60,
  1,
  '[6.8533, 8.4581, 6.9395, 8.4592, 6.9395, 8.5861, 6.8529, 8.5849]'::jsonb,
  'Deposit Received: Totals section. Deposit label present but amount not populated.',
  now(),
  now()
),
(
  '00000001-0002-0001-0000-000000000000',
  'genai',
  'nrcan_number',
  NULL,
  'text',
  'NR5707-46721659-ES5',
  NULL,
  96,
  1,
  '[3.3654, 4.8774, 4.6042, 4.8788, 4.6042, 5.0304, 3.3644, 5.0322]'::jsonb,
  'NRCan: NR5707-46721659-ES5',
  now(),
  now()
),
(
  '00000001-0002-0001-0000-000000000000',
  'genai',
  'cpd_number',
  NULL,
  'text',
  NULL,
  NULL,
  20,
  NULL,
  NULL,
  NULL,
  now(),
  now()
),
(
  '00000001-0002-0001-0000-000000000000',
  'genai',
  'brand_and_model',
  NULL,
  'text',
  'Centra Model 6800 ENERGY STAR windows',
  NULL,
  90,
  1,
  NULL,
  'Model: 6800 U-factor: 1.14 ENERGY STAR',
  now(),
  now()
),
(
  '00000001-0002-0001-0000-000000000000',
  'genai',
  'metric_u_factor',
  NULL,
  'number',
  '1.14',
  NULL,
  95,
  1,
  '[1.5429, 4.8806, 1.767, 4.8794, 1.7665, 5.0311, 1.5425, 5.0313]'::jsonb,
  'U-factor: 1.14',
  now(),
  now()
),
(
  '00000001-0002-0001-0000-000000000000',
  'genai',
  'labour_per_unit',
  NULL,
  'json',
  NULL,
  NULL,
  30,
  NULL,
  NULL,
  NULL,
  now(),
  now()
);






-- ============================================================
-- INSERT invoice 3
-- ============================================================

INSERT INTO claims.invoices (
  id,
  session_id,

  system_help_notes,
 -- current_invoice_version_id,
  status,
  status_updated_at,
  created_at,
  updated_at
) VALUES (
'00000001-0003-0000-0000-000000000000',
'00000001-0000-0000-0000-000000000000',

  'Seed invoice for dev/testing.',
 -- NULL,                                     -- set after invoice_versions insert
  'awaiting_contractor_submit',
  now(),
  now(), now()
);


INSERT INTO claims.invoice_versions (
  id,
  invoice_id,
  invoice_versionno,

  storage_provider,
  storage_key,
  original_filename,
  content_type,
  byte_size,
  sha256,

  di_raw_json,

  di_ocr_invoice_id,
  di_ocr_invoice_id_page,
  di_ocr_invoice_id_polygon,
  di_ocr_invoice_date,
  di_ocr_invoice_date_page,
  di_ocr_invoice_date_polygon,
  di_ocr_vendor_name,
  di_ocr_vendor_name_page,
  di_ocr_vendor_name_polygon,
  di_ocr_vendor_address,
  di_ocr_vendor_address_page,
  di_ocr_vendor_address_polygon,
  di_ocr_customer_name,
  di_ocr_customer_name_page,
  di_ocr_customer_name_polygon,
  di_ocr_billing_address,
  di_ocr_billing_address_page,
  di_ocr_billing_address_polygon,
  di_ocr_sub_total,
  di_ocr_sub_total_page,
  di_ocr_sub_total_polygon,
  di_ocr_total_tax,
  di_ocr_total_tax_page,
  di_ocr_total_tax_polygon,
  di_ocr_invoice_total,
  di_ocr_invoice_total_page,
  di_ocr_invoice_total_polygon,
  di_ocr_amount_due,
  di_ocr_amount_due_page,
  di_ocr_amount_due_polygon,

  created_at,
  updated_at
) VALUES (
'00000001-0003-0001-0000-000000000000',
'00000001-0003-0000-0000-000000000000',
  1,

  'azure_blob',
  'dev/claims/invoices/cccccccc-cccc-cccc-cccc-cccccccccccc/v1/invoice.pdf',
  'sample_invoice.pdf',
  'application/pdf',
  123456,
  NULL,

  NULL,

  'INV-10001',
  1,
  NULL,
  now()::timestamp,
  1,
  NULL,
  'we are at invoice3 - Acme Windows Ltd',
  1,
  NULL,
  '123 Main St, Victoria BC',
  1,
  NULL,
  'Pat Participant',
  1,
  NULL,
  '456 Home Rd, Victoria BC',
  1,
  NULL,
  1000.00,
  1,
  NULL,
  50.00,
  1,
  NULL,
  1050.00,
  1,
  NULL,
  1050.00,
  1,
  NULL,


  now(),
  now()
);





COMMIT;
