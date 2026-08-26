export type AdminPdfViewerUxMode = 'simple' | 'enterprise';

export const normalizeAdminPdfViewerUxMode = (value: unknown): AdminPdfViewerUxMode =>
  value === 'enterprise' ? 'enterprise' : 'simple';
