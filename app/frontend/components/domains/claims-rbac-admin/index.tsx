import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Alert,
  AlertIcon,
  Badge,
  Box,
  Button,
  Checkbox,
  Container,
  Flex,
  Spinner,
  Table,
  Tbody,
  Td,
  Text,
  Th,
  Thead,
  Tooltip,
  Tr,
} from '@chakra-ui/react';
import { FloppyDisk, LockSimple } from '@phosphor-icons/react';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { useClaimsAccess } from '../../shared/claims/claims-access';

type RoleKey = 'contractor' | 'admin' | 'admin_manager' | 'system_admin';

type FunctionRow = {
  id: string;
  function_key: string;
  description?: string | null;
  direct_role_keys: RoleKey[];
  effective_role_keys: RoleKey[];
};

type RbacPayload = {
  functions: FunctionRow[];
  roles: Array<{ role_key: RoleKey }>;
};

const ROLE_COLUMNS: Array<{ key: RoleKey; label: string }> = [
  { key: 'contractor', label: 'Contractor' },
  { key: 'admin', label: 'Admin' },
  { key: 'admin_manager', label: 'Admin Manager' },
  { key: 'system_admin', label: 'System Admin' },
];

const inheritedRoleKeys = (directRoleKeys: RoleKey[]): RoleKey[] => {
  const effective = new Set<RoleKey>(directRoleKeys);
  if (effective.has('admin')) {
    effective.add('admin_manager');
    effective.add('system_admin');
  }
  if (effective.has('admin_manager')) effective.add('system_admin');
  return ROLE_COLUMNS.map(({ key }) => key).filter((key) => effective.has(key));
};

const assignmentSnapshot = (rows: FunctionRow[]) =>
  JSON.stringify(
    rows.map((row) => ({
      function_key: row.function_key,
      role_keys: [...row.direct_role_keys].sort(),
    })),
  );

export default function ClaimsRbacAdminScreen() {
  const { refresh: refreshCurrentAccess } = useClaimsAccess();
  const [rows, setRows] = useState<FunctionRow[]>([]);
  const [savedSnapshot, setSavedSnapshot] = useState('');
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [message, setMessage] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const response = await fetch('/api/claims/admin/rbac', {
        credentials: 'include',
        headers: { Accept: 'application/json' },
      });
      const body = (await response.json().catch(() => ({}))) as RbacPayload & { error?: string };
      if (!response.ok) throw new Error(body?.error || `HTTP ${response.status}`);
      const nextRows = Array.isArray(body.functions) ? body.functions : [];
      setRows(nextRows);
      setSavedSnapshot(assignmentSnapshot(nextRows));
    } catch (requestError: any) {
      setError(requestError?.message || 'RBAC configuration could not be loaded.');
      setRows([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const currentSnapshot = useMemo(() => assignmentSnapshot(rows), [rows]);
  const dirty = currentSnapshot !== savedSnapshot;

  const toggleAssignment = (functionKey: string, roleKey: RoleKey) => {
    setMessage('');
    setRows((existing) =>
      existing.map((row) => {
        if (row.function_key !== functionKey) return row;

        const direct = new Set<RoleKey>(row.direct_role_keys);
        if (direct.has(roleKey)) {
          direct.delete(roleKey);
        } else {
          direct.add(roleKey);
          if (roleKey === 'admin') {
            direct.delete('admin_manager');
            direct.delete('system_admin');
          } else if (roleKey === 'admin_manager') {
            direct.delete('system_admin');
          }
        }

        const directRoleKeys = ROLE_COLUMNS.map(({ key }) => key).filter((key) => direct.has(key));
        return {
          ...row,
          direct_role_keys: directRoleKeys,
          effective_role_keys: inheritedRoleKeys(directRoleKeys),
        };
      }),
    );
  };

  const save = async () => {
    setSaving(true);
    setError('');
    setMessage('');
    try {
      const response = await fetch('/api/claims/admin/rbac', {
        method: 'PUT',
        credentials: 'include',
        headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
        body: JSON.stringify({
          assignments: rows.map((row) => ({
            function_key: row.function_key,
            role_keys: row.direct_role_keys,
          })),
        }),
      });
      const body = (await response.json().catch(() => ({}))) as RbacPayload & { error?: string };
      if (!response.ok) throw new Error(body?.error || `HTTP ${response.status}`);
      const nextRows = Array.isArray(body.functions) ? body.functions : [];
      setRows(nextRows);
      setSavedSnapshot(assignmentSnapshot(nextRows));
      setMessage('Claims role functions saved.');
      await refreshCurrentAccess();
    } catch (requestError: any) {
      setError(requestError?.message || 'RBAC configuration could not be saved.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Role Based Access Control" />

      <Container maxW="container.xl" pt={6} pb={6}>
        <Flex justify="space-between" align="end" gap={4} mb={5} wrap="wrap">
          <Box>
            <Text fontSize="xl" fontWeight="semibold">
              Claims role functions
            </Text>
            <Text fontSize="sm" color="gray.600" mt={1} maxW="760px">
              Assign broad Claims capabilities to fixed roles. Checked, disabled cells are inherited from a lower staff
              role.
            </Text>
          </Box>

          <Flex gap={3} align="center">
            {dirty && <Badge colorScheme="yellow">Unsaved changes</Badge>}
            <Button variant="outline" onClick={() => void load()} isDisabled={loading || saving || !dirty}>
              Reset
            </Button>
            <Button
              colorScheme="blue"
              leftIcon={<FloppyDisk size={18} />}
              onClick={() => void save()}
              isDisabled={!dirty || loading}
              isLoading={saving}
            >
              Save
            </Button>
          </Flex>
        </Flex>

        {error && (
          <Alert status="error" mb={4} borderRadius="md">
            <AlertIcon />
            {error}
          </Alert>
        )}
        {message && (
          <Alert status="success" mb={4} borderRadius="md">
            <AlertIcon />
            {message}
          </Alert>
        )}

        <Box bg="white" borderWidth="1px" borderColor="gray.200" borderRadius="xl" overflowX="auto">
          {loading ? (
            <Flex minH="220px" align="center" justify="center">
              <Spinner />
            </Flex>
          ) : (
            <Table size="sm" sx={{ tableLayout: 'fixed' }} minW="1040px">
              <Thead>
                <Tr>
                  <Th w="210px">Function</Th>
                  <Th>Description and included Claims UI</Th>
                  {ROLE_COLUMNS.map(({ key, label }) => (
                    <Th key={key} w="130px" textAlign="center" whiteSpace="normal">
                      {label}
                    </Th>
                  ))}
                </Tr>
              </Thead>
              <Tbody>
                {rows.map((row) => {
                  const protectedRow = row.function_key === 'claims.role_functions';
                  return (
                    <Tr key={row.function_key}>
                      <Td verticalAlign="top" py={4}>
                        <Text fontWeight="semibold" fontSize="sm">
                          {row.function_key}
                        </Text>
                      </Td>
                      <Td verticalAlign="top" py={4}>
                        <Text fontSize="sm" color="gray.700">
                          {row.description || '—'}
                        </Text>
                      </Td>
                      {ROLE_COLUMNS.map(({ key, label }) => {
                        const directlyAssigned = row.direct_role_keys.includes(key);
                        const effectivelyAssigned = inheritedRoleKeys(row.direct_role_keys).includes(key);
                        const inherited = effectivelyAssigned && !directlyAssigned;
                        const protectedCell = protectedRow;
                        const disabledReason = protectedCell
                          ? 'Protected: RBAC administration must remain assigned only to System Admin.'
                          : inherited
                            ? 'Inherited from a lower staff role. Change the direct assignment in that role to alter this permission.'
                            : '';
                        return (
                          <Td key={key} textAlign="center" verticalAlign="middle">
                            <Tooltip label={disabledReason} hasArrow isDisabled={!disabledReason} shouldWrapChildren>
                              <Checkbox
                                aria-label={`${row.function_key}: ${label}`}
                                isChecked={effectivelyAssigned}
                                isDisabled={inherited || protectedCell}
                                onChange={() => toggleAssignment(row.function_key, key)}
                              />
                            </Tooltip>
                            {protectedCell && key === 'system_admin' && (
                              <Box as="span" ml={2} color="gray.500" display="inline-flex" verticalAlign="middle">
                                <LockSimple size={15} aria-label="Protected assignment" />
                              </Box>
                            )}
                          </Td>
                        );
                      })}
                    </Tr>
                  );
                })}
              </Tbody>
            </Table>
          )}
        </Box>
      </Container>
    </Flex>
  );
}
