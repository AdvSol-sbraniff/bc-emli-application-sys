import React, { useEffect, useMemo, useState } from 'react';
import { Box, Button, Container, Flex, Heading, Input, Spinner, Text } from '@chakra-ui/react';
import { useLocation, useNavigate } from 'react-router-dom';
import { BlueTitleBar } from '../../shared/base/blue-title-bar';

type EligibilityRecordDto = {
  id: string;
  user_id: string;
  eligibility_code: string;
  income_level?: number | null;
  applied_at: string;
  approved_at: string;
  expires_at: string;
  created_at?: string;
  updated_at?: string;
};

function useQueryParam(name: string): string | null {
  const { search } = useLocation();
  return useMemo(() => new URLSearchParams(search).get(name), [search, name]);
}

function deriveIncomeLevel(value: string): number | null {
  const token = value.trim().toUpperCase();
  if (token.startsWith('ESP1') || token.startsWith('ESPI')) return 1;
  if (token.startsWith('ESP2')) return 2;
  if (token.startsWith('ESP3')) return 3;
  return null;
}

export default function EligibilitycodeEditorScreen() {
  const navigate = useNavigate();

  const id = useQueryParam('id');
  const mode = useQueryParam('mode');
  const userIdFromQuery = useQueryParam('user_id');
  const emailFromQuery = useQueryParam('email');
  const nameFromQuery = useQueryParam('name');
  const isCreateMode = mode === 'create';

  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [isSaving, setIsSaving] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  const [record, setRecord] = useState<EligibilityRecordDto | null>(null);

  const [userId, setUserId] = useState<string>('');
  const [eligibilityCode, setEligibilityCode] = useState<string>('');
  const [appliedAt, setAppliedAt] = useState<string>('');
  const [approvedAt, setApprovedAt] = useState<string>('');
  const [expiresAt, setExpiresAt] = useState<string>('');

  const [initialValues, setInitialValues] = useState({
    userId: '',
    eligibilityCode: '',
    appliedAt: '',
    approvedAt: '',
    expiresAt: '',
  });

  const isDirty =
    userId !== initialValues.userId ||
    eligibilityCode !== initialValues.eligibilityCode ||
    appliedAt !== initialValues.appliedAt ||
    approvedAt !== initialValues.approvedAt ||
    expiresAt !== initialValues.expiresAt;
  const incomeLevel = deriveIncomeLevel(eligibilityCode) ?? record?.income_level ?? null;

  async function load() {
    setIsLoading(true);
    setError(null);

    try {
      if (isCreateMode) {
        const nextUserId = userIdFromQuery || '';
        setRecord(null);
        setUserId(nextUserId);
        setEligibilityCode('');
        setAppliedAt('');
        setApprovedAt('');
        setExpiresAt('');
        setInitialValues({
          userId: nextUserId,
          eligibilityCode: '',
          appliedAt: '',
          approvedAt: '',
          expiresAt: '',
        });
        return;
      }

      if (!id) {
        setError('Missing query param: id');
        return;
      }

      const resp = await fetch(`/api/claims/admin/users_eligibilitycodes/${id}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      if (!resp.ok) {
        const txt = await resp.text();
        throw new Error(`GET failed (${resp.status}): ${txt}`);
      }

      const data: EligibilityRecordDto = await resp.json();
      setRecord(data);
      setUserId(data.user_id || '');
      setEligibilityCode(data.eligibility_code || '');
      setAppliedAt(data.applied_at || '');
      setApprovedAt(data.approved_at || '');
      setExpiresAt(data.expires_at || '');
      setInitialValues({
        userId: data.user_id || '',
        eligibilityCode: data.eligibility_code || '',
        appliedAt: data.applied_at || '',
        approvedAt: data.approved_at || '',
        expiresAt: data.expires_at || '',
      });
    } catch (e: any) {
      setError(e?.message || 'Load failed');
    } finally {
      setIsLoading(false);
    }
  }

  async function save() {
    if (!isCreateMode && !id) return;

    setIsSaving(true);
    setError(null);

    try {
      const endpoint = isCreateMode
        ? '/api/claims/admin/users_eligibilitycodes'
        : `/api/claims/admin/users_eligibilitycodes/${id}`;
      const method = isCreateMode ? 'POST' : 'PATCH';

      const body = isCreateMode
        ? {
            user_id: userId.trim(),
            eligibility_code: eligibilityCode.trim(),
            applied_at: appliedAt,
            approved_at: approvedAt,
            expires_at: expiresAt,
          }
        : {
            eligibility_code: eligibilityCode.trim(),
            applied_at: appliedAt,
            approved_at: approvedAt,
            expires_at: expiresAt,
          };

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

      const data: EligibilityRecordDto = await resp.json();
      setRecord(data);
      setUserId(data.user_id || '');
      setEligibilityCode(data.eligibility_code || '');
      setAppliedAt(data.applied_at || '');
      setApprovedAt(data.approved_at || '');
      setExpiresAt(data.expires_at || '');
      setInitialValues({
        userId: data.user_id || '',
        eligibilityCode: data.eligibility_code || '',
        appliedAt: data.applied_at || '',
        approvedAt: data.approved_at || '',
        expiresAt: data.expires_at || '',
      });

      if (isCreateMode) {
        navigate(`/eligibilitycode-editor?id=${encodeURIComponent(data.id)}`, { replace: true });
      }
    } catch (e: any) {
      setError(e?.message || 'Save failed');
    } finally {
      setIsSaving(false);
    }
  }

  useEffect(() => {
    load();
  }, [id, mode, userIdFromQuery]);

  return (
    <Box>
      <BlueTitleBar title="Eligibility Code Editor" />

      <Container maxW="4xl" py={6}>
        {!id && !isCreateMode && (
          <Box p={4} borderWidth="1px" borderRadius="md">
            <Text fontWeight="bold">Missing id</Text>
            <Text>
              Use: /eligibilitycode-editor?id=&lt;uuid&gt; or /eligibilitycode-editor?mode=create&user_id=&lt;uuid&gt;
            </Text>
          </Box>
        )}

        {(id || isCreateMode) && (
          <Box borderWidth="1px" borderRadius="lg" p={5} bg="white">
            <Flex align="center" justify="space-between" mb={4}>
              <Heading size="md">{isCreateMode ? 'Insert Eligibility Code' : 'Update Eligibility Code'}</Heading>
              <Flex gap={2}>
                <Button onClick={load} variant="outline" isDisabled={isLoading || isSaving}>
                  Reload
                </Button>
                <Button onClick={save} colorScheme="blue" isLoading={isSaving} isDisabled={isLoading || !isDirty}>
                  Save
                </Button>
              </Flex>
            </Flex>

            {(nameFromQuery || emailFromQuery) && (
              <Box mb={4} p={3} borderWidth="1px" borderRadius="md" bg="gray.50">
                <Text fontSize="sm" fontWeight="bold">
                  User context
                </Text>
                {nameFromQuery && <Text fontSize="sm">name: {nameFromQuery}</Text>}
                {emailFromQuery && <Text fontSize="sm">email: {emailFromQuery}</Text>}
              </Box>
            )}

            {isLoading && (
              <Flex align="center" gap={3} p={3}>
                <Spinner size="sm" />
                <Text>Loading...</Text>
              </Flex>
            )}

            {error && (
              <Box p={3} borderWidth="1px" borderRadius="md" mb={4} borderColor="red.300" bg="red.50">
                <Text color="red.800" fontSize="sm">
                  {error}
                </Text>
              </Box>
            )}

            {!isLoading && !error && (
              <Flex direction="column" gap={4}>
                <Box>
                  <Text fontSize="xs" opacity={0.7} mb={1}>
                    user_id
                  </Text>
                  <Input
                    value={userId}
                    onChange={(e) => setUserId(e.target.value)}
                    isDisabled={!isCreateMode}
                    fontFamily="mono"
                  />
                </Box>
                <Box>
                  <Text fontSize="xs" opacity={0.7} mb={1}>
                    eligibility_code
                  </Text>
                  <Input value={eligibilityCode} onChange={(e) => setEligibilityCode(e.target.value)} />
                </Box>
                <Box>
                  <Text fontSize="xs" opacity={0.7} mb={1}>
                    income_level
                  </Text>
                  <Input value={incomeLevel === null ? '—' : String(incomeLevel)} isReadOnly bg="gray.50" />
                  <Text fontSize="xs" opacity={0.7} mt={1}>
                    Stored from the eligibility code prefix on save.
                  </Text>
                </Box>
                <Box>
                  <Text fontSize="xs" opacity={0.7} mb={1}>
                    applied_at
                  </Text>
                  <Input
                    value={appliedAt}
                    onChange={(e) => setAppliedAt(e.target.value)}
                    placeholder="YYYY-MM-DD or timestamp"
                  />
                </Box>
                <Box>
                  <Text fontSize="xs" opacity={0.7} mb={1}>
                    approved_at
                  </Text>
                  <Input
                    value={approvedAt}
                    onChange={(e) => setApprovedAt(e.target.value)}
                    placeholder="YYYY-MM-DD or timestamp"
                  />
                </Box>
                <Box>
                  <Text fontSize="xs" opacity={0.7} mb={1}>
                    expires_at
                  </Text>
                  <Input
                    value={expiresAt}
                    onChange={(e) => setExpiresAt(e.target.value)}
                    placeholder="YYYY-MM-DD or timestamp"
                  />
                </Box>

                <Text fontSize="sm" opacity={0.8}>
                  {isDirty ? 'Unsaved changes' : 'Saved'}
                  {record?.updated_at ? ` • updated_at: ${record.updated_at}` : ''}
                </Text>
              </Flex>
            )}
          </Box>
        )}
      </Container>
    </Box>
  );
}
