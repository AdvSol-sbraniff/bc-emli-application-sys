import React, { useEffect, useMemo, useState } from 'react';
import {
  Box,
  Button,
  Checkbox,
  Container,
  Divider,
  Flex,
  Heading,
  Input,
  Select,
  SimpleGrid,
  Spinner,
  Text,
} from '@chakra-ui/react';
import { useLocation } from 'react-router-dom';
import { BlueTitleBar } from '../../shared/base/blue-title-bar';

type UserDto = {
  id: string;
  email?: string | null;
  organization?: string | null;
  role?: string | null;
  first_name?: string | null;
  last_name?: string | null;
  name?: string | null;
  reviewed?: boolean | null;
  certified?: boolean | null;
  confirmed_at?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
  omniauth_provider?: string | null;
  omniauth_uid?: string | null;
  omniauth_email?: string | null;
  omniauth_username?: string | null;
  discarded_at?: string | null;
  sign_in_count?: number | null;
  current_sign_in_at?: string | null;
  last_sign_in_at?: string | null;
  invitation_sent_at?: string | null;
  invitation_accepted_at?: string | null;
  unconfirmed_email?: string | null;
};

const ROLE_OPTIONS = [
  { value: 'participant', label: 'participant (0)' },
  { value: 'admin_manager', label: 'admin_manager (1)' },
  { value: 'admin', label: 'admin (2)' },
  { value: 'system_admin', label: 'system_admin (3)' },
  { value: 'regional_review_manager', label: 'regional_review_manager (4)' },
  { value: 'participant_support_rep', label: 'participant_support_rep (5)' },
  { value: 'contractor', label: 'contractor (6)' },
  { value: 'unassigned', label: 'unassigned (7)' },
];

const fmtTs = (s?: string | null) => (s ? String(s).replace('T', ' ').replace('Z', '') : '--');

function useQueryParam(name: string): string | null {
  const { search } = useLocation();
  return useMemo(() => new URLSearchParams(search).get(name), [search, name]);
}

function ReadOnlyField({ label, value }: { label: string; value: any }) {
  return (
    <Box>
      <Text fontSize="xs" opacity={0.7} mb={1}>
        {label}
      </Text>
      <Text fontSize="sm" whiteSpace="pre-wrap" fontFamily={label === 'id' ? 'mono' : undefined}>
        {value === null || value === undefined || value === '' ? '--' : String(value)}
      </Text>
    </Box>
  );
}

export default function UserEditorScreen() {
  const id = useQueryParam('id');
  const mode = useQueryParam('mode');
  const isCreateMode = mode === 'create';

  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [isSaving, setIsSaving] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [record, setRecord] = useState<UserDto | null>(null);

  const [email, setEmail] = useState<string>('');
  const [firstName, setFirstName] = useState<string>('');
  const [lastName, setLastName] = useState<string>('');
  const [organization, setOrganization] = useState<string>('');
  const [role, setRole] = useState<string>('unassigned');
  const [reviewed, setReviewed] = useState<boolean>(false);
  const [certified, setCertified] = useState<boolean>(false);
  const [omniauthProvider, setOmniauthProvider] = useState<string>('');
  const [omniauthUid, setOmniauthUid] = useState<string>('');
  const [omniauthEmail, setOmniauthEmail] = useState<string>('');
  const [omniauthUsername, setOmniauthUsername] = useState<string>('');

  const [initialValues, setInitialValues] = useState({
    email: '',
    firstName: '',
    lastName: '',
    organization: '',
    role: 'unassigned',
    reviewed: false,
    certified: false,
    omniauthProvider: '',
    omniauthUid: '',
    omniauthEmail: '',
    omniauthUsername: '',
  });

  const isDirty =
    email !== initialValues.email ||
    firstName !== initialValues.firstName ||
    lastName !== initialValues.lastName ||
    organization !== initialValues.organization ||
    role !== initialValues.role ||
    reviewed !== initialValues.reviewed ||
    certified !== initialValues.certified ||
    omniauthProvider !== initialValues.omniauthProvider ||
    omniauthUid !== initialValues.omniauthUid ||
    omniauthEmail !== initialValues.omniauthEmail ||
    omniauthUsername !== initialValues.omniauthUsername;

  async function load() {
    setIsLoading(true);
    setError(null);

    try {
      if (isCreateMode) {
        setRecord(null);
        setEmail('');
        setFirstName('');
        setLastName('');
        setOrganization('');
        setRole('unassigned');
        setReviewed(false);
        setCertified(false);
        setOmniauthProvider('');
        setOmniauthUid('');
        setOmniauthEmail('');
        setOmniauthUsername('');
        setInitialValues({
          email: '',
          firstName: '',
          lastName: '',
          organization: '',
          role: 'unassigned',
          reviewed: false,
          certified: false,
          omniauthProvider: '',
          omniauthUid: '',
          omniauthEmail: '',
          omniauthUsername: '',
        });
        return;
      }

      if (!id) {
        setError('Missing query param: id');
        return;
      }

      const resp = await fetch(`/api/claims/admin/users/${id}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      if (!resp.ok) {
        const txt = await resp.text();
        throw new Error(`GET failed (${resp.status}): ${txt}`);
      }

      const data: UserDto = await resp.json();
      setRecord(data);
      setEmail(data.email || '');
      setFirstName(data.first_name || '');
      setLastName(data.last_name || '');
      setOrganization(data.organization || '');
      setRole(data.role || 'participant');
      setReviewed(Boolean(data.reviewed));
      setCertified(Boolean(data.certified));
      setOmniauthProvider(data.omniauth_provider || '');
      setOmniauthUid(data.omniauth_uid || '');
      setOmniauthEmail(data.omniauth_email || '');
      setOmniauthUsername(data.omniauth_username || '');
      setInitialValues({
        email: data.email || '',
        firstName: data.first_name || '',
        lastName: data.last_name || '',
        organization: data.organization || '',
        role: data.role || 'participant',
        reviewed: Boolean(data.reviewed),
        certified: Boolean(data.certified),
        omniauthProvider: data.omniauth_provider || '',
        omniauthUid: data.omniauth_uid || '',
        omniauthEmail: data.omniauth_email || '',
        omniauthUsername: data.omniauth_username || '',
      });
    } catch (e: any) {
      setError(e?.message || 'Load failed');
    } finally {
      setIsLoading(false);
    }
  }

  async function save() {
    setIsSaving(true);
    setError(null);

    try {
      const endpoint = isCreateMode ? '/api/claims/admin/users' : `/api/claims/admin/users/${id}`;
      const method = isCreateMode ? 'POST' : 'PATCH';

      const resp = await fetch(endpoint, {
        method,
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          email: email.trim(),
          first_name: firstName.trim(),
          last_name: lastName.trim(),
          organization: organization.trim(),
          role,
          reviewed,
          certified,
          omniauth_provider: omniauthProvider.trim(),
          omniauth_uid: omniauthUid.trim(),
          omniauth_email: omniauthEmail.trim(),
          omniauth_username: omniauthUsername.trim(),
        }),
      });

      if (!resp.ok) {
        const txt = await resp.text();
        throw new Error(`${method} failed (${resp.status}): ${txt}`);
      }

      const data: UserDto = await resp.json();
      setRecord(data);
      setEmail(data.email || '');
      setFirstName(data.first_name || '');
      setLastName(data.last_name || '');
      setOrganization(data.organization || '');
      setRole(data.role || 'participant');
      setReviewed(Boolean(data.reviewed));
      setCertified(Boolean(data.certified));
      setOmniauthProvider(data.omniauth_provider || '');
      setOmniauthUid(data.omniauth_uid || '');
      setOmniauthEmail(data.omniauth_email || '');
      setOmniauthUsername(data.omniauth_username || '');
      setInitialValues({
        email: data.email || '',
        firstName: data.first_name || '',
        lastName: data.last_name || '',
        organization: data.organization || '',
        role: data.role || 'participant',
        reviewed: Boolean(data.reviewed),
        certified: Boolean(data.certified),
        omniauthProvider: data.omniauth_provider || '',
        omniauthUid: data.omniauth_uid || '',
        omniauthEmail: data.omniauth_email || '',
        omniauthUsername: data.omniauth_username || '',
      });

      if (isCreateMode) {
        window.location.search = `?id=${encodeURIComponent(data.id)}`;
      }
    } catch (e: any) {
      setError(e?.message || 'Save failed');
    } finally {
      setIsSaving(false);
    }
  }

  useEffect(() => {
    load();
  }, [id, mode]);

  return (
    <Box>
      <BlueTitleBar title="User Editor" />

      <Container maxW="5xl" py={6}>
        {!id && !isCreateMode && (
          <Box p={4} borderWidth="1px" borderRadius="md">
            <Text fontWeight="bold">Missing id</Text>
            <Text>Use: /user-editor?id=&lt;uuid&gt; or /user-editor?mode=create</Text>
          </Box>
        )}

        {(id || isCreateMode) && (
          <Box borderWidth="1px" borderRadius="lg" p={5} bg="white">
            <Flex align="center" justify="space-between" mb={4} gap={3} wrap="wrap">
              <Heading size="md">{isCreateMode ? 'Add User' : 'Update User'}</Heading>
              <Flex gap={2}>
                <Button onClick={load} variant="outline" isDisabled={isLoading || isSaving}>
                  Reload
                </Button>
                <Button onClick={save} colorScheme="blue" isLoading={isSaving} isDisabled={isLoading || !isDirty}>
                  Save
                </Button>
              </Flex>
            </Flex>

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
              <Flex direction="column" gap={6}>
                <Box>
                  <Heading size="sm" mb={4}>
                    Core Details
                  </Heading>
                  <SimpleGrid columns={{ base: 1, md: 2 }} spacing={4}>
                    <Box>
                      <Text fontSize="xs" opacity={0.7} mb={1}>
                        email
                      </Text>
                      <Input value={email} onChange={(e) => setEmail(e.target.value)} />
                    </Box>
                    <Box>
                      <Text fontSize="xs" opacity={0.7} mb={1}>
                        organization
                      </Text>
                      <Input value={organization} onChange={(e) => setOrganization(e.target.value)} />
                    </Box>
                    <Box>
                      <Text fontSize="xs" opacity={0.7} mb={1}>
                        first_name
                      </Text>
                      <Input value={firstName} onChange={(e) => setFirstName(e.target.value)} />
                    </Box>
                    <Box>
                      <Text fontSize="xs" opacity={0.7} mb={1}>
                        last_name
                      </Text>
                      <Input value={lastName} onChange={(e) => setLastName(e.target.value)} />
                    </Box>
                    <Box>
                      <Text fontSize="xs" opacity={0.7} mb={1}>
                        role
                      </Text>
                      <Select value={role} onChange={(e) => setRole(e.target.value)}>
                        {ROLE_OPTIONS.map((option) => (
                          <option key={option.value} value={option.value}>
                            {option.label}
                          </option>
                        ))}
                      </Select>
                    </Box>
                  </SimpleGrid>
                </Box>

                <Flex gap={6} wrap="wrap">
                  <Checkbox isChecked={reviewed} onChange={(e) => setReviewed(e.target.checked)}>
                    reviewed
                  </Checkbox>
                  <Checkbox isChecked={certified} onChange={(e) => setCertified(e.target.checked)}>
                    certified
                  </Checkbox>
                </Flex>

                <Divider />

                <Box>
                  <Heading size="sm" mb={4}>
                    Authentication Details
                  </Heading>
                  <SimpleGrid columns={{ base: 1, md: 2 }} spacing={4}>
                    <Box>
                      <Text fontSize="xs" opacity={0.7} mb={1}>
                        omniauth_provider
                      </Text>
                      <Input value={omniauthProvider} onChange={(e) => setOmniauthProvider(e.target.value)} />
                    </Box>
                    <Box>
                      <Text fontSize="xs" opacity={0.7} mb={1}>
                        omniauth_email
                      </Text>
                      <Input value={omniauthEmail} onChange={(e) => setOmniauthEmail(e.target.value)} />
                    </Box>
                    <Box>
                      <Text fontSize="xs" opacity={0.7} mb={1}>
                        omniauth_username
                      </Text>
                      <Input value={omniauthUsername} onChange={(e) => setOmniauthUsername(e.target.value)} />
                    </Box>
                    <Box>
                      <Text fontSize="xs" opacity={0.7} mb={1}>
                        omniauth_uid
                      </Text>
                      <Input value={omniauthUid} onChange={(e) => setOmniauthUid(e.target.value)} fontFamily="mono" />
                    </Box>
                  </SimpleGrid>
                </Box>

                <Divider />

                <Box>
                  <Heading size="sm" mb={4}>
                    Activity
                  </Heading>
                  <Box>
                    <SimpleGrid columns={{ base: 1, md: 3 }} spacing={4}>
                      <ReadOnlyField label="id" value={record?.id} />
                      <ReadOnlyField label="name" value={record?.name} />
                      <ReadOnlyField label="confirmed_at" value={fmtTs(record?.confirmed_at)} />
                      <ReadOnlyField label="last_sign_in_at" value={fmtTs(record?.last_sign_in_at)} />
                      <ReadOnlyField label="sign_in_count" value={record?.sign_in_count} />
                      <ReadOnlyField label="unconfirmed_email" value={record?.unconfirmed_email} />
                      <ReadOnlyField label="invitation_sent_at" value={fmtTs(record?.invitation_sent_at)} />
                      <ReadOnlyField label="invitation_accepted_at" value={fmtTs(record?.invitation_accepted_at)} />
                      <ReadOnlyField label="created_at" value={fmtTs(record?.created_at)} />
                      <ReadOnlyField label="updated_at" value={fmtTs(record?.updated_at)} />
                    </SimpleGrid>
                  </Box>
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
