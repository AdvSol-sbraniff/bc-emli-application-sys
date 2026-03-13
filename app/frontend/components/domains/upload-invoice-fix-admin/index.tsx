import React, { useRef, useState } from 'react';
import { Box, Button, Container, Flex, HStack, Input, Spinner, Text } from '@chakra-ui/react';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { useLocation } from 'react-router-dom';

function getParam(search: string, key: string): string {
  return new URLSearchParams(search).get(key) ?? '';
}

export default function UploadInvoiceFixAdminScreen() {
  const location = useLocation();

  const invoiceId = getParam(location.search, 'invoice_id');
  const sessionId = getParam(location.search, 'session_id');
  const latestInvoiceVersionId = getParam(location.search, 'latest_invoice_version_id');
  const latestInvoiceVersionNo = getParam(location.search, 'latest_invoice_versionno');
  const contractorBusinessName = getParam(location.search, 'contractor_business_name');
  const diOcrInvoiceId = getParam(location.search, 'di_ocr_invoice_id');

  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const [selectedFileName, setSelectedFileName] = useState('');
  const [isUploading, setIsUploading] = useState(false);
  const [error, setError] = useState('');
  const [okMessage, setOkMessage] = useState('');
  const [newInvoiceVersionId, setNewInvoiceVersionId] = useState('');
  const [newInvoiceVersionNo, setNewInvoiceVersionNo] = useState('');

  const openFileChooser = () => {
    setError('');
    setOkMessage('');

    if (!invoiceId.trim()) {
      setError('Missing invoice_id context. Please open this screen from Invoices Admin.');
      return;
    }

    fileInputRef.current?.click();
  };

  const uploadFixPdf = async (file: File) => {
    setIsUploading(true);
    setError('');
    setOkMessage('');
    setNewInvoiceVersionId('');
    setNewInvoiceVersionNo('');

    try {
      const endpoint = `/api/claims/invoices/${encodeURIComponent(invoiceId)}/upload_fix`;
      const form = new FormData();
      form.append('invoice_id', invoiceId);
      form.append('pdfs[]', file, file.name);

      const res = await fetch(endpoint, {
        method: 'POST',
        credentials: 'include',
        body: form,
      });

      const data = await res.json().catch(() => ({}));

      if (!res.ok || data?.ok === false) {
        throw new Error(data?.error || data?.message || `HTTP ${res.status} ${res.statusText}`);
      }

      const nextVersionId = data?.invoice_version_id ? String(data.invoice_version_id) : '';
      const nextVersionNo = data?.invoice_versionno !== undefined && data?.invoice_versionno !== null ? String(data.invoice_versionno) : '';

      setNewInvoiceVersionId(nextVersionId);
      setNewInvoiceVersionNo(nextVersionNo);
      setOkMessage(String(data?.message || 'Upload fix accepted.'));
    } catch (e: any) {
      setError(e?.message || 'Upload fix failed.');
    } finally {
      setIsUploading(false);
    }
  };

  const handleFileChosen = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = (e.target.files || [])[0] || null;
    e.target.value = '';
    if (!file) return;

    setSelectedFileName(file.name);
    await uploadFixPdf(file);
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Upload Invoice Fix" />

      <Container maxW="container.lg" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Box mb={4} p={3} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="gray.50">
            <Text fontSize="sm" fontWeight="bold" mb={2}>Context (selected invoice)</Text>
            <Text fontSize="sm">invoice_id: {invoiceId || '—'}</Text>
            <Text fontSize="sm">session_id: {sessionId || '—'}</Text>
            <Text fontSize="sm">contractor name: {contractorBusinessName || '—'}</Text>
            <Text fontSize="sm">invoice # (DI): {diOcrInvoiceId || '—'}</Text>
            <Text fontSize="sm">latest invoice_version_id: {latestInvoiceVersionId || '—'}</Text>
            <Text fontSize="sm">latest invoice_versionno: {latestInvoiceVersionNo || '—'}</Text>
          </Box>

          <HStack spacing={3} mb={3}>
            <Button onClick={openFileChooser} isDisabled={!invoiceId.trim() || isUploading}>
              choose pdf to upload fix
            </Button>
            {isUploading && <Spinner size="sm" />}
          </HStack>

          <Input ref={fileInputRef} type="file" accept="application/pdf,.pdf" display="none" onChange={handleFileChosen} />

          {!!selectedFileName && (
            <Text fontSize="sm" mb={2}>selected file: {selectedFileName}</Text>
          )}

          {!!error && (
            <Box mb={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
              <Text fontSize="sm" color="red.700">{error}</Text>
            </Box>
          )}

          {!!okMessage && (
            <Box mb={3} p={3} bg="green.50" borderWidth="1px" borderColor="green.200" borderRadius="md">
              <Text fontSize="sm" color="green.700">{okMessage}</Text>
              <Text fontSize="sm">new invoice_version_id: {newInvoiceVersionId || '—'}</Text>
              <Text fontSize="sm">new invoice_versionno: {newInvoiceVersionNo || '—'}</Text>
            </Box>
          )}
        </Box>
      </Container>
    </Flex>
  );
}
