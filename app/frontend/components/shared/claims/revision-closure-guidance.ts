export const EXPLANATION_OR_ATTESTATION_LABEL = 'Explanation or attestation accepted';
export const INTERNAL_RESOLUTION_LABEL = 'Resolved internally before sending to contractor';

export const REVISION_CLOSURE_LABELS: Record<string, string> = {
  closed_no_contractor_action_required: INTERNAL_RESOLUTION_LABEL,
  closed_via_corrected_documentation: 'Corrected documentation accepted',
  closed_via_attestation: EXPLANATION_OR_ATTESTATION_LABEL,
  closed_via_exception: 'Exception granted',
  closed_as_withdrawn: 'Issue withdrawn',
};

const CLOSURE_GUIDANCE: Record<string, string> = {
  closed_no_contractor_action_required:
    'The admin resolves the issue before sending it to the contractor. No contractor response or correction is required. Record why the issue can be closed internally.',
  closed_via_corrected_documentation:
    'Corrected or additional documents resolve the issue and establish that the requirement is met. Record which documents were accepted and what they resolved.',
  closed_via_attestation:
    'An explanation or attestation establishes that the requirement is met. An explanation provides context; an attestation gives a formal assurance. If the requirement is not met, acceptance requires an authorised exception instead.',
  closed_via_exception:
    'The requirement is not met, but an authorised exception permits acceptance. Record the unmet requirement, why the exception is allowed and who authorised it.',
  closed_as_withdrawn:
    'The issue is withdrawn without completing the requested correction. Record the reason for withdrawal; this does not establish that the requirement was met.',
};

export const revisionClosureGuidance = (status: string): string =>
  CLOSURE_GUIDANCE[status] ||
  'Choose the outcome that records what the admin concluded. The contractor response records what they supplied; an explanation or attestation can establish compliance or support a request for an exception.';
