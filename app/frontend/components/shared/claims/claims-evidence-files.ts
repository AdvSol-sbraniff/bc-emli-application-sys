export const CLAIMS_EVIDENCE_FILE_ACCEPT = 'application/pdf,image/jpeg,image/png,.pdf,.jpg,.jpeg,.png';

export function isClaimsEvidenceFile(file: File): boolean {
  const type = String(file.type || '').toLowerCase();
  const name = String(file.name || '').toLowerCase();
  return type === 'application/pdf' || type === 'image/jpeg' || type === 'image/png' || /\.(pdf|jpe?g|png)$/.test(name);
}

export function supportedClaimsEvidenceFiles(files: File[]): File[] {
  return files.filter(isClaimsEvidenceFile);
}

export function mergeUniqueClaimsEvidenceFiles(existing: File[], incoming: File[]): File[] {
  const merged = [...existing];
  supportedClaimsEvidenceFiles(incoming).forEach((file) => {
    const duplicate = merged.some(
      (item) => item.name === file.name && item.size === file.size && item.lastModified === file.lastModified,
    );
    if (!duplicate) merged.push(file);
  });
  return merged;
}
