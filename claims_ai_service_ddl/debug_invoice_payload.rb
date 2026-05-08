invoice_id = ENV.fetch("INVOICE_ID")

pa = PermitApplication.find(invoice_id)
tv = pa.template_version
rt = tv&.requirement_template
user = pa.submitter.is_a?(Contractor) ? pa.submitter.contact : pa.submitter
data =
  PermitApplicationBlueprint.render_as_hash(
    pa,
    view: :extended,
    current_user: user
  )
form_json = data[:form_json] || data["form_json"]
submission_data = data[:submission_data] || data["submission_data"]
components = form_json && (form_json[:components] || form_json["components"])

pp(
  record: {
    id: pa.id,
    status: pa.status,
    template_version_id: pa.template_version_id,
    requirement_template_nickname: rt&.nickname,
    full_address: pa.full_address,
    submission_variant: pa.submission_variant&.name,
    has_submission_data: pa.submission_data.present?,
    has_template_form_json: tv&.form_json.present?
  },
  payload: {
    is_fully_loaded: data[:is_fully_loaded] || data["is_fully_loaded"],
    form_json_present: !form_json.nil?,
    form_json_component_count: components&.length,
    submission_data_present: !submission_data.nil?,
    top_level_keys: data.keys.sort
  }
)
