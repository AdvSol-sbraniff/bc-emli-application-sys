export function formatClaimsReferenceNumber(referenceNumber: number | string) {
  const digits = String(referenceNumber).padStart(9, '0');
  const groupedDigits = digits.replace(/\B(?=(\d{3})+(?!\d))/g, '-');

  return `C-${groupedDigits}`;
}
