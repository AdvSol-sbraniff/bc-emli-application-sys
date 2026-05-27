import {
  AlertDialog,
  AlertDialogBody,
  AlertDialogContent,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogOverlay,
  Box,
  Button,
  Container,
  Drawer,
  DrawerBody,
  DrawerCloseButton,
  DrawerContent,
  DrawerHeader,
  DrawerOverlay,
  Flex,
  Heading,
  IconButton,
  Input,
  Select,
  Spinner,
  Text,
  Textarea,
  Tooltip,
  useDisclosure,
} from '@chakra-ui/react';
import React, { useEffect, useMemo, useRef, useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { ArrowCounterClockwise, FloppyDiskBack, Question } from '@phosphor-icons/react';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';

type RulesetDto = {
  id: string;
  invoice_upgrade_type_id: string;
  upgrade_type_key?: string | null;
  upgrade_type_description?: string | null;
  ruleset_shortname: string;
  user_record1: string | null;
  is_current?: boolean;
  created_at?: string;
  updated_at?: string;
};

type UpgradeTypeDto = {
  id: string;
  upgrade_type_key: string;
  description?: string | null;
};

function useQueryParam(name: string): string | null {
  const { search } = useLocation();
  return useMemo(() => new URLSearchParams(search).get(name), [search, name]);
}

export default function RulesetEditorScreen() {
  const navigate = useNavigate();
  const id = useQueryParam('id');
  const mode = useQueryParam('mode');
  const duplicateFromId = useQueryParam('duplicate_from');
  const isCreateMode = mode === 'create' && Boolean(duplicateFromId);
  const isUnsupportedCreateMode = mode === 'create' && !duplicateFromId;
  const requestedReadOnlyMode = mode === 'view' || mode === 'read';

  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [isSaving, setIsSaving] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [ruleset, setRuleset] = useState<RulesetDto | null>(null);
  const [upgradeTypes, setUpgradeTypes] = useState<UpgradeTypeDto[]>([]);

  const { isOpen: isHelpOpen, onOpen: onHelpOpen, onClose: onHelpClose } = useDisclosure();
  const {
    isOpen: isSaveWarningOpen,
    onOpen: onSaveWarningOpen,
    onClose: onSaveWarningClose,
  } = useDisclosure();
  const cancelSaveRef = useRef<HTMLButtonElement | null>(null);

  const [shortname, setShortname] = useState<string>('');
  const [invoiceUpgradeTypeId, setInvoiceUpgradeTypeId] = useState<string>('');
  const [userRecord1, setUserRecord1] = useState<string>('');
  const [initialValues, setInitialValues] = useState({
    shortname: '',
    invoiceUpgradeTypeId: '',
    userRecord1: '',
  });

  const isDirty =
    shortname !== initialValues.shortname ||
    invoiceUpgradeTypeId !== initialValues.invoiceUpgradeTypeId ||
    userRecord1 !== initialValues.userRecord1;
  const isHistoricalRuleset = !isCreateMode && ruleset?.is_current === false;
  const isReadOnly = requestedReadOnlyMode || isHistoricalRuleset;

  function buildDuplicateShortname(originalShortname?: string | null): string {
    const base = (originalShortname || '').trim();
    if (!base) return 'changeme';
    return `${base}-changeme`;
  }

  async function loadUpgradeTypes() {
    const resp = await fetch('/api/claims/admin/invoice_upgrade_types', {
      method: 'GET',
      headers: { Accept: 'application/json' },
      credentials: 'include',
    });

    if (!resp.ok) {
      const txt = await resp.text();
      throw new Error(`GET upgrade types failed (${resp.status}): ${txt}`);
    }

    const data = await resp.json();
    const rows = Array.isArray(data?.rows) ? data.rows : [];
    setUpgradeTypes(rows);
    return rows as UpgradeTypeDto[];
  }

  async function load() {
    setIsLoading(true);
    setError(null);

    try {
      const loadedUpgradeTypes = await loadUpgradeTypes();
      const defaultUpgradeTypeId = loadedUpgradeTypes[0]?.id || '';

      if (isUnsupportedCreateMode) {
        setInitialValues({
          shortname: '',
          invoiceUpgradeTypeId: '',
          userRecord1: '',
        });
        setError('Standalone ruleset creation is disabled. Duplicate an existing ruleset instead.');
        return;
      }

      if (isCreateMode) {
        const resp = await fetch(`/api/claims/admin/validationgenai_rulesets/${duplicateFromId}`, {
          method: 'GET',
          headers: { Accept: 'application/json' },
          credentials: 'include',
        });

        if (!resp.ok) {
          const txt = await resp.text();
          throw new Error(`GET failed (${resp.status}): ${txt}`);
        }

        const sourceData: RulesetDto = await resp.json();
        const duplicatedShortname = buildDuplicateShortname(sourceData.ruleset_shortname);

        setRuleset(null);
        setShortname(duplicatedShortname);
        setInvoiceUpgradeTypeId(sourceData.invoice_upgrade_type_id || defaultUpgradeTypeId);
        setUserRecord1(sourceData.user_record1 ?? '');
        setInitialValues({
          shortname: duplicatedShortname,
          invoiceUpgradeTypeId: sourceData.invoice_upgrade_type_id || defaultUpgradeTypeId,
          userRecord1: sourceData.user_record1 ?? '',
        });
        return;
      }

      if (!id) {
        setError('Missing query param: id');
        return;
      }

      const resp = await fetch(`/api/claims/admin/validationgenai_rulesets/${id}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      if (!resp.ok) {
        const txt = await resp.text();
        throw new Error(`GET failed (${resp.status}): ${txt}`);
      }

      const data: RulesetDto = await resp.json();
      setRuleset(data);
      setShortname(data.ruleset_shortname ?? '');
      setInvoiceUpgradeTypeId(data.invoice_upgrade_type_id ?? '');
      setUserRecord1(data.user_record1 ?? '');
      setInitialValues({
        shortname: data.ruleset_shortname ?? '',
        invoiceUpgradeTypeId: data.invoice_upgrade_type_id ?? '',
        userRecord1: data.user_record1 ?? '',
      });
    } catch (e: any) {
      setError(e?.message ?? 'Load failed');
    } finally {
      setIsLoading(false);
    }
  }

  async function save() {
    if (isReadOnly) return;
    if (!isCreateMode && !id) return;

    const trimmedShortname = shortname.trim();
    if (!trimmedShortname) {
      setError('ruleset_shortname is required');
      return;
    }
    if (!invoiceUpgradeTypeId) {
      setError('upgrade type is required');
      return;
    }

    setIsSaving(true);
    setError(null);

    try {
      const endpoint = isCreateMode
        ? '/api/claims/admin/validationgenai_rulesets'
        : `/api/claims/admin/validationgenai_rulesets/${id}`;

      const method = isCreateMode ? 'POST' : 'PATCH';
      const body: Record<string, string> = {
        ruleset_shortname: trimmedShortname,
        user_record1: userRecord1,
      };
      if (isCreateMode) body.invoice_upgrade_type_id = invoiceUpgradeTypeId;

      const resp = await fetch(endpoint, {
        method,
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        credentials: 'include',
        body: JSON.stringify(body),
      });

      if (!resp.ok) {
        const txt = await resp.text();
        throw new Error(`${method} failed (${resp.status}): ${txt}`);
      }

      const data: RulesetDto = await resp.json();
      setRuleset(data);
      setShortname(data.ruleset_shortname ?? '');
      setInvoiceUpgradeTypeId(data.invoice_upgrade_type_id ?? '');
      setUserRecord1(data.user_record1 ?? '');
      setInitialValues({
        shortname: data.ruleset_shortname ?? '',
        invoiceUpgradeTypeId: data.invoice_upgrade_type_id ?? '',
        userRecord1: data.user_record1 ?? '',
      });

      if (isCreateMode) {
        navigate(`/ruleset-editor?id=${encodeURIComponent(data.id)}`, { replace: true });
      }
    } catch (e: any) {
      setError(e?.message ?? 'Save failed');
    } finally {
      setIsSaving(false);
    }
  }

  function requestSave() {
    if (isReadOnly) return;

    if (!isCreateMode && isDirty) {
      onSaveWarningOpen();
      return;
    }

    save();
  }

  async function confirmExistingRulesetSave() {
    onSaveWarningClose();
    await save();
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id, mode, duplicateFromId]);

  return (
    <Box>
      <ThinBlueTitleBar title={isReadOnly ? 'Ruleset Viewer' : 'Ruleset Editor'} />

      <Container maxW="6xl" py={6}>
        {!id && !isCreateMode && (
          <Box p={4} borderWidth="1px" borderRadius="md">
            <Text fontWeight="bold">{isUnsupportedCreateMode ? 'Standalone creation disabled' : 'Missing id'}</Text>
            <Text>Open an existing ruleset, or use Duplicate from the ruleset admin grid.</Text>
          </Box>
        )}

        {(id || isCreateMode) && (
          <Box>
            <Flex align="center" justify="space-between" mb={4}>
              <Heading size="md">
                {isReadOnly ? 'Ruleset (Read only)' : isCreateMode ? 'Ruleset (Duplicate)' : 'Ruleset'}
              </Heading>

              <Flex gap={2}>
                {!isReadOnly && (
                  <>
                    <Tooltip label="Undo unsaved changes by reloading the latest saved values from the database.">
                      <IconButton
                        aria-label="Undo unsaved changes"
                        icon={<ArrowCounterClockwise size={18} />}
                        variant="outline"
                        onClick={load}
                        isDisabled={isLoading || isSaving}
                      />
                    </Tooltip>
                    <Tooltip label="Save ruleset changes">
                      <IconButton
                        aria-label="Save ruleset"
                        icon={<FloppyDiskBack size={18} />}
                        colorScheme="blue"
                        onClick={requestSave}
                        isLoading={isSaving}
                        isDisabled={(!isDirty && !isCreateMode) || isLoading}
                      />
                    </Tooltip>
                  </>
                )}
                <Tooltip label="Help: ruleset layers and output mapping">
                  <IconButton
                    aria-label="Open ruleset editor help"
                    icon={<Question size={18} />}
                    variant="outline"
                    onClick={onHelpOpen}
                  />
                </Tooltip>
              </Flex>
            </Flex>

            {isLoading && (
              <Flex align="center" gap={3} p={4}>
                <Spinner />
                <Text>Loading...</Text>
              </Flex>
            )}

            {error && (
              <Box p={4} borderWidth="1px" borderRadius="md" mb={4}>
                <Text fontWeight="bold">Error</Text>
                <Text whiteSpace="pre-wrap">{error}</Text>
              </Box>
            )}

            {!isLoading && !error && (
              <Box>
                {isReadOnly && (
                  <Box p={4} borderWidth="1px" borderRadius="md" mb={4} bg="gray.50" borderColor="gray.200">
                    <Text fontWeight="bold" mb={1}>
                      {isHistoricalRuleset ? 'Read-only historical ruleset' : 'Read-only ruleset view'}
                    </Text>
                    <Text fontSize="sm" opacity={0.8}>
                      {isHistoricalRuleset
                        ? 'This ruleset is not the current runtime version for its upgrade type. It is locked so historical evaluations remain understandable and reproducible.'
                        : 'This ruleset was opened in view mode. Open the current ruleset from GenAI Rulesets Admin if an edit is required.'}
                    </Text>
                  </Box>
                )}

                <Box mb={4}>
                  <Text fontWeight="bold" mb={1}>
                    upgrade type
                  </Text>
                  <Select value={invoiceUpgradeTypeId} isDisabled>
                    {upgradeTypes.map((t) => (
                      <option key={t.id} value={t.id}>
                        {t.description || t.upgrade_type_key} ({t.upgrade_type_key})
                      </option>
                    ))}
                  </Select>
                  <Text fontSize="xs" opacity={0.7} mt={1}>
                    Upgrade type is locked. Duplicate the correct ruleset instead of moving a ruleset between upgrade
                    types.
                  </Text>
                </Box>

                <Box mb={4}>
                  <Text fontWeight="bold" mb={1}>
                    ruleset_shortname
                  </Text>
                  <Input value={shortname} onChange={(e) => setShortname(e.target.value)} isReadOnly={isReadOnly} />
                </Box>

                <Box borderWidth="1px" borderRadius="lg" p={3} mb={4} bg="white">
                  <Text fontWeight="bold" mb={2}>
                    user_record1
                  </Text>
                  <Text fontSize="sm" opacity={0.75} mb={3}>
                    Located fields and rulechecks for this ruleset. Common invoice evidence now lives in the common
                    ruleset row.
                  </Text>
                  <Textarea
                    value={userRecord1}
                    onChange={(e) => setUserRecord1(e.target.value)}
                    minH="520px"
                    isReadOnly={isReadOnly}
                  />
                </Box>

                <Flex justify="space-between" mt={2}>
                  <Text fontSize="sm" opacity={0.8}>
                    {isReadOnly ? 'Read only' : isDirty ? 'Unsaved changes' : 'Saved'}
                  </Text>
                  <Text fontSize="sm" opacity={0.8}>
                    {ruleset?.updated_at ? `updated_at: ${ruleset.updated_at}` : ''}
                  </Text>
                </Flex>
              </Box>
            )}
          </Box>
        )}
      </Container>

      <AlertDialog
        isOpen={isSaveWarningOpen}
        leastDestructiveRef={cancelSaveRef}
        onClose={onSaveWarningClose}
        isCentered
      >
        <AlertDialogOverlay>
          <AlertDialogContent>
            <AlertDialogHeader fontSize="lg" fontWeight="bold">
              Confirm existing ruleset edit
            </AlertDialogHeader>

            <AlertDialogBody>
              <Text mb={3}>
                Editing an existing GenAI ruleset changes the rule text that future invoice evaluations will use.
                Existing evaluations were produced with the previous wording, so changing this row can make historical
                results harder to interpret or reproduce.
              </Text>
              <Text mb={3}>
                This should normally only be done in a test environment. For production-like use, the safer pattern is
                to duplicate the ruleset, test the copy, and move forward with the new version instead.
              </Text>
              <Text fontWeight="semibold">Only continue if you intentionally want to update this existing ruleset.</Text>
            </AlertDialogBody>

            <AlertDialogFooter>
              <Button ref={cancelSaveRef} onClick={onSaveWarningClose} variant="outline">
                Cancel
              </Button>
              <Button colorScheme="orange" onClick={confirmExistingRulesetSave} ml={3} isLoading={isSaving}>
                Save existing ruleset
              </Button>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialogOverlay>
      </AlertDialog>

      <Drawer isOpen={isHelpOpen} placement="left" onClose={onHelpClose} size="xl">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Ruleset Editor Help</DrawerHeader>
          <DrawerBody>
            <Flex direction="column" gap={4}>
              <Box>
                <Heading size="sm" mb={2}>
                  Big Picture
                </Heading>
                <Text fontSize="sm">
                  This page edits one ruleset. The shared system prompt and final advice wrapper are edited separately
                  in AI System Config.
                </Text>
              </Box>

              <Box>
                <Heading size="sm" mb={2}>
                  What Lives Here
                </Heading>
                <Text fontSize="sm">
                  user_record1 should contain the fields and rulechecks for this ruleset. The common invoice evidence
                  rules now live in the common ruleset row.
                </Text>
              </Box>

              <Box>
                <Heading size="sm" mb={2}>
                  What Happens At Runtime
                </Heading>
                <Text fontSize="sm">
                  The GenAI call receives system_record from AI System Config, then this ruleset&apos;s user_record1, then
                  the invoice OCR and case facts. In the multi-type flow, the common ruleset runs as its own call.
                </Text>
              </Box>

              <Box>
                <Heading size="sm" mb={2}>
                  Safe Editing Pattern
                </Heading>
                <Text fontSize="sm">
                  Prefer duplicating an existing ruleset, editing the copy, testing it, and only then using it for real
                  invoice runs.
                </Text>
              </Box>
            </Flex>
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Box>
  );
}
