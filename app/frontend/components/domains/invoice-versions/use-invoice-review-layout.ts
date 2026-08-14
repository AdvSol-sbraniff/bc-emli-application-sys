import { useCallback, useState } from 'react';

export type RevisionWorkspacePlacement = 'top' | 'side';
export type CommunicationPanel = 'conversation' | 'internal_notes' | null;
export type EffectiveAuxiliaryPanel = 'revision_issues' | CommunicationPanel;

type MountedCommunicationPanels = {
  conversation: boolean;
  internal_notes: boolean;
};

type EffectiveAuxiliaryPanelArgs = {
  revisionPlacement: RevisionWorkspacePlacement;
  communicationPanel: CommunicationPanel;
  revisionWorkspaceAvailable: boolean;
};

const REVISION_PLACEMENT_STORAGE_KEY = 'claims-admin-revision-workspace-placement';
const AUXILIARY_PANEL_WIDTH_STORAGE_KEY = 'claims-admin-auxiliary-panel-width';
export const MIN_AUXILIARY_PANEL_WIDTH = 340;
export const MAX_AUXILIARY_PANEL_WIDTH = 640;
const DEFAULT_AUXILIARY_PANEL_WIDTH = 420;

export const normalizeRevisionWorkspacePlacement = (value: unknown): RevisionWorkspacePlacement =>
  value === 'side' ? 'side' : 'top';

export const toggledRevisionWorkspacePlacement = (current: RevisionWorkspacePlacement): RevisionWorkspacePlacement =>
  current === 'top' ? 'side' : 'top';

export const clampAuxiliaryPanelWidth = (value: number): number =>
  Math.min(MAX_AUXILIARY_PANEL_WIDTH, Math.max(MIN_AUXILIARY_PANEL_WIDTH, value));

const storedRevisionWorkspacePlacement = (): RevisionWorkspacePlacement =>
  typeof window === 'undefined'
    ? 'top'
    : normalizeRevisionWorkspacePlacement(window.localStorage.getItem(REVISION_PLACEMENT_STORAGE_KEY));

const storedAuxiliaryPanelWidth = (): number => {
  if (typeof window === 'undefined') return DEFAULT_AUXILIARY_PANEL_WIDTH;
  const storedWidth = Number(window.localStorage.getItem(AUXILIARY_PANEL_WIDTH_STORAGE_KEY));
  return Number.isFinite(storedWidth) &&
    storedWidth >= MIN_AUXILIARY_PANEL_WIDTH &&
    storedWidth <= MAX_AUXILIARY_PANEL_WIDTH
    ? storedWidth
    : DEFAULT_AUXILIARY_PANEL_WIDTH;
};

export const effectiveAuxiliaryPanelFor = ({
  revisionPlacement,
  communicationPanel,
  revisionWorkspaceAvailable,
}: EffectiveAuxiliaryPanelArgs): EffectiveAuxiliaryPanel => {
  if (communicationPanel) return communicationPanel;
  if (revisionPlacement === 'side' && revisionWorkspaceAvailable) return 'revision_issues';
  return null;
};

export const useInvoiceReviewLayout = () => {
  const [documentVisible, setDocumentVisible] = useState(true);
  const [revisionPlacement, setRevisionPlacement] = useState<RevisionWorkspacePlacement>(
    storedRevisionWorkspacePlacement,
  );
  const [communicationPanel, setCommunicationPanel] = useState<CommunicationPanel>(null);
  const [mountedCommunicationPanels, setMountedCommunicationPanels] = useState<MountedCommunicationPanels>({
    conversation: false,
    internal_notes: false,
  });
  const [auxiliaryPanelWidth, setAuxiliaryPanelWidthState] = useState(storedAuxiliaryPanelWidth);

  const toggleDocument = useCallback(() => setDocumentVisible((current) => !current), []);
  const showDocument = useCallback(() => setDocumentVisible(true), []);

  const toggleRevisionPlacement = useCallback(() => {
    const next = toggledRevisionWorkspacePlacement(revisionPlacement);
    setRevisionPlacement(next);
    window.localStorage.setItem(REVISION_PLACEMENT_STORAGE_KEY, next);
    if (next === 'side') setCommunicationPanel(null);
  }, [revisionPlacement]);

  const toggleCommunicationPanel = useCallback((panel: Exclude<CommunicationPanel, null>) => {
    setMountedCommunicationPanels((current) => ({ ...current, [panel]: true }));
    setCommunicationPanel((current) => (current === panel ? null : panel));
  }, []);

  const closeCommunicationPanel = useCallback(() => setCommunicationPanel(null), []);

  const showRevisionWorkspace = useCallback(() => {
    if (revisionPlacement === 'side') setCommunicationPanel(null);
  }, [revisionPlacement]);

  const effectiveAuxiliaryPanel = useCallback(
    ({ revisionWorkspaceAvailable }: { revisionWorkspaceAvailable: boolean }) =>
      effectiveAuxiliaryPanelFor({
        revisionPlacement,
        communicationPanel,
        revisionWorkspaceAvailable,
      }),
    [communicationPanel, revisionPlacement],
  );

  const setAuxiliaryPanelWidth = useCallback((value: number) => {
    const next = clampAuxiliaryPanelWidth(value);
    setAuxiliaryPanelWidthState(next);
    window.localStorage.setItem(AUXILIARY_PANEL_WIDTH_STORAGE_KEY, String(next));
  }, []);

  return {
    documentVisible,
    toggleDocument,
    showDocument,
    revisionPlacement,
    toggleRevisionPlacement,
    communicationPanel,
    toggleCommunicationPanel,
    closeCommunicationPanel,
    mountedCommunicationPanels,
    showRevisionWorkspace,
    effectiveAuxiliaryPanel,
    auxiliaryPanelWidth,
    setAuxiliaryPanelWidth,
  };
};
