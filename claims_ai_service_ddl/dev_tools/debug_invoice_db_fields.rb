invoice_id = ENV.fetch("INVOICE_ID")

pa = PermitApplication.find(invoice_id)

pp(
  permit_type_id: pa.permit_type_id,
  activity_id: pa.activity_id,
  permit_type_name: (pa.permit_type ? pa.permit_type.name : nil),
  activity_name: (pa.activity ? pa.activity.name : nil)
)
