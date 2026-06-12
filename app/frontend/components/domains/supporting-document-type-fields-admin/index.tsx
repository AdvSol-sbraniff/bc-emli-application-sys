import React, { useCallback, useEffect, useState } from 'react';
import {
  Badge,
  Box,
  Button,
  Checkbox,
  Container,
  Flex,
  FormControl,
  FormLabel,
  HStack,
  IconButton,
  Input,
  NumberInput,
  NumberInputField,
  Spinner,
  Table,
  Tbody,
  Td,
  Text,
  Textarea,
  Th,
  Thead,
  Tooltip,
  Tr,
  VStack,
} from '@chakra-ui/react';
import { ArrowLeft, PencilSimple, Plus } from '@phosphor-icons/react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';

type SupportingDocumentTypeSummary = {
  id: string;
  type_key: string;
  description?: string | null;
  enabled: boolean;
};

type LocatedFieldRow = {
  id: string;
  supporting_document_type_id: string;
  field_key: string;
  prompt_text: string;
  field_number: number;
  enabled: boolean;
  created_at?: string | null;
  updated_at?: string | null;
  supporting_document_type?: SupportingDocumentTypeSummary | null;
};

type EditorState = {
  id?: string;
  fieldKey: string;
  promptText: string;
  fieldNumber: string;
  enabled: boolean;
};

type FieldAdminConfig = {
  basePath: string;
  listEndpointName: string;
  rowEndpointName: string;
  listTitle: string;
  createTitle: string;
  editTitle: string;
  helperText: string;
  loadRowsError: string;
  loadEditorError: string;
  saveError: string;
  editAriaLabel: string;
};

const fileFieldConfig: FieldAdminConfig = {
  basePath: '/supporting-document-type-fields-admin',
  listEndpointName: 'located_fields',
  rowEndpointName: 'supporting_document_type_located_fields',
  listTitle: 'Supporting Document Fields',
  createTitle: 'Add Supporting Document Field',
  editTitle: 'Edit Supporting Document Field',
  helperText: 'Manage the located-field tasks sent to the supporting-document extraction prompt.',
  loadRowsError: 'Failed to load supporting document fields.',
  loadEditorError: 'Failed to load supporting document field.',
  saveError: 'Failed to save supporting document field.',
  editAriaLabel: 'Edit supporting document field',
};

const fmtDate = (value?: string | null) => {
  if (!value) return '';
  const str = String(value);
  return str.includes('T') ? str.split('T')[0] : str.slice(0, 10);
};

const buildSearchParams = (obj: Record<string, string | undefined>) => {
  const params = new URLSearchParams();
  Object.entries(obj).forEach(([key, value]) => {
    const next = value?.toString().trim();
    if (next) params.set(key, next);
  });
  return params;
};

export function SupportingDocumentTypeFieldsAdminScreen({ config = fileFieldConfig }: { config?: FieldAdminConfig }) {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();

  const typeId = searchParams.get('type_id') || '';
  const editorMode = searchParams.get('mode') || '';
  const editorId = searchParams.get('id') || '';
  const isEditorScreen = editorMode === 'create' || editorMode === 'edit';

  const [supportingDocumentType, setSupportingDocumentType] = useState<SupportingDocumentTypeSummary | null>(null);
  const [rows, setRows] = useState<LocatedFieldRow[]>([]);
  const [editor, setEditor] = useState<EditorState | null>(null);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const fieldGridPath = useCallback(
    (mode?: string, id?: string) => ({
      pathname: config.basePath,
      search: `?${buildSearchParams({ type_id: typeId, mode, id }).toString()}`,
    }),
    [config.basePath, typeId],
  );

  const loadRows = useCallback(async () => {
    if (!typeId) {
      setSupportingDocumentType(null);
      setRows([]);
      setError('Missing supporting document type id.');
      return;
    }

    setLoading(true);
    setError('');

    try {
      const res = await fetch(
        `/api/claims/admin/supporting_document_types/${encodeURIComponent(typeId)}/${config.listEndpointName}`,
        {
          method: 'GET',
          headers: { Accept: 'application/json' },
          credentials: 'include',
        },
      );

      const data = await res.json().catch(() => ({ rows: [] }));
      if (!res.ok) {
        throw new Error(data?.error || data?.message || `HTTP ${res.status}`);
      }

      setSupportingDocumentType(data?.supporting_document_type ?? null);
      setRows(Array.isArray(data?.rows) ? data.rows : []);
    } catch (e: any) {
      setRows([]);
      setError(e?.message || config.loadRowsError);
    } finally {
      setLoading(false);
    }
  }, [config.listEndpointName, config.loadRowsError, typeId]);

  const loadEditor = useCallback(async () => {
    if (!isEditorScreen) {
      setEditor(null);
      return;
    }

    if (editorMode === 'create') {
      const nextNumber = rows.reduce((max, row) => Math.max(max, Number(row.field_number || 0)), 0) + 1;
      setEditor({
        fieldKey: '',
        promptText: '',
        fieldNumber: String(nextNumber),
        enabled: true,
      });
      return;
    }

    setLoading(true);
    setError('');

    try {
      const res = await fetch(`/api/claims/admin/${config.rowEndpointName}/${encodeURIComponent(editorId)}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data: LocatedFieldRow = await res.json().catch(() => ({}) as LocatedFieldRow);
      if (!res.ok) {
        throw new Error((data as any)?.error || (data as any)?.message || `HTTP ${res.status}`);
      }

      setSupportingDocumentType(data.supporting_document_type ?? supportingDocumentType);
      setEditor({
        id: data.id,
        fieldKey: data.field_key || '',
        promptText: data.prompt_text || '',
        fieldNumber: String(data.field_number || ''),
        enabled: !!data.enabled,
      });
    } catch (e: any) {
      setError(e?.message || config.loadEditorError);
    } finally {
      setLoading(false);
    }
  }, [
    config.loadEditorError,
    config.rowEndpointName,
    editorId,
    editorMode,
    isEditorScreen,
    rows,
    supportingDocumentType,
  ]);

  useEffect(() => {
    loadRows();
  }, [loadRows]);

  useEffect(() => {
    loadEditor();
  }, [loadEditor]);

  const openCreate = () => {
    navigate(fieldGridPath('create'));
  };

  const openEdit = (row: LocatedFieldRow) => {
    navigate(fieldGridPath('edit', row.id));
  };

  const closeEditor = () => {
    navigate(fieldGridPath());
    setError('');
  };

  const saveEditor = async () => {
    if (!editor || !typeId) return;

    setSaving(true);
    setError('');

    try {
      const body = {
        field_key: editor.fieldKey,
        prompt_text: editor.promptText,
        field_number: Number(editor.fieldNumber),
        enabled: editor.enabled,
      };

      const res = await fetch(
        editor.id
          ? `/api/claims/admin/${config.rowEndpointName}/${encodeURIComponent(editor.id)}`
          : `/api/claims/admin/supporting_document_types/${encodeURIComponent(typeId)}/${config.listEndpointName}`,
        {
          method: editor.id ? 'PATCH' : 'POST',
          headers: {
            Accept: 'application/json',
            'Content-Type': 'application/json',
          },
          credentials: 'include',
          body: JSON.stringify(body),
        },
      );

      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(data?.error || data?.message || `HTTP ${res.status}`);
      }

      await loadRows();
      closeEditor();
    } catch (e: any) {
      setError(e?.message || config.saveError);
    } finally {
      setSaving(false);
    }
  };

  const typeTitle =
    supportingDocumentType?.description || supportingDocumentType?.type_key || 'Supporting document type';

  if (isEditorScreen) {
    return (
      <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
        <ThinBlueTitleBar title={editorMode === 'create' ? config.createTitle : config.editTitle} />
        <Container maxW="container.md" pb={4} flex="1" pt={6}>
          <VStack align="stretch" spacing={4}>
            <Button alignSelf="flex-start" variant="ghost" leftIcon={<ArrowLeft size={16} />} onClick={closeEditor}>
              Back to fields
            </Button>

            <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
              <Text fontSize="lg" fontWeight="bold">
                {typeTitle}
              </Text>
              <Text fontSize="sm" opacity={0.7} mb={5}>
                Define one field the supporting-document extraction prompt should ask the model to locate.
              </Text>

              {error ? (
                <Box mb={4} borderWidth="1px" borderColor="red.200" bg="red.50" color="red.700" borderRadius="md" p={3}>
                  {error}
                </Box>
              ) : null}

              {!editor ? (
                <Flex py={10} justify="center">
                  <Spinner />
                </Flex>
              ) : (
                <VStack align="stretch" spacing={5}>
                  <Checkbox
                    isChecked={editor.enabled}
                    onChange={(event) =>
                      setEditor((current) => (current ? { ...current, enabled: event.target.checked } : current))
                    }
                  >
                    Enabled
                  </Checkbox>

                  <FormControl>
                    <FormLabel>Field key</FormLabel>
                    <Input
                      value={editor.fieldKey}
                      onChange={(event) =>
                        setEditor((current) => (current ? { ...current, fieldKey: event.target.value } : current))
                      }
                      placeholder="utility_provider"
                    />
                  </FormControl>

                  <FormControl>
                    <FormLabel>Display/order number</FormLabel>
                    <NumberInput
                      min={1}
                      value={editor.fieldNumber}
                      onChange={(value) =>
                        setEditor((current) => (current ? { ...current, fieldNumber: value } : current))
                      }
                    >
                      <NumberInputField />
                    </NumberInput>
                  </FormControl>

                  <FormControl>
                    <FormLabel>Prompt text</FormLabel>
                    <Textarea
                      value={editor.promptText}
                      onChange={(event) =>
                        setEditor((current) => (current ? { ...current, promptText: event.target.value } : current))
                      }
                      minH="180px"
                      placeholder="Locate the utility provider name..."
                    />
                  </FormControl>

                  <HStack justify="end">
                    <Button variant="outline" onClick={closeEditor}>
                      Cancel
                    </Button>
                    <Button colorScheme="blue" onClick={saveEditor} isLoading={saving}>
                      Save Field
                    </Button>
                  </HStack>
                </VStack>
              )}
            </Box>
          </VStack>
        </Container>
      </Flex>
    );
  }

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title={config.listTitle} />
      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <VStack align="stretch" spacing={4}>
          <Button
            alignSelf="flex-start"
            variant="ghost"
            leftIcon={<ArrowLeft size={16} />}
            onClick={() => navigate('/supporting-document-types-admin')}
          >
            Back to document types
          </Button>

          <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
            <Flex justify="space-between" align={{ base: 'start', md: 'center' }} gap={3} mb={4}>
              <Box>
                <HStack mb={1}>
                  <Text fontSize="lg" fontWeight="bold">
                    {typeTitle}
                  </Text>
                  {supportingDocumentType ? (
                    <Badge colorScheme={supportingDocumentType.enabled ? 'green' : 'red'} variant="subtle">
                      {supportingDocumentType.enabled ? 'Enabled' : 'Disabled'}
                    </Badge>
                  ) : null}
                </HStack>
                <Text fontSize="sm" opacity={0.7}>
                  {config.helperText}
                </Text>
              </Box>
              <Button leftIcon={<Plus size={16} />} onClick={openCreate} isDisabled={!typeId}>
                Add Field
              </Button>
            </Flex>

            {error ? (
              <Box mb={4} borderWidth="1px" borderColor="red.200" bg="red.50" color="red.700" borderRadius="md" p={3}>
                {error}
              </Box>
            ) : null}

            {loading ? (
              <Flex py={10} justify="center">
                <Spinner />
              </Flex>
            ) : (
              <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" overflowX="auto">
                <Table size="sm">
                  <Thead bg="gray.50">
                    <Tr>
                      <Th w="80px">Order</Th>
                      <Th>Field key</Th>
                      <Th>Prompt</Th>
                      <Th>Enabled</Th>
                      <Th>Updated</Th>
                      <Th textAlign="right">Actions</Th>
                    </Tr>
                  </Thead>
                  <Tbody>
                    {rows.map((row) => (
                      <Tr key={row.id}>
                        <Td>{row.field_number}</Td>
                        <Td>
                          <Text fontWeight="semibold">{row.field_key}</Text>
                        </Td>
                        <Td maxW="560px">
                          <Text noOfLines={2}>{row.prompt_text}</Text>
                        </Td>
                        <Td>
                          <Badge colorScheme={row.enabled ? 'green' : 'red'} variant="subtle">
                            {row.enabled ? 'Enabled' : 'Disabled'}
                          </Badge>
                        </Td>
                        <Td>{fmtDate(row.updated_at)}</Td>
                        <Td>
                          <Flex justify="end">
                            <Tooltip label="Edit field">
                              <IconButton
                                aria-label={config.editAriaLabel}
                                icon={<PencilSimple size={18} />}
                                variant="outline"
                                size="sm"
                                onClick={() => openEdit(row)}
                              />
                            </Tooltip>
                          </Flex>
                        </Td>
                      </Tr>
                    ))}
                    {rows.length === 0 ? (
                      <Tr>
                        <Td colSpan={6}>
                          <Text py={6} textAlign="center" opacity={0.7}>
                            No located fields configured yet.
                          </Text>
                        </Td>
                      </Tr>
                    ) : null}
                  </Tbody>
                </Table>
              </Box>
            )}
          </Box>
        </VStack>
      </Container>
    </Flex>
  );
}

export default SupportingDocumentTypeFieldsAdminScreen;
