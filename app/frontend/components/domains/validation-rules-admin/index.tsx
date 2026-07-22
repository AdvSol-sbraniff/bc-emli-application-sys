import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Badge,
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
  Grid,
  GridItem,
  HStack,
  IconButton,
  Spinner,
  Tab,
  TabList,
  TabPanel,
  TabPanels,
  Table,
  Tabs,
  Tbody,
  Td,
  Text,
  Th,
  Thead,
  Tooltip,
  Tr,
  VStack,
  useDisclosure,
} from '@chakra-ui/react';
import { ClockCounterClockwise, Info, PencilSimple, Plus } from '@phosphor-icons/react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import {
  CodeLocatedFieldEditorScreen,
  CodeRuleEditorScreen,
  GenaiLocatedFieldEditorScreen,
  GenaiRuleEditorScreen,
} from './editor-screens';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { getInvoiceUpgradeTypeMeta, InvoiceUpgradeTypeTile } from '../../shared/claims/invoice-upgrade-type-visual';

type RecordType = 'code_rule' | 'code_located_field' | 'genai_rule' | 'genai_located_field';

type UpgradeTypeRow = {
  id: string;
  upgrade_type_key: string;
  description?: string | null;
  code_rules_count?: number;
  code_fields_count?: number;
  genai_rules_count?: number;
  genai_fields_count?: number;
};

type MappingRow = {
  id?: string;
  invoice_upgrade_type_id: string;
  field_number?: number;
};

type ValidationRow = {
  id: string;
  record_type: RecordType;
  record_key: string;
  enabled: boolean;
  updated_at?: string | null;
  created_at?: string | null;
  upgrade_types: UpgradeTypeRow[];
  detail: Record<string, any>;
  mappings: MappingRow[];
};

type HistoryPayload = {
  row_history: Record<string, any>[];
  mapping_history: Record<string, any>[];
};

type MappingEditorRow = {
  invoice_upgrade_type_id: string;
  label: string;
  checked: boolean;
};

type BaseEditorState = {
  recordType: RecordType;
  recordId?: string;
  recordKey: string;
  enabled: boolean;
  mappings: MappingEditorRow[];
};

type CodeRuleEditorState = BaseEditorState & {
  recordType: 'code_rule';
  contractorDisplayName: string;
  description: string;
  sourceQuote: string;
  contractorVisibility: string;
  contractorBlockingPolicy: string;
  adminWorkflowPolicy: string;
  passAdminMessage: string;
  warnAdminMessage: string;
  failAdminMessage: string;
  infoAdminMessage: string;
  adminNotes: string;
};

type CodeLocatedFieldEditorState = BaseEditorState & {
  recordType: 'code_located_field';
  contractorDisplayName: string;
  description: string;
};

type GenaiRuleEditorState = BaseEditorState & {
  recordType: 'genai_rule';
  contractorDisplayName: string;
  promptText: string;
  sourceQuote: string;
  contractorVisibility: string;
  contractorBlockingPolicy: string;
  adminWorkflowPolicy: string;
};

type GenaiLocatedFieldEditorState = BaseEditorState & {
  recordType: 'genai_located_field';
  contractorDisplayName: string;
  promptText: string;
};

type EditorState =
  | CodeRuleEditorState
  | CodeLocatedFieldEditorState
  | GenaiRuleEditorState
  | GenaiLocatedFieldEditorState;

const TYPE_LABELS: Record<RecordType, string> = {
  code_rule: 'Code Rules',
  code_located_field: 'Code Fields',
  genai_rule: 'GenAI Rules',
  genai_located_field: 'GenAI Fields',
};

const EDITOR_LABELS: Record<RecordType, string> = {
  code_rule: 'Code Rule',
  code_located_field: 'Code Field',
  genai_rule: 'GenAI Rule',
  genai_located_field: 'GenAI Field',
};

const TAB_ORDER: RecordType[] = ['code_rule', 'code_located_field', 'genai_rule', 'genai_located_field'];

const CREATEABLE_RECORD_TYPES: RecordType[] = ['genai_rule', 'genai_located_field'];

const fmtDate = (value?: string | null) => {
  if (!value) return '';
  const str = String(value);
  return str.includes('T') ? str.split('T')[0] : str.slice(0, 10);
};

const isCodeRuleEditor = (editor: EditorState): editor is CodeRuleEditorState => editor.recordType === 'code_rule';

const isCodeLocatedFieldEditor = (editor: EditorState): editor is CodeLocatedFieldEditorState =>
  editor.recordType === 'code_located_field';

const isGenaiRuleEditor = (editor: EditorState): editor is GenaiRuleEditorState => editor.recordType === 'genai_rule';

const isGenaiLocatedFieldEditor = (editor: EditorState): editor is GenaiLocatedFieldEditorState =>
  editor.recordType === 'genai_located_field';

const buildSearchParams = (obj: Record<string, string | undefined>) => {
  const params = new URLSearchParams();
  Object.entries(obj).forEach(([key, value]) => {
    const next = value?.toString().trim();
    if (next) params.set(key, next);
  });
  return params;
};

function HistorySection({ title, rows }: { title: string; rows: Record<string, any>[] }) {
  return (
    <Box>
      <Text fontWeight="bold" mb={2}>
        {title}
      </Text>
      {rows.length === 0 ? (
        <Text fontSize="sm" opacity={0.7}>
          No history yet.
        </Text>
      ) : (
        <VStack align="stretch" spacing={3}>
          {rows.map((row, index) => (
            <Box key={`${title}-${index}`} borderWidth="1px" borderRadius="md" p={3} bg="gray.50">
              {Object.entries(row).map(([key, value]) => (
                <Text key={key} fontSize="sm">
                  <Text as="span" fontWeight="semibold">
                    {key}:
                  </Text>{' '}
                  {value === null || value === undefined || value === '' ? 'n/a' : String(value)}
                </Text>
              ))}
            </Box>
          ))}
        </VStack>
      )}
    </Box>
  );
}

export default function ValidationRulesAdminScreen() {
  const infoDrawer = useDisclosure();
  const auditDrawer = useDisclosure();
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();

  const selectedUpgradeTypeId = searchParams.get('invoice_upgrade_type_id') || '';
  const editorMode = searchParams.get('mode') || '';
  const editorRecordTypeParam = (searchParams.get('record_type') as RecordType | null) || null;
  const editorRecordId = searchParams.get('record_id') || '';

  const [upgradeTypes, setUpgradeTypes] = useState<UpgradeTypeRow[]>([]);
  const [rows, setRows] = useState<ValidationRow[]>([]);
  const [history, setHistory] = useState<HistoryPayload>({
    row_history: [],
    mapping_history: [],
  });
  const [selectedRow, setSelectedRow] = useState<ValidationRow | null>(null);
  const [editor, setEditor] = useState<EditorState | null>(null);
  const [loadingUpgradeTypes, setLoadingUpgradeTypes] = useState(false);
  const [loadingRows, setLoadingRows] = useState(false);
  const [loadingHistory, setLoadingHistory] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const selectedUpgradeType = useMemo(
    () => upgradeTypes.find((item) => item.id === selectedUpgradeTypeId) || null,
    [selectedUpgradeTypeId, upgradeTypes],
  );
  const isEditorScreen = editorMode === 'create' || editorMode === 'edit';
  const editorBannerTitle =
    editor && isEditorScreen
      ? `${editorMode === 'create' ? 'Add' : 'Edit'} ${EDITOR_LABELS[editor.recordType]}`
      : editorMode === 'create'
        ? 'Add Validation Record'
        : 'Edit Validation Record';

  const fetchUpgradeTypes = useCallback(async () => {
    setLoadingUpgradeTypes(true);
    try {
      const res = await fetch('/api/claims/admin/validation_rules/upgrade_types', {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data = await res.json().catch(() => ({ rows: [] }));
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
      setUpgradeTypes(Array.isArray(data?.rows) ? data.rows : []);
    } catch (e: any) {
      setError(e?.message || 'Failed to load upgrade types.');
      setUpgradeTypes([]);
    } finally {
      setLoadingUpgradeTypes(false);
    }
  }, []);

  const fetchRows = useCallback(async () => {
    if (!selectedUpgradeTypeId) return;

    setLoadingRows(true);
    setError('');

    try {
      const params = buildSearchParams({
        invoice_upgrade_type_id: selectedUpgradeTypeId,
      });

      const res = await fetch(`/api/claims/admin/validation_rules?${params.toString()}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data = await res.json().catch(() => ({ rows: [] }));
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
      setRows(Array.isArray(data?.rows) ? data.rows : []);
    } catch (e: any) {
      setRows([]);
      setError(e?.message || 'Failed to load validation records.');
    } finally {
      setLoadingRows(false);
    }
  }, [selectedUpgradeTypeId]);

  useEffect(() => {
    fetchUpgradeTypes();
  }, [fetchUpgradeTypes]);

  useEffect(() => {
    fetchRows();
  }, [fetchRows]);

  const tabRows = useMemo(() => {
    return TAB_ORDER.reduce(
      (acc, key) => {
        acc[key] = rows.filter((row) => row.record_type === key);
        return acc;
      },
      {} as Record<RecordType, ValidationRow[]>,
    );
  }, [rows]);

  const emptyEditor = useCallback(
    (recordType: RecordType): EditorState => {
      const mappings = upgradeTypes.map((type) => ({
        invoice_upgrade_type_id: type.id,
        label: type.description || type.upgrade_type_key,
        checked: recordType === 'code_located_field' ? false : selectedUpgradeTypeId === type.id,
      }));

      switch (recordType) {
        case 'code_rule':
          return {
            recordType,
            recordKey: '',
            enabled: true,
            contractorDisplayName: '',
            description: '',
            sourceQuote: '',
            contractorVisibility: 'fail_only',
            contractorBlockingPolicy: 'non_blocking',
            adminWorkflowPolicy: 'fail_only',
            passAdminMessage: '',
            warnAdminMessage: '',
            failAdminMessage: '',
            infoAdminMessage: '',
            adminNotes: '',
            mappings,
          };
        case 'code_located_field':
          return {
            recordType,
            recordKey: '',
            enabled: true,
            contractorDisplayName: '',
            description: '',
            mappings,
          };
        case 'genai_rule':
          return {
            recordType,
            recordKey: '',
            enabled: true,
            contractorDisplayName: '',
            promptText: '',
            sourceQuote: '',
            contractorVisibility: 'fail_only',
            contractorBlockingPolicy: 'non_blocking',
            adminWorkflowPolicy: 'fail_only',
            mappings,
          };
        case 'genai_located_field':
          return {
            recordType,
            recordKey: '',
            enabled: true,
            contractorDisplayName: '',
            promptText: '',
            mappings,
          };
      }
    },
    [selectedUpgradeTypeId, upgradeTypes],
  );

  const hydrateMappings = useCallback(
    (recordType: RecordType, row: ValidationRow | null): MappingEditorRow[] =>
      upgradeTypes.map((type) => {
        const mapping = row?.mappings.find((item) => item.invoice_upgrade_type_id === type.id);

        return {
          invoice_upgrade_type_id: type.id,
          label: type.description || type.upgrade_type_key,
          checked: Boolean(mapping),
        };
      }),
    [upgradeTypes],
  );

  const editorSearchParams = useCallback(
    (params: Record<string, string | undefined>) =>
      buildSearchParams({
        invoice_upgrade_type_id: selectedUpgradeTypeId || undefined,
        ...params,
      }),
    [selectedUpgradeTypeId],
  );

  const closeEditorScreen = useCallback(() => {
    setSearchParams(editorSearchParams({}));
    setEditor(null);
    setSelectedRow(null);
  }, [editorSearchParams, setSearchParams]);

  const openCreate = (recordType: RecordType) => {
    if (!CREATEABLE_RECORD_TYPES.includes(recordType)) return;
    setSelectedRow(null);
    setEditor(emptyEditor(recordType));
    setSearchParams(
      editorSearchParams({
        mode: 'create',
        record_type: recordType,
      }),
    );
  };

  const openEdit = (row: ValidationRow) => {
    setSelectedRow(row);
    const mappings = hydrateMappings(row.record_type, row);
    switch (row.record_type) {
      case 'code_rule':
        setEditor({
          recordType: row.record_type,
          recordId: row.id,
          recordKey: row.record_key,
          enabled: Boolean(row.enabled),
          contractorDisplayName: row.detail?.contractor_display_name || '',
          description: row.detail?.description || '',
          sourceQuote: row.detail?.source_quote || '',
          contractorVisibility: row.detail?.contractor_visibility || 'fail_only',
          contractorBlockingPolicy: row.detail?.contractor_blocking_policy || 'non_blocking',
          adminWorkflowPolicy: row.detail?.admin_workflow_policy || 'fail_only',
          passAdminMessage: row.detail?.pass_admin_message || '',
          warnAdminMessage: row.detail?.warn_admin_message || '',
          failAdminMessage: row.detail?.fail_admin_message || '',
          infoAdminMessage: row.detail?.info_admin_message || '',
          adminNotes: row.detail?.admin_notes || '',
          mappings,
        });
        break;
      case 'code_located_field':
        setEditor({
          recordType: row.record_type,
          recordId: row.id,
          recordKey: row.record_key,
          enabled: Boolean(row.enabled),
          contractorDisplayName: row.detail?.contractor_display_name || '',
          description: row.detail?.description || '',
          mappings,
        });
        break;
      case 'genai_rule':
        setEditor({
          recordType: row.record_type,
          recordId: row.id,
          recordKey: row.record_key,
          enabled: Boolean(row.enabled),
          contractorDisplayName: row.detail?.contractor_display_name || '',
          promptText: row.detail?.prompt_text || '',
          sourceQuote: row.detail?.source_quote || '',
          contractorVisibility: row.detail?.contractor_visibility || 'fail_only',
          contractorBlockingPolicy: row.detail?.contractor_blocking_policy || 'non_blocking',
          adminWorkflowPolicy: row.detail?.admin_workflow_policy || 'fail_only',
          mappings,
        });
        break;
      case 'genai_located_field':
        setEditor({
          recordType: row.record_type,
          recordId: row.id,
          recordKey: row.record_key,
          enabled: Boolean(row.enabled),
          contractorDisplayName: row.detail?.contractor_display_name || '',
          promptText: row.detail?.prompt_text || '',
          mappings,
        });
        break;
    }
    setSearchParams(
      editorSearchParams({
        mode: 'edit',
        record_type: row.record_type,
        record_id: row.id,
      }),
    );
  };

  const openInfo = (row: ValidationRow) => {
    setSelectedRow(row);
    infoDrawer.onOpen();
  };

  const openAudit = async (row: ValidationRow) => {
    setSelectedRow(row);
    setLoadingHistory(true);
    setHistory({ row_history: [], mapping_history: [] });
    auditDrawer.onOpen();

    try {
      const res = await fetch(
        `/api/claims/admin/validation_rules/${encodeURIComponent(
          row.record_type,
        )}/${encodeURIComponent(row.id)}/history`,
        {
          method: 'GET',
          headers: { Accept: 'application/json' },
          credentials: 'include',
        },
      );
      const data = await res.json().catch(() => ({
        row_history: [],
        mapping_history: [],
      }));
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
      setHistory({
        row_history: Array.isArray(data?.row_history) ? data.row_history : [],
        mapping_history: Array.isArray(data?.mapping_history) ? data.mapping_history : [],
      });
    } catch (e: any) {
      setHistory({
        row_history: [{ error: e?.message || 'Failed to load history.' }],
        mapping_history: [],
      });
    } finally {
      setLoadingHistory(false);
    }
  };

  const setEditorField = useCallback((mutator: (current: EditorState) => EditorState) => {
    setEditor((current) => (current ? mutator(current) : current));
  }, []);

  useEffect(() => {
    if (!isEditorScreen || !selectedUpgradeTypeId || editor) return;

    if (editorMode === 'create' && editorRecordTypeParam) {
      if (CREATEABLE_RECORD_TYPES.includes(editorRecordTypeParam)) {
        setEditor(emptyEditor(editorRecordTypeParam));
      }
      return;
    }

    if (editorMode === 'edit' && editorRecordTypeParam && editorRecordId) {
      const row = rows.find((item) => item.record_type === editorRecordTypeParam && item.id === editorRecordId);
      if (!row) return;

      setSelectedRow(row);
      const mappings = hydrateMappings(row.record_type, row);
      switch (row.record_type) {
        case 'code_rule':
          setEditor({
            recordType: row.record_type,
            recordId: row.id,
            recordKey: row.record_key,
            enabled: Boolean(row.enabled),
            contractorDisplayName: row.detail?.contractor_display_name || '',
            description: row.detail?.description || '',
            sourceQuote: row.detail?.source_quote || '',
            contractorVisibility: row.detail?.contractor_visibility || 'fail_only',
            contractorBlockingPolicy: row.detail?.contractor_blocking_policy || 'non_blocking',
            adminWorkflowPolicy: row.detail?.admin_workflow_policy || 'fail_only',
            passAdminMessage: row.detail?.pass_admin_message || '',
            warnAdminMessage: row.detail?.warn_admin_message || '',
            failAdminMessage: row.detail?.fail_admin_message || '',
            infoAdminMessage: row.detail?.info_admin_message || '',
            adminNotes: row.detail?.admin_notes || '',
            mappings,
          });
          break;
        case 'code_located_field':
          setEditor({
            recordType: row.record_type,
            recordId: row.id,
            recordKey: row.record_key,
            enabled: Boolean(row.enabled),
            contractorDisplayName: row.detail?.contractor_display_name || '',
            description: row.detail?.description || '',
            mappings,
          });
          break;
        case 'genai_rule':
          setEditor({
            recordType: row.record_type,
            recordId: row.id,
            recordKey: row.record_key,
            enabled: Boolean(row.enabled),
            contractorDisplayName: row.detail?.contractor_display_name || '',
            promptText: row.detail?.prompt_text || '',
            sourceQuote: row.detail?.source_quote || '',
            contractorVisibility: row.detail?.contractor_visibility || 'fail_only',
            contractorBlockingPolicy: row.detail?.contractor_blocking_policy || 'non_blocking',
            adminWorkflowPolicy: row.detail?.admin_workflow_policy || 'fail_only',
            mappings,
          });
          break;
        case 'genai_located_field':
          setEditor({
            recordType: row.record_type,
            recordId: row.id,
            recordKey: row.record_key,
            enabled: Boolean(row.enabled),
            contractorDisplayName: row.detail?.contractor_display_name || '',
            promptText: row.detail?.prompt_text || '',
            mappings,
          });
          break;
      }
    }
  }, [
    editor,
    editorMode,
    editorRecordId,
    editorRecordTypeParam,
    emptyEditor,
    hydrateMappings,
    isEditorScreen,
    rows,
    selectedUpgradeTypeId,
  ]);

  const updateMapping = (invoiceUpgradeTypeId: string, patch: Partial<MappingEditorRow>) => {
    setEditor((current) =>
      current
        ? {
            ...current,
            mappings: current.mappings.map((row) =>
              row.invoice_upgrade_type_id === invoiceUpgradeTypeId ? { ...row, ...patch } : row,
            ),
          }
        : current,
    );
  };

  const saveEditor = async () => {
    if (!editor) return;

    setSaving(true);
    setError('');

    try {
      const mappings = editor.mappings
        .filter((row) => row.checked)
        .map((row) => ({
          invoice_upgrade_type_id: row.invoice_upgrade_type_id,
        }));

      const body: Record<string, any> = { enabled: editor.enabled };

      if (editor.recordType === 'code_rule') {
        body.code_rule_key = editor.recordKey;
        body.contractor_display_name = editor.contractorDisplayName;
        body.description = editor.description;
        body.source_quote = editor.sourceQuote;
        body.contractor_visibility = editor.contractorVisibility;
        body.contractor_blocking_policy = editor.contractorBlockingPolicy;
        body.admin_workflow_policy = editor.adminWorkflowPolicy;
        body.pass_admin_message = editor.passAdminMessage;
        body.warn_admin_message = editor.warnAdminMessage;
        body.fail_admin_message = editor.failAdminMessage;
        body.info_admin_message = editor.infoAdminMessage;
        body.admin_notes = editor.adminNotes;
        body.mappings = mappings;
      } else if (editor.recordType === 'code_located_field') {
        body.code_field_key = editor.recordKey;
        body.contractor_display_name = editor.contractorDisplayName;
        body.description = editor.description;
      } else if (editor.recordType === 'genai_rule') {
        body.genai_rule_key = editor.recordKey;
        body.contractor_display_name = editor.contractorDisplayName;
        body.prompt_text = editor.promptText;
        body.source_quote = editor.sourceQuote;
        body.contractor_visibility = editor.contractorVisibility;
        body.contractor_blocking_policy = editor.contractorBlockingPolicy;
        body.admin_workflow_policy = editor.adminWorkflowPolicy;
        body.mappings = mappings;
      } else if (editor.recordType === 'genai_located_field') {
        body.genai_field_key = editor.recordKey;
        body.contractor_display_name = editor.contractorDisplayName;
        body.prompt_text = editor.promptText;
        body.mappings = mappings;
      }

      const isCreate = !editor.recordId;
      const endpoint = isCreate
        ? `/api/claims/admin/validation_rules/${encodeURIComponent(editor.recordType)}`
        : `/api/claims/admin/validation_rules/${encodeURIComponent(
            editor.recordType,
          )}/${encodeURIComponent(editor.recordId || '')}`;

      const res = await fetch(endpoint, {
        method: isCreate ? 'POST' : 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
        },
        credentials: 'include',
        body: JSON.stringify(body),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);

      await fetchRows();
      closeEditorScreen();
    } catch (e: any) {
      setError(e?.message || 'Failed to save validation record.');
    } finally {
      setSaving(false);
    }
  };

  const openUpgradeType = (upgradeTypeId: string) => {
    setSearchParams({ invoice_upgrade_type_id: upgradeTypeId });
  };

  if (!selectedUpgradeTypeId) {
    return (
      <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
        <ThinBlueTitleBar title="Fields and Advice Editor" />
        <Container maxW="container.xl" pb={4} flex="1" pt={6}>
          <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
            <Flex justify="space-between" align={{ base: 'start', md: 'center' }} gap={3} mb={4}>
              <Box />
              <HStack spacing={3} flexWrap="wrap" justify="end">
                <Button
                  colorScheme="blue"
                  variant="outline"
                  onClick={() => navigate('/validation-rules-alphabetic-admin')}
                >
                  Advice Checks at a Glance
                </Button>
              </HStack>
            </Flex>

            {loadingUpgradeTypes ? (
              <Flex py={10} justify="center">
                <Spinner />
              </Flex>
            ) : (
              <Grid templateColumns="repeat(auto-fit, minmax(260px, 1fr))" gap={4}>
                {upgradeTypes.map((upgradeType) => {
                  const meta = getInvoiceUpgradeTypeMeta(upgradeType.upgrade_type_key, upgradeType.description);

                  return (
                    <GridItem key={upgradeType.id}>
                      <Box
                        borderWidth="1px"
                        borderRadius="xl"
                        p={5}
                        bg="white"
                        boxShadow="sm"
                        borderColor={meta.border}
                      >
                        <HStack align="start" spacing={4} mb={4}>
                          <InvoiceUpgradeTypeTile
                            upgradeTypeKey={upgradeType.upgrade_type_key}
                            description={upgradeType.description}
                            size={44}
                          />
                          <Box>
                            <Button
                              variant="link"
                              fontWeight="bold"
                              whiteSpace="normal"
                              textAlign="left"
                              justifyContent="flex-start"
                              height="auto"
                              minH="unset"
                              p={0}
                              onClick={() => openUpgradeType(upgradeType.id)}
                            >
                              {upgradeType.description || meta.label}
                            </Button>
                          </Box>
                        </HStack>
                      </Box>
                    </GridItem>
                  );
                })}
              </Grid>
            )}
          </Box>
        </Container>
      </Flex>
    );
  }

  if (isEditorScreen) {
    return (
      <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
        <ThinBlueTitleBar title={editorBannerTitle} />
        <Container maxW="container.lg" pb={4} flex="1" pt={6}>
          <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
            {editor ? (
              isCodeRuleEditor(editor) ? (
                <CodeRuleEditorScreen
                  recordKeyReadOnly={Boolean(editor.recordId)}
                  recordKey={editor.recordKey}
                  enabled={editor.enabled}
                  contractorDisplayName={editor.contractorDisplayName}
                  description={editor.description}
                  sourceQuote={editor.sourceQuote}
                  contractorVisibility={editor.contractorVisibility}
                  contractorBlockingPolicy={editor.contractorBlockingPolicy}
                  adminWorkflowPolicy={editor.adminWorkflowPolicy}
                  passAdminMessage={editor.passAdminMessage}
                  warnAdminMessage={editor.warnAdminMessage}
                  failAdminMessage={editor.failAdminMessage}
                  infoAdminMessage={editor.infoAdminMessage}
                  adminNotes={editor.adminNotes}
                  mappings={editor.mappings}
                  selectedUpgradeTypeId={selectedUpgradeTypeId}
                  onEnabledChange={(next) =>
                    setEditorField((current) => (isCodeRuleEditor(current) ? { ...current, enabled: next } : current))
                  }
                  onRecordKeyChange={(next) =>
                    setEditorField((current) => (isCodeRuleEditor(current) ? { ...current, recordKey: next } : current))
                  }
                  onContractorDisplayNameChange={(next) =>
                    setEditorField((current) =>
                      isCodeRuleEditor(current) ? { ...current, contractorDisplayName: next } : current,
                    )
                  }
                  onDescriptionChange={(next) =>
                    setEditorField((current) =>
                      isCodeRuleEditor(current) ? { ...current, description: next } : current,
                    )
                  }
                  onSourceQuoteChange={(next) =>
                    setEditorField((current) =>
                      isCodeRuleEditor(current) ? { ...current, sourceQuote: next } : current,
                    )
                  }
                  onContractorVisibilityChange={(next) =>
                    setEditorField((current) =>
                      isCodeRuleEditor(current) ? { ...current, contractorVisibility: next } : current,
                    )
                  }
                  onContractorBlockingPolicyChange={(next) =>
                    setEditorField((current) =>
                      isCodeRuleEditor(current) ? { ...current, contractorBlockingPolicy: next } : current,
                    )
                  }
                  onAdminWorkflowPolicyChange={(next) =>
                    setEditorField((current) =>
                      isCodeRuleEditor(current) ? { ...current, adminWorkflowPolicy: next } : current,
                    )
                  }
                  onPassAdminMessageChange={(next) =>
                    setEditorField((current) =>
                      isCodeRuleEditor(current) ? { ...current, passAdminMessage: next } : current,
                    )
                  }
                  onWarnAdminMessageChange={(next) =>
                    setEditorField((current) =>
                      isCodeRuleEditor(current) ? { ...current, warnAdminMessage: next } : current,
                    )
                  }
                  onFailAdminMessageChange={(next) =>
                    setEditorField((current) =>
                      isCodeRuleEditor(current) ? { ...current, failAdminMessage: next } : current,
                    )
                  }
                  onInfoAdminMessageChange={(next) =>
                    setEditorField((current) =>
                      isCodeRuleEditor(current) ? { ...current, infoAdminMessage: next } : current,
                    )
                  }
                  onAdminNotesChange={(next) =>
                    setEditorField((current) =>
                      isCodeRuleEditor(current) ? { ...current, adminNotes: next } : current,
                    )
                  }
                  onMappingCheckedChange={(invoiceUpgradeTypeId, checked) =>
                    updateMapping(invoiceUpgradeTypeId, { checked })
                  }
                  onCancel={closeEditorScreen}
                  onSave={saveEditor}
                  saving={saving}
                />
              ) : isCodeLocatedFieldEditor(editor) ? (
                <CodeLocatedFieldEditorScreen
                  recordKeyReadOnly={Boolean(editor.recordId)}
                  recordKey={editor.recordKey}
                  enabled={editor.enabled}
                  contractorDisplayName={editor.contractorDisplayName}
                  description={editor.description}
                  mappings={editor.mappings}
                  selectedUpgradeTypeId={selectedUpgradeTypeId}
                  onEnabledChange={(next) =>
                    setEditorField((current) =>
                      isCodeLocatedFieldEditor(current) ? { ...current, enabled: next } : current,
                    )
                  }
                  onRecordKeyChange={(next) =>
                    setEditorField((current) =>
                      isCodeLocatedFieldEditor(current) ? { ...current, recordKey: next } : current,
                    )
                  }
                  onContractorDisplayNameChange={(next) =>
                    setEditorField((current) =>
                      isCodeLocatedFieldEditor(current) ? { ...current, contractorDisplayName: next } : current,
                    )
                  }
                  onDescriptionChange={(next) =>
                    setEditorField((current) =>
                      isCodeLocatedFieldEditor(current) ? { ...current, description: next } : current,
                    )
                  }
                  onMappingCheckedChange={(invoiceUpgradeTypeId, checked) =>
                    updateMapping(invoiceUpgradeTypeId, { checked })
                  }
                  onCancel={closeEditorScreen}
                  onSave={saveEditor}
                  saving={saving}
                />
              ) : isGenaiRuleEditor(editor) ? (
                <GenaiRuleEditorScreen
                  recordKeyReadOnly={Boolean(editor.recordId)}
                  recordKey={editor.recordKey}
                  enabled={editor.enabled}
                  contractorDisplayName={editor.contractorDisplayName}
                  promptText={editor.promptText}
                  sourceQuote={editor.sourceQuote}
                  contractorVisibility={editor.contractorVisibility}
                  contractorBlockingPolicy={editor.contractorBlockingPolicy}
                  adminWorkflowPolicy={editor.adminWorkflowPolicy}
                  mappings={editor.mappings}
                  selectedUpgradeTypeId={selectedUpgradeTypeId}
                  onEnabledChange={(next) =>
                    setEditorField((current) => (isGenaiRuleEditor(current) ? { ...current, enabled: next } : current))
                  }
                  onRecordKeyChange={(next) =>
                    setEditorField((current) =>
                      isGenaiRuleEditor(current) ? { ...current, recordKey: next } : current,
                    )
                  }
                  onContractorDisplayNameChange={(next) =>
                    setEditorField((current) =>
                      isGenaiRuleEditor(current) ? { ...current, contractorDisplayName: next } : current,
                    )
                  }
                  onPromptTextChange={(next) =>
                    setEditorField((current) =>
                      isGenaiRuleEditor(current) ? { ...current, promptText: next } : current,
                    )
                  }
                  onSourceQuoteChange={(next) =>
                    setEditorField((current) =>
                      isGenaiRuleEditor(current) ? { ...current, sourceQuote: next } : current,
                    )
                  }
                  onContractorVisibilityChange={(next) =>
                    setEditorField((current) =>
                      isGenaiRuleEditor(current) ? { ...current, contractorVisibility: next } : current,
                    )
                  }
                  onContractorBlockingPolicyChange={(next) =>
                    setEditorField((current) =>
                      isGenaiRuleEditor(current) ? { ...current, contractorBlockingPolicy: next } : current,
                    )
                  }
                  onAdminWorkflowPolicyChange={(next) =>
                    setEditorField((current) =>
                      isGenaiRuleEditor(current) ? { ...current, adminWorkflowPolicy: next } : current,
                    )
                  }
                  onMappingCheckedChange={(invoiceUpgradeTypeId, checked) =>
                    updateMapping(invoiceUpgradeTypeId, { checked })
                  }
                  onCancel={closeEditorScreen}
                  onSave={saveEditor}
                  saving={saving}
                />
              ) : (
                <GenaiLocatedFieldEditorScreen
                  recordKeyReadOnly={Boolean(editor.recordId)}
                  recordKey={editor.recordKey}
                  enabled={editor.enabled}
                  contractorDisplayName={editor.contractorDisplayName}
                  promptText={editor.promptText}
                  mappings={editor.mappings}
                  selectedUpgradeTypeId={selectedUpgradeTypeId}
                  onEnabledChange={(next) =>
                    setEditorField((current) =>
                      isGenaiLocatedFieldEditor(current) ? { ...current, enabled: next } : current,
                    )
                  }
                  onRecordKeyChange={(next) =>
                    setEditorField((current) =>
                      isGenaiLocatedFieldEditor(current) ? { ...current, recordKey: next } : current,
                    )
                  }
                  onContractorDisplayNameChange={(next) =>
                    setEditorField((current) =>
                      isGenaiLocatedFieldEditor(current) ? { ...current, contractorDisplayName: next } : current,
                    )
                  }
                  onPromptTextChange={(next) =>
                    setEditorField((current) =>
                      isGenaiLocatedFieldEditor(current) ? { ...current, promptText: next } : current,
                    )
                  }
                  onMappingCheckedChange={(invoiceUpgradeTypeId, checked) =>
                    updateMapping(invoiceUpgradeTypeId, { checked })
                  }
                  onCancel={closeEditorScreen}
                  onSave={saveEditor}
                  saving={saving}
                />
              )
            ) : (
              <Flex py={10} justify="center">
                <Spinner />
              </Flex>
            )}
          </Box>
        </Container>
      </Flex>
    );
  }

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Fields and Advice Editor" />
      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Box mb={5}>
            <HStack align="start" spacing={3}>
              <InvoiceUpgradeTypeTile
                upgradeTypeKey={selectedUpgradeType?.upgrade_type_key}
                description={selectedUpgradeType?.description}
                size={44}
              />
              <Box>
                <Text fontSize="lg" fontWeight="bold">
                  {selectedUpgradeType?.description || 'Upgrade type'}
                </Text>
              </Box>
            </HStack>
          </Box>

          {error ? (
            <Box mb={4} borderWidth="1px" borderColor="red.200" bg="red.50" color="red.700" borderRadius="md" p={3}>
              {error}
            </Box>
          ) : null}

          {loadingRows ? (
            <Flex py={10} justify="center">
              <Spinner />
            </Flex>
          ) : (
            <Tabs variant="enclosed" colorScheme="blue">
              <TabList>
                {TAB_ORDER.map((recordType) => (
                  <Tab key={recordType}>{TYPE_LABELS[recordType]}</Tab>
                ))}
              </TabList>

              <TabPanels>
                {TAB_ORDER.map((recordType) => (
                  <TabPanel key={recordType} px={0} pt={5}>
                    <Flex justify="space-between" align="center" mb={4}>
                      <Box>
                        <Text fontWeight="bold">{TYPE_LABELS[recordType]}</Text>
                        <Text fontSize="sm" opacity={0.7}>
                          Shared records are still shown with all mapped upgrade types so edits never hide
                          cross-taxonomy impact.
                        </Text>
                      </Box>
                      {CREATEABLE_RECORD_TYPES.includes(recordType) ? (
                        <Button leftIcon={<Plus size={16} />} onClick={() => openCreate(recordType)}>
                          Add
                        </Button>
                      ) : null}
                    </Flex>

                    <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" overflowX="auto">
                      <Table size="sm">
                        <Thead bg="gray.50">
                          <Tr>
                            <Th>Name / key</Th>
                            <Th>Updated</Th>
                            <Th>Enabled</Th>
                            <Th textAlign="right">Actions</Th>
                          </Tr>
                        </Thead>
                        <Tbody>
                          {(tabRows[recordType] || []).map((row) => (
                            <Tr key={`${row.record_type}-${row.id}`}>
                              <Td>
                                {row.detail?.contractor_display_name ? (
                                  <Text fontWeight="semibold">{row.detail.contractor_display_name}</Text>
                                ) : null}
                                <Text
                                  fontFamily={row.detail?.contractor_display_name ? 'mono' : undefined}
                                  fontSize={row.detail?.contractor_display_name ? 'xs' : 'sm'}
                                  fontWeight={row.detail?.contractor_display_name ? 'normal' : 'semibold'}
                                  opacity={row.detail?.contractor_display_name ? 0.7 : 1}
                                >
                                  {row.record_key}
                                </Text>
                              </Td>
                              <Td>{fmtDate(row.updated_at)}</Td>
                              <Td>
                                <Badge colorScheme={row.enabled ? 'green' : 'red'} variant="subtle">
                                  {row.enabled ? 'Enabled' : 'Disabled'}
                                </Badge>
                              </Td>
                              <Td>
                                <Flex justify="end" gap={2}>
                                  <Tooltip label="View details">
                                    <IconButton
                                      aria-label="View details"
                                      icon={<Info size={18} />}
                                      size="sm"
                                      variant="outline"
                                      onClick={() => openInfo(row)}
                                    />
                                  </Tooltip>
                                  <Tooltip label="Edit record">
                                    <IconButton
                                      aria-label="Edit record"
                                      icon={<PencilSimple size={18} />}
                                      size="sm"
                                      variant="outline"
                                      onClick={() => openEdit(row)}
                                    />
                                  </Tooltip>
                                  <Tooltip label="View history">
                                    <IconButton
                                      aria-label="View history"
                                      icon={<ClockCounterClockwise size={18} />}
                                      size="sm"
                                      variant="outline"
                                      onClick={() => openAudit(row)}
                                    />
                                  </Tooltip>
                                </Flex>
                              </Td>
                            </Tr>
                          ))}
                          {(tabRows[recordType] || []).length === 0 ? (
                            <Tr>
                              <Td colSpan={4}>
                                <Flex py={8} justify="center">
                                  <Text opacity={0.7}>
                                    No {TYPE_LABELS[recordType].toLowerCase()} for this taxonomy.
                                  </Text>
                                </Flex>
                              </Td>
                            </Tr>
                          ) : null}
                        </Tbody>
                      </Table>
                    </Box>
                  </TabPanel>
                ))}
              </TabPanels>
            </Tabs>
          )}
        </Box>
      </Container>

      <Drawer isOpen={infoDrawer.isOpen} placement="right" onClose={infoDrawer.onClose} size="md">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Record details</DrawerHeader>
          <DrawerBody>
            {selectedRow ? (
              <VStack align="stretch" spacing={4}>
                <Box>
                  <Text fontSize="sm" opacity={0.7}>
                    Type
                  </Text>
                  <Text fontWeight="bold">{TYPE_LABELS[selectedRow.record_type]}</Text>
                </Box>
                <Box>
                  <Text fontSize="sm" opacity={0.7}>
                    Contractor-friendly name
                  </Text>
                  <Text fontWeight="bold">{selectedRow.detail?.contractor_display_name || 'n/a'}</Text>
                </Box>
                <Box>
                  <Text fontSize="sm" opacity={0.7}>
                    Key
                  </Text>
                  <Text fontWeight="bold">{selectedRow.record_key}</Text>
                </Box>
                <Box>
                  <Text fontSize="sm" opacity={0.7} mb={2}>
                    Upgrade types
                  </Text>
                  <Flex gap={2} wrap="wrap">
                    {selectedRow.upgrade_types.length === 0 ? (
                      <Badge variant="outline">All upgrade types</Badge>
                    ) : (
                      selectedRow.upgrade_types.map((type) => (
                        <Badge key={type.id} colorScheme="blue" variant="subtle">
                          {type.description || type.upgrade_type_key}
                        </Badge>
                      ))
                    )}
                  </Flex>
                </Box>
                {Object.entries(selectedRow.detail || {}).map(([key, value]) => (
                  <Box key={key}>
                    <Text fontSize="sm" opacity={0.7}>
                      {key}
                    </Text>
                    <Text whiteSpace="pre-wrap">
                      {value === null || value === undefined || value === '' ? 'n/a' : String(value)}
                    </Text>
                  </Box>
                ))}
              </VStack>
            ) : null}
          </DrawerBody>
        </DrawerContent>
      </Drawer>

      <Drawer isOpen={auditDrawer.isOpen} placement="right" onClose={auditDrawer.onClose} size="lg">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Audit history</DrawerHeader>
          <DrawerBody>
            {loadingHistory ? (
              <Flex py={10} justify="center">
                <Spinner />
              </Flex>
            ) : (
              <VStack align="stretch" spacing={6}>
                <Box>
                  <Text fontWeight="bold">{selectedRow?.record_key}</Text>
                  <Text fontSize="sm" opacity={0.7}>
                    {selectedRow ? TYPE_LABELS[selectedRow.record_type] : ''}
                  </Text>
                </Box>
                <HistorySection title="Record snapshots" rows={history.row_history} />
                <HistorySection title="Mapping snapshots" rows={history.mapping_history} />
              </VStack>
            )}
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
}
