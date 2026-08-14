export type InvoiceStatusCopy = {
  label: string;
  hint: string;
};

export type InvoiceStatusVisual = {
  background: string;
  border: string;
  color: string;
};

const DEFAULT_STATUS_VISUAL: InvoiceStatusVisual = {
  background: 'greys.grey50',
  border: 'border.randomBorderColorforthePublishModal',
  color: 'greys.anotherGrey',
};

const INVOICE_STATUS_VISUALS: Record<string, InvoiceStatusVisual> = {
  contractor_precheck: {
    background: 'theme.blueLight',
    border: 'greys.lightGrey',
    color: 'greys.anotherGrey',
  },
  admin_review_inbox: {
    background: 'theme.orangeLight02',
    border: 'theme.orange',
    color: 'greys.anotherGrey',
  },
  contractor_revision_inbox: {
    background: 'theme.softRose',
    border: 'semantic.errorDark',
    color: 'greys.anotherGrey',
  },
  in_review: {
    background: 'theme.lightGreen',
    border: 'theme.darkGreen',
    color: 'greys.anotherGrey',
  },
  approved: {
    background: 'theme.lightGreen',
    border: 'theme.darkGreen',
    color: 'greys.anotherGrey',
  },
  approved_pending: {
    background: 'theme.lightGreen',
    border: 'theme.darkGreen',
    color: 'greys.anotherGrey',
  },
  approved_paid: {
    background: 'theme.lightGreen',
    border: 'theme.darkGreen',
    color: 'greys.anotherGrey',
  },
  ineligible: DEFAULT_STATUS_VISUAL,
  contractor_withdrawn: DEFAULT_STATUS_VISUAL,
  preparing_ai_advice: {
    background: 'theme.blueLight',
    border: 'greys.lightGrey',
    color: 'greys.anotherGrey',
  },
  package_needs_correction: {
    background: 'theme.softRose',
    border: 'semantic.errorDark',
    color: 'greys.anotherGrey',
  },
  needs_technical_help: {
    background: 'theme.softRose',
    border: 'semantic.errorDark',
    color: 'greys.anotherGrey',
  },
};

export const invoiceStatusVisual = (status?: string | null): InvoiceStatusVisual =>
  INVOICE_STATUS_VISUALS[String(status || '').trim()] || DEFAULT_STATUS_VISUAL;

export const INVOICE_STATUS_COPY: Record<string, InvoiceStatusCopy> = {
  contractor_precheck: {
    label: 'With Contractor for Pre-check',
    hint: 'AI Advice is complete. The contractor can pre-check the advice, revise if needed, and submit when ready.',
  },
  admin_review_inbox: {
    label: 'With First Level Admin Review',
    hint: 'The claim is waiting for first level admin review.',
  },
  contractor_revision_inbox: {
    label: 'With Contractor for Revision',
    hint: 'Admin review sent the claim back to the contractor to revise the package or provide supporting information.',
  },
  in_review: {
    label: 'With Second Level Admin Review',
    hint: 'A second level admin review is underway.',
  },
  approved_pending: {
    label: 'Approved, Pending Payment',
    hint: 'The claim is approved, but payment or final closeout is not complete yet.',
  },
  approved_paid: {
    label: 'Approved and Paid',
    hint: 'The claim has been approved and paid or closed.',
  },
  ineligible: {
    label: 'Ineligible',
    hint: 'The claim has been marked ineligible.',
  },
  contractor_withdrawn: {
    label: 'Withdrawn by Contractor',
    hint: 'The contractor voluntarily withdrew this invoice before approval.',
  },
};

export const INVOICE_STATUS_FILTER_OPTIONS = [
  'contractor_precheck',
  'admin_review_inbox',
  'contractor_revision_inbox',
  'in_review',
  'approved_pending',
  'approved_paid',
  'ineligible',
  'contractor_withdrawn',
];

const humanizeStatus = (status: string) =>
  status
    .split('_')
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');

export const invoiceStatusCopy = (status?: string | null): InvoiceStatusCopy => {
  const rawStatus = String(status || '').trim();
  if (!rawStatus) {
    return {
      label: 'Unknown',
      hint: 'No invoice status is available yet.',
    };
  }

  const copy = INVOICE_STATUS_COPY[rawStatus] || {
    label: humanizeStatus(rawStatus),
    hint: 'This invoice is in a workflow status that does not have custom help text yet.',
  };

  return copy;
};

export const INVOICE_STATUS_FILTER_GROUPS = INVOICE_STATUS_FILTER_OPTIONS.reduce<
  Array<{ label: string; statuses: string[] }>
>((groups, status) => {
  const label = invoiceStatusCopy(status).label;
  const existing = groups.find((group) => group.label === label);
  if (existing) existing.statuses.push(status);
  else groups.push({ label, statuses: [status] });
  return groups;
}, []);
