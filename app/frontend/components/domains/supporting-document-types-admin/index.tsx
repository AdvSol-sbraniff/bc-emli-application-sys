import React, { useCallback, useEffect, useMemo, useState } from 'react';
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
  Input,
  Spinner,
  Table,
  Tbody,
  Td,
  Text,
  Th,
  Thead,
  Tooltip,
  Tr,
  VStack,
} from '@chakra-ui/react';
import { PencilSimple, Plus } from '@phosphor-icons/react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';

type SupportingDocumentTypeRow = {
  id: string;
  type_key: string;
  description?: string | null;
  enabled: boolean;
  created_at?: string | null;
  updated_at?: string | null;
  supporting_documents_count?: number;
};

type EditorState = {
  id?: string;
  typeKey: string;
  description: string;
  enabled: boolean;
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

export default function SupportingDocumentTypesAdminScreen() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();

  const editorMode = searchParams.get('mode') || '';
  const editorId = searchParams.get('id') || '';
  const isEditorScreen = editorMode === 'create' || editorMode === 'edit';

  const [rows, setRows] = useState<SupportingDocumentTypeRow[]>([]);
  const [editor, setEditor] = useState<EditorState | null>(null);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const selectedRow = useMemo(
    () => rows.find((row) => row.id === editorId) || null,
    [editorId, rows]
  );

  const loadRows = useCallback(async () => {
    setLoading(true);
    setError('');

    try {
      const res = await fetch('/api/claims/admin/supporting_document_types', {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data = await res.json().catch(() => ({ rows: [] }));
      if (!res.ok) {
        throw new Error(data?.error || data?.message || `HTTP ${res.status}`);
      }

      setRows(Array.isArray(data?.rows) ? data.rows : []);
    } catch (e: any) {
      setRows([]);
      setError(e?.message || 'Failed to load supporting document types.');
    } finally {
      setLoading(false);
    }
  }, []);

  const loadEditor = useCallback(async () => {
    if (!isEditorScreen) {
      setEditor(null);
      return;
    }

    if (editorMode === 'create') {
      setEditor({
        typeKey: '',
        description: '',
        enabled: true,
      });
      return;
    }

    setLoading(true);
    setError('');

    try {
      const res = await fetch(`/api/claims/admin/supporting_document_types/${encodeURIComponent(editorId)}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(data?.error || data?.message || `HTTP ${res.status}`);
      }

      setEditor({
        id: data.id,
        typeKey: data.type_key || '',
        description: data.description || '',
        enabled: !!data.enabled,
      });
    } catch (e: any) {
      setError(e?.message || 'Failed to load supporting document type.');
    } finally {
      setLoading(false);
    }
  }, [editorId, editorMode, isEditorScreen]);

  useEffect(() => {
    loadRows();
  }, [loadRows]);

  useEffect(() => {
    loadEditor();
  }, [loadEditor]);

  const openCreate = () => {
    navigate({
      pathname: '/supporting-document-types-admin',
      search: `?${buildSearchParams({ mode: 'create' }).toString()}`,
    });
  };

  const openEdit = (row: SupportingDocumentTypeRow) => {
    navigate({
      pathname: '/supporting-document-types-admin',
      search: `?${buildSearchParams({ mode: 'edit', id: row.id }).toString()}`,
    });
  };

  const closeEditor = () => {
    navigate('/supporting-document-types-admin');
    setError('');
  };

  const saveEditor = async () => {
    if (!editor) return;

    setSaving(true);
    setError('');

    try {
      const body = {
        type_key: editor.typeKey,
        description: editor.description,
        enabled: editor.enabled,
      };

      const res = await fetch(
        editor.id
          ? `/api/claims/admin/supporting_document_types/${encodeURIComponent(editor.id)}`
          : '/api/claims/admin/supporting_document_types',
        {
          method: editor.id ? 'PATCH' : 'POST',
          headers: {
            Accept: 'application/json',
            'Content-Type': 'application/json',
          },
          credentials: 'include',
          body: JSON.stringify(body),
        }
      );

      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error(data?.error || data?.message || `HTTP ${res.status}`);
      }

      await loadRows();
      closeEditor();
    } catch (e: any) {
      setError(e?.message || 'Failed to save supporting document type.');
    } finally {
      setSaving(false);
    }
  };

  if (isEditorScreen) {
    return (
      <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
        <ThinBlueTitleBar
          title={editorMode === 'create' ? 'Add Supporting Document Type' : 'Edit Supporting Document Type'}
        />
        <Container maxW="container.md" pb={4} flex="1" pt={6}>
          <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
            {error ? (
              <Box
                mb={4}
                borderWidth="1px"
                borderColor="red.200"
                bg="red.50"
                color="red.700"
                borderRadius="md"
                p={3}
              >
                {error}
              </Box>
            ) : null}

            {!editor ? (
              <Flex py={10} justify="center">
                <Spinner />
              </Flex>
            ) : (
              <VStack align="stretch" spacing={5}>
                <FormControl>
                  <FormLabel>Type key</FormLabel>
                  <Input
                    value={editor.typeKey}
                    onChange={(event) =>
                      setEditor((current) =>
                        current ? { ...current, typeKey: event.target.value } : current
                      )
                    }
                  />
                </FormControl>

                <FormControl>
                  <FormLabel>Description</FormLabel>
                  <Input
                    value={editor.description}
                    onChange={(event) =>
                      setEditor((current) =>
                        current ? { ...current, description: event.target.value } : current
                      )
                    }
                  />
                </FormControl>

                <Checkbox
                  isChecked={editor.enabled}
                  onChange={(event) =>
                    setEditor((current) =>
                      current ? { ...current, enabled: event.target.checked } : current
                    )
                  }
                >
                  Enabled
                </Checkbox>

                {selectedRow ? (
                  <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={4} bg="gray.50">
                    <Text fontSize="sm">
                      <Text as="span" fontWeight="semibold">
                        Linked supporting documents:
                      </Text>{' '}
                      {selectedRow.supporting_documents_count || 0}
                    </Text>
                  </Box>
                ) : null}

                <HStack justify="end">
                  <Button variant="outline" onClick={closeEditor}>
                    Cancel
                  </Button>
                  <Button colorScheme="blue" onClick={saveEditor} isLoading={saving}>
                    Save
                  </Button>
                </HStack>
              </VStack>
            )}
          </Box>
        </Container>
      </Flex>
    );
  }

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Supporting Document Types" />
      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Flex justify="space-between" align={{ base: 'start', md: 'center' }} gap={3} mb={4}>
            <Box>
              <Text fontSize="lg" fontWeight="bold">
                Supporting document type registry
              </Text>
              <Text fontSize="sm" opacity={0.7}>
                Manage the supplement-type classifications used by the mixed upload pipeline.
              </Text>
            </Box>
            <Button leftIcon={<Plus size={16} />} onClick={openCreate}>
              Add Type
            </Button>
          </Flex>

          {error ? (
            <Box
              mb={4}
              borderWidth="1px"
              borderColor="red.200"
              bg="red.50"
              color="red.700"
              borderRadius="md"
              p={3}
            >
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
                    <Th>Key</Th>
                    <Th>Description</Th>
                    <Th>Used By</Th>
                    <Th>Enabled</Th>
                    <Th>Updated</Th>
                    <Th textAlign="right">Actions</Th>
                  </Tr>
                </Thead>
                <Tbody>
                  {rows.map((row) => (
                    <Tr key={row.id}>
                      <Td>
                        <Text fontWeight="semibold">{row.type_key}</Text>
                      </Td>
                      <Td>{row.description || ''}</Td>
                      <Td>{row.supporting_documents_count || 0}</Td>
                      <Td>
                        <Badge colorScheme={row.enabled ? 'green' : 'red'} variant="subtle">
                          {row.enabled ? 'Enabled' : 'Disabled'}
                        </Badge>
                      </Td>
                      <Td>{fmtDate(row.updated_at)}</Td>
                      <Td>
                        <Flex justify="end">
                          <Tooltip label="Edit type">
                            <Button
                              aria-label="Edit type"
                              variant="outline"
                              size="sm"
                              leftIcon={<PencilSimple size={16} />}
                              onClick={() => openEdit(row)}
                            >
                              Edit
                            </Button>
                          </Tooltip>
                        </Flex>
                      </Td>
                    </Tr>
                  ))}
                </Tbody>
              </Table>
            </Box>
          )}
        </Box>
      </Container>
    </Flex>
  );
}
